param(
    [string]$Port,
    [int]$Seconds = 180,
    [switch]$RequireBootCycle
)

$ErrorActionPreference = 'Stop'

function Get-Setting {
    param(
        [string]$ExplicitValue,
        [string[]]$EnvironmentNames,
        [string]$DefaultValue
    )

    if (-not [string]::IsNullOrWhiteSpace($ExplicitValue)) {
        return $ExplicitValue
    }
    foreach ($name in $EnvironmentNames) {
        $value = [Environment]::GetEnvironmentVariable($name)
        if (-not [string]::IsNullOrWhiteSpace($value)) {
            return $value
        }
    }
    return $DefaultValue
}

$Port = Get-Setting $Port @('AES_GCM_RX_COM_PORT', 'AES_GCM_COM_PORT') 'COM12'

if ($Seconds -le 0) { throw '-Seconds must be greater than zero.' }

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$logPath = Join-Path $here 'uboot_serial.log'
$statusPath = Join-Path $here 'jtag_boot_status.txt'
if ($Port.StartsWith('D2XX:', [StringComparison]::OrdinalIgnoreCase)) {
    . (Join-Path $here 'd2xx_serial_transport.ps1')
    $serialNumber = $Port.Substring('D2XX:'.Length)
    $serial = [D2xxSerialTransport]::new($serialNumber)
} else {
    $serial = [System.IO.Ports.SerialPort]::new(
        $Port, 115200, [System.IO.Ports.Parity]::None, 8,
        [System.IO.Ports.StopBits]::One
    )
}
$serial.ReadTimeout = 100
$serial.WriteTimeout = 1000
$serial.DtrEnable = $false
$serial.RtsEnable = $false
$openDeadline = [DateTime]::UtcNow.AddSeconds(15)
while ($true) {
    try {
        $serial.Open()
        break
    } catch {
        if ([DateTime]::UtcNow -ge $openDeadline) { throw }
        Start-Sleep -Milliseconds 250
    }
}
$serial.DiscardInBuffer()
# Wake or interrupt U-Boot. Linux never consumes this byte because JTAG reset
# precedes the boot command.
$serial.Write("`r")

$all = [Text.StringBuilder]::new()
$tail = ''
$stopped = $false
$bootargsSent = $false
$bootmSent = $false
$bootComplete = $false
$deadline = [DateTime]::UtcNow.AddSeconds($Seconds)
$nextBreakAttempt = [DateTime]::UtcNow

try {
    while ([DateTime]::UtcNow -lt $deadline) {
        if ($RequireBootCycle -and -not $stopped -and
            [DateTime]::UtcNow -ge $nextBreakAttempt) {
            # Transmit before and throughout the short U-Boot countdown.  Any
            # spaces seen by the old Linux shell are discarded by JTAG reset.
            $serial.Write(' ')
            $nextBreakAttempt = [DateTime]::UtcNow.AddMilliseconds(100)
        }
        $chunk = $serial.ReadExisting()
        if ($chunk) {
            [void]$all.Append($chunk)
            Write-Host -NoNewline $chunk
            $tail += $chunk
            if ($tail.Length -gt 8192) {
                $tail = $tail.Substring($tail.Length - 8192)
            }
        }
        if (-not $stopped -and $tail -match 'Hit any key to stop autoboot') {
            $serial.Write(' ')
            $stopped = $true
        }
        if (-not $stopped -and
            $tail -match '(?m)(Zynq|zynq-uboot)>\s*$') {
            $stopped = $true
        }
        if (-not $stopped -and $tail -match 'BOOTP broadcast') {
            # Recover when the countdown was missed and U-Boot has already
            # entered its network-boot retry loop.
            $serial.Write([string][char]3)
            $stopped = $true
            $tail = ''
        }
        if ($stopped -and -not $bootargsSent -and
            $tail -match '(?m)(Zynq|zynq-uboot)>\s*$') {
            # Keep the relocated initrd/FDT below 384 MiB; 0x18000000..0x1fffffff
            # stays outside Linux for the RX network/video DMA buffers.
            $serial.Write("setenv bootm_low 0; setenv bootm_size 0x18000000; setenv initrd_high 0x17ffffff; setenv fdt_high 0x17ffffff; setenv bootargs root=/dev/ram0 rw mem=384M`r")
            $bootargsSent = $true
            $tail = ''
        } elseif ($bootargsSent -and -not $bootmSent -and
                  $tail -match '(?m)(Zynq|zynq-uboot)>\s*$') {
            $serial.Write("bootm 0x10000000:kernel-1 0x10000000:ramdisk-1 0x00100000`r")
            $bootmSent = $true
            # Linux intentionally has no ttyPS0 console. Release the COM port
            # immediately so the PC UI can auto-identify RX UART telemetry.
            $bootComplete = $true
            $tail = ''
            break
        }
        Start-Sleep -Milliseconds 20
    }
} finally {
    [IO.File]::WriteAllText($logPath, $all.ToString())
    $serial.Close()
}

$summary = "SPACE=$([int]$stopped) BOOTARGS=$([int]$bootargsSent) BOOTM=$([int]$bootmSent) UART_HANDOFF=$([int]$bootComplete)"
Write-Host "`n$summary"
[IO.File]::WriteAllText($statusPath,
    "$summary`r`n")
if (-not $bootComplete) { throw "Serial JTAG boot was not dispatched within $Seconds seconds" }
