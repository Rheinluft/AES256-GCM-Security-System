$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot
$rtl = Join-Path $root 'rtl'
$vectors = Join-Path $root 'vectors'
$sim = Join-Path $root 'build/rtl_sim'
$result = Join-Path $root 'results/rtl_results.txt'
$vivadoBin = 'D:\2025.2\Vivado\bin'
$xvlog = Join-Path $vivadoBin 'xvlog.bat'
$xelab = Join-Path $vivadoBin 'xelab.bat'
$xsim = Join-Path $vivadoBin 'xsim.bat'

foreach ($tool in @($xvlog, $xelab, $xsim)) {
    if (-not (Test-Path -LiteralPath $tool)) {
        throw "Vivado 2025.2 simulator tool not found: $tool"
    }
}

New-Item -ItemType Directory -Force -Path $sim, (Join-Path $sim 'vectors') | Out-Null
foreach ($name in @('keys.hex', 'plaintexts.hex', 'golden.hex', 'golden_fixed_key.hex')) {
    Copy-Item -LiteralPath (Join-Path $vectors $name) -Destination (Join-Path $sim "vectors/$name") -Force
}

$sources = @(
    (Join-Path $rtl 'aes_sbox_pkg.sv'),
    (Join-Path $rtl 'aes_key_rcon_pkg.sv'),
    (Join-Path $rtl 'aes_subword32.sv'),
    (Join-Path $rtl 'aes256_key_transform.sv'),
    (Join-Path $rtl 'aes_next_round_key.sv'),
    (Join-Path $rtl 'aes256_key_expansion.sv'),
    (Join-Path $rtl 'aes_addroundkey.sv'),
    (Join-Path $rtl 'aes_subbytes.sv'),
    (Join-Path $rtl 'aes_shiftrows.sv'),
    (Join-Path $rtl 'aes_mixcolumns.sv'),
    (Join-Path $rtl 'aes_round.sv'),
    (Join-Path $rtl 'aes256_iterative_core.sv'),
    (Join-Path $rtl 'tb_aes256_compare.sv')
)

Push-Location $sim
try {
    & $xvlog '--sv' '--relax' @sources
    if ($LASTEXITCODE -ne 0) {
        throw "xvlog failed with exit code $LASTEXITCODE"
    }

    & $xelab '--relax' '--snapshot' 'aes256_compare_sim' 'work.tb_aes256_compare'
    if ($LASTEXITCODE -ne 0) {
        throw "xelab failed with exit code $LASTEXITCODE"
    }

    $output = & $xsim 'aes256_compare_sim' '-runall' 2>&1
    $exitCode = $LASTEXITCODE
    $output | Set-Content -LiteralPath $result
    $output | Write-Output
    if ($exitCode -ne 0) {
        throw "xsim failed with exit code $exitCode"
    }
}
finally {
    Pop-Location
}
