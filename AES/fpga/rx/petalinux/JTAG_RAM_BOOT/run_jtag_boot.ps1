param(
    [string]$Port,
    [string]$Xsdb,
    [string]$CableSerial,
    [int]$Seconds = 300
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

function ConvertTo-PowerShellLiteral {
    param([Parameter(Mandatory)][string]$Value)
    return "'" + $Value.Replace("'", "''") + "'"
}

$Port = Get-Setting $Port @('AES_GCM_RX_COM_PORT', 'AES_GCM_COM_PORT') 'COM12'
$Xsdb = Get-Setting $Xsdb @('AES_GCM_RX_XSDB', 'AES_GCM_XSDB') ''
$CableSerial = Get-Setting $CableSerial @('AES_GCM_RX_CABLE_SERIAL', 'AES_GCM_JTAG_CABLE_SERIAL') '210351BE7D5BA'

if ($Seconds -le 0) {
    throw '-Seconds must be greater than zero.'
}
if ([string]::IsNullOrWhiteSpace($CableSerial)) {
    throw 'JTAG cable serial must not be empty.'
}
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$serialScript = Join-Path $here 'uboot_direct_boot_serial.ps1'
$tcl = Join-Path $here 'jtag_boot_ram_direct.tcl'
if ($Xsdb) {
    if (-not (Test-Path -LiteralPath $Xsdb -PathType Leaf)) {
        throw "XSDB not found: $Xsdb"
    }
    $xsdbPath = (Resolve-Path -LiteralPath $Xsdb).Path
} else {
    $xsdbCommand = Get-Command 'xsdb.bat', 'xsdb' -ErrorAction SilentlyContinue |
        Select-Object -First 1
    if (-not $xsdbCommand) {
        throw 'XSDB is not on PATH. Use a Vitis 2025.2 shell or pass -Xsdb <path-to-xsdb.bat>.'
    }
    $xsdbPath = $xsdbCommand.Source
}

$childCommand = @(
    '&', (ConvertTo-PowerShellLiteral $serialScript),
    '-Port', (ConvertTo-PowerShellLiteral $Port),
    '-Seconds', $Seconds,
    '-RequireBootCycle'
) -join ' '
$encodedChildCommand = [Convert]::ToBase64String(
    [Text.Encoding]::Unicode.GetBytes($childCommand)
)
$serial = Start-Process powershell -ArgumentList @(
    '-NoProfile', '-ExecutionPolicy', 'Bypass',
    '-EncodedCommand', $encodedChildCommand
) -PassThru -WindowStyle Hidden
Start-Sleep -Milliseconds 1500
$previousCableSerial = $env:AES_GCM_JTAG_CABLE_SERIAL
try {
    $env:AES_GCM_JTAG_CABLE_SERIAL = $CableSerial
    Write-Host "RX JTAG: cable=$CableSerial port=$Port; Linux releases UART to PC telemetry"
    & $xsdbPath $tcl
    if ($LASTEXITCODE -ne 0) { throw 'XSDB JTAG boot failed' }
} finally {
    $env:AES_GCM_JTAG_CABLE_SERIAL = $previousCableSerial
}
$serial.WaitForExit()
if ($serial.ExitCode -ne 0) { throw 'Serial boot automation failed' }
