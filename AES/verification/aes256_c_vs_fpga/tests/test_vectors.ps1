$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot
$expectedWidths = @{
    'keys.hex' = 64
    'plaintexts.hex' = 32
    'golden.hex' = 32
    'golden_fixed_key.hex' = 32
}

foreach ($name in $expectedWidths.Keys) {
    $path = Join-Path $root "vectors/$name"
    $lines = @(Get-Content -LiteralPath $path)
    if ($lines.Count -ne 10000) {
        throw "$name record count $($lines.Count), expected 10000"
    }
    $pattern = '^[0-9a-f]{' + $expectedWidths[$name] + '}$'
    foreach ($line in $lines) {
        if ($line -notmatch $pattern) {
            throw "$name contains malformed record: $line"
        }
    }
}

Write-Output 'Vector structure: PASS (4 files x 10000 records)'
