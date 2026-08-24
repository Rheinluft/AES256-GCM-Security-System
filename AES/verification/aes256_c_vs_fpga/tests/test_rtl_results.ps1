$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot
$runner = Join-Path $root 'scripts/run_rtl_sim.ps1'
$result = Join-Path $root 'results/rtl_results.txt'

& $runner
if ($LASTEXITCODE -ne 0) {
    throw "RTL simulation failed with exit code $LASTEXITCODE"
}

$text = Get-Content -Raw -LiteralPath $result
if ($text -notmatch 'RTL_FIPS PASS') {
    throw 'RTL FIPS AES-256 KAT failed'
}
if ($text -notmatch 'RTL_KEY_INCLUDED .*matches=10000') {
    throw 'Missing or invalid RTL key-included result'
}
if ($text -notmatch 'RTL_KEY_EXCLUDED .*matches=10000') {
    throw 'Missing or invalid RTL key-excluded result'
}

Write-Output 'RTL benchmark contract: PASS'
