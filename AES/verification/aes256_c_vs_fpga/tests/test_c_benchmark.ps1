$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot
$binary = Join-Path $root 'build/c_benchmark.exe'
$vectors = Join-Path $root 'vectors'
$result = Join-Path $root 'results/c_results.txt'

& $binary $vectors 0 | Set-Content -LiteralPath $result
if ($LASTEXITCODE -ne 0) {
    throw "C benchmark failed with exit code $LASTEXITCODE"
}

$text = Get-Content -Raw -LiteralPath $result
if ($text -notmatch 'C_KEY_INCLUDED .*matches=10000') {
    throw 'Missing or invalid C key-included result'
}
if ($text -notmatch 'C_KEY_EXCLUDED .*matches=10000') {
    throw 'Missing or invalid C key-excluded result'
}

Write-Output 'C benchmark contract: PASS'
