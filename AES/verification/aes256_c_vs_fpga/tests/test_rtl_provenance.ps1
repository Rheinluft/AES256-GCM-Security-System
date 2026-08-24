$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot
$rtlDir = Join-Path $root 'rtl'
$manifest = Join-Path $rtlDir 'SHA256SUMS'
$sourceDir = 'D:\git\vivado_25.2_win\aes\AES_GCM_TX_PL_DIRECT_260811_1826\vivado\rtl\aes256_gcm'
$expectedNames = @(
    'aes_sbox_pkg.sv',
    'aes_key_rcon_pkg.sv',
    'aes_subword32.sv',
    'aes256_key_transform.sv',
    'aes_next_round_key.sv',
    'aes256_key_expansion.sv',
    'aes_addroundkey.sv',
    'aes_subbytes.sv',
    'aes_shiftrows.sv',
    'aes_mixcolumns.sv',
    'aes_round.sv',
    'aes256_iterative_core.sv'
)

if (-not (Test-Path -LiteralPath $manifest)) {
    throw 'Missing RTL provenance manifest'
}

$entries = @{}
foreach ($line in Get-Content -LiteralPath $manifest) {
    if ($line -notmatch '^([0-9a-f]{64})  (.+\.sv)$') {
        throw "Malformed manifest line: $line"
    }
    $entries[$Matches[2]] = $Matches[1]
}

if ($entries.Count -ne $expectedNames.Count) {
    throw "Manifest entry count $($entries.Count), expected $($expectedNames.Count)"
}

foreach ($name in $expectedNames) {
    if (-not $entries.ContainsKey($name)) {
        throw "Missing manifest entry: $name"
    }
    $copy = Join-Path $rtlDir $name
    $source = Join-Path $sourceDir $name
    $copyHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $copy).Hash.ToLowerInvariant()
    $sourceHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $source).Hash.ToLowerInvariant()
    if ($copyHash -ne $entries[$name] -or $sourceHash -ne $entries[$name]) {
        throw "RTL provenance mismatch: $name"
    }
}

Write-Output 'RTL provenance: PASS (12 byte-identical TX source files)'
