param(
    [Parameter(Mandatory = $true)]
    [string]$Binary
)

$ErrorActionPreference = 'Stop'

if (-not (Test-Path -LiteralPath $Binary -PathType Leaf)) {
    throw "Benchmark binary not found: $Binary"
}

$objdump = Get-Command objdump.exe -ErrorAction Stop
$disassembly = & $objdump.Source '-d' $Binary 2>&1
if ($LASTEXITCODE -ne 0) {
    throw "objdump failed with exit code $LASTEXITCODE"
}

$forbiddenMnemonic = '(?i)\b(?:aesenc|aesenclast|aesdec|aesdeclast|aesimc|aeskeygenassist|vaesenc|vaesenclast|vaesdec|vaesdeclast|pclmulqdq|vpclmulqdq)\b'
$matches = @($disassembly | Select-String -Pattern $forbiddenMnemonic)
if ($matches.Count -ne 0) {
    $details = $matches -join [Environment]::NewLine
    throw "Forbidden CPU crypto instructions found:`n$details"
}

Write-Output 'Forbidden CPU crypto instructions: PASS (0 found)'
