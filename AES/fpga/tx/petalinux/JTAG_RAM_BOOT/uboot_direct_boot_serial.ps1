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

$Port = Get-Setting $Port @('AES_GCM_TX_COM_PORT', 'AES_GCM_COM_PORT') 'COM9'

if ($Seconds -le 0) { throw '-Seconds must be greater than zero.' }

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$logPath = Join-Path $here 'uboot_serial.log'
$statusPath = Join-Path $here 'jtag_boot_status.txt'
$setupCommand = "sleep 8; ip -4 -br addr; if [ -c /dev/media0 ] && [ -c /dev/video0 ] && [ ! -e /dev/pcam_aes_bridge ]; then printf '\n__PL_DIRECT_PCAM_PRESENT__\n'; else printf '\n__PL_DIRECT_PCAM_ABSENT__\n'; fi; printf '\n__PCAM_JTAG_READY__\n'"
$serial = [System.IO.Ports.SerialPort]::new(
    $Port, 115200, [System.IO.Ports.Parity]::None, 8,
    [System.IO.Ports.StopBits]::One
)
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
# Also support attaching after Linux has already reached the login prompt (for
# example, a first boot that spent longer than expected generating SSH keys).
$serial.Write("`r")

$all = [Text.StringBuilder]::new()
$tail = ''
$stopped = $false
$bootargsSent = $false
$bootmSent = $false
$loginSent = $false
$loginPasswordSent = $false
$currentPasswordSent = $false
$newPasswordSent = $false
$retypePasswordSent = $false
$ipCommandSent = $false
$bootComplete = $false
$pcamChecked = $false
$pcamPresent = $false
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
        if (-not $pcamChecked -and $tail -match '(?m)^__PL_DIRECT_PCAM_PRESENT__\r?$') {
            $pcamChecked = $true
            $pcamPresent = $true
        } elseif (-not $pcamChecked -and $tail -match '(?m)^__PL_DIRECT_PCAM_ABSENT__\r?$') {
            $pcamChecked = $true
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
            $serial.Write("setenv bootargs console=ttyPS0,115200 earlycon root=/dev/ram0 rw mem=384M`r")
            $bootargsSent = $true
            $tail = ''
        } elseif ($bootargsSent -and -not $bootmSent -and
                  $tail -match '(?m)(Zynq|zynq-uboot)>\s*$') {
            # Keep the FIT ramdisk and DTB below the mem=384M Linux limit.
            # The upper 128 MiB beginning at 0x18000000 is reserved for PL DMA.
            $serial.Write("setenv initrd_high 0x16ffffff; setenv fdt_high 0x17ffffff; bootm 0x10000000:kernel-1 0x10000000:ramdisk-1 0x00100000`r")
            $bootmSent = $true
            $tail = ''
        } elseif ((-not $RequireBootCycle -or $bootmSent) -and
                  -not $loginSent -and
                  $tail -match '(?im)login:\s*$') {
            $serial.Write("petalinux`r")
            $loginSent = $true
            $tail = ''
        } elseif ($loginSent -and -not $retypePasswordSent -and
                  $tail -match '(?im)retype new password:\s*$') {
            $serial.Write("peta`r")
            $retypePasswordSent = $true
            $tail = ''
        } elseif ($loginSent -and -not $newPasswordSent -and
                  $tail -match '(?im)new password:\s*$') {
            $serial.Write("peta`r")
            $newPasswordSent = $true
            $tail = ''
        } elseif ($loginSent -and -not $currentPasswordSent -and
                  $tail -match '(?im)current password:\s*$') {
            $serial.Write("peta`r")
            $currentPasswordSent = $true
            $tail = ''
        } elseif (-not $ipCommandSent -and $loginSent -and
                  -not $loginPasswordSent -and
                  $tail -match '(?im)password:\s*$') {
            $serial.Write("peta`r")
            $loginPasswordSent = $true
            $tail = ''
        } elseif ((-not $RequireBootCycle -or $bootmSent) -and
                  -not $ipCommandSent -and
                  $tail -match '(?m)[$#]\s*$') {
            $serial.Write("$setupCommand`r")
            $ipCommandSent = $true
            $tail = ''
        } elseif ($ipCommandSent -and $tail -match '(?m)^__PCAM_JTAG_READY__\r?$') {
            $bootComplete = $true
            break
        }
        Start-Sleep -Milliseconds 20
    }
} finally {
    [IO.File]::WriteAllText($logPath, $all.ToString())
    $serial.Close()
}

$summary = "SPACE=$([int]$stopped) BOOTARGS=$([int]$bootargsSent) BOOTM=$([int]$bootmSent) LOGIN=$([int]$loginSent) READY=$([int]$bootComplete) PCAM_CHECKED=$([int]$pcamChecked) PCAM=$([int]$pcamPresent)"
Write-Host "`n$summary"
[IO.File]::WriteAllText($statusPath,
    "$summary`r`n")
if (-not $bootComplete) { throw "Serial JTAG boot did not reach the Linux shell within $Seconds seconds" }
if (-not $pcamChecked) { throw 'TX boot completed without a Pcam device check result' }
if (-not $pcamPresent) { throw 'TX PL-direct image did not expose media/video devices or still exposed the removed legacy bridge' }
