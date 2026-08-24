$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot
$build = Join-Path $root 'build'
$vectors = Join-Path $root 'vectors'
$results = Join-Path $root 'results'
$tests = Join-Path $root 'tests'
$source = Join-Path $root 'src'
$tools = Join-Path $root 'tools'
$vivadoBin = 'D:\2025.2\Vivado\bin'
$xvlog = Join-Path $vivadoBin 'xvlog.bat'
$inv = [Globalization.CultureInfo]::InvariantCulture

function Assert-ExitCode([string]$Step) {
    if ($LASTEXITCODE -ne 0) {
        throw "$Step failed with exit code $LASTEXITCODE"
    }
}

function Read-Result([string]$Path, [string]$Label) {
    $line = Get-Content -LiteralPath $Path |
        Where-Object { $_ -match ('^' + [regex]::Escape($Label) + '\s') } |
        Select-Object -Last 1
    if ($null -eq $line) {
        throw "Missing $Label in $Path"
    }

    $values = @{}
    foreach ($match in [regex]::Matches($line, '([A-Za-z_]+)=([^\s]+)')) {
        $values[$match.Groups[1].Value] = $match.Groups[2].Value
    }
    return $values
}

function Number([string]$Value) {
    return [double]::Parse($Value, $inv)
}

function Fixed([double]$Value, [int]$Digits) {
    return $Value.ToString("F$Digits", $inv)
}

function Run-PowerShell([string]$Script, [string]$Step) {
    & powershell.exe '-NoProfile' '-ExecutionPolicy' 'Bypass' '-File' $Script
    Assert-ExitCode $Step
}

New-Item -ItemType Directory -Force -Path $build, $vectors, $results | Out-Null

$gcc = Get-Command gcc.exe -ErrorAction Stop
$openssl = Get-Command openssl.exe -ErrorAction Stop
$objdump = Get-Command objdump.exe -ErrorAction Stop
if (-not (Test-Path -LiteralPath $xvlog -PathType Leaf)) {
    throw "Vivado 2025.2 simulator not found: $xvlog"
}

$generator = Join-Path $build 'generate_vectors.exe'
$generatorArgs = @(
    '-std=c11', '-O2', '-Wall', '-Wextra', '-Wpedantic',
    (Join-Path $tools 'generate_vectors.c'), '-o', $generator, '-lcrypto'
)
& $gcc.Source @generatorArgs
Assert-ExitCode 'OpenSSL vector generator build'
& $generator $vectors
Assert-ExitCode 'OpenSSL vector generation'
Run-PowerShell (Join-Path $tests 'test_vectors.ps1') 'Vector structure test'

$scalarFlags = @(
    '-std=c11', '-O3', '-Wall', '-Wextra', '-Wpedantic',
    '-fno-tree-vectorize', '-fno-tree-slp-vectorize',
    '-mno-aes', '-mno-pclmul', '-mno-avx', '-mno-avx2'
)

$aesTest = Join-Path $build 'test_aes256.exe'
$aesTestArgs = $scalarFlags + @(
    '-I', $source,
    (Join-Path $tests 'test_aes256.c'),
    (Join-Path $source 'aes256.c'),
    '-o', $aesTest
)
& $gcc.Source @aesTestArgs
Assert-ExitCode 'Pure C AES-256 test build'
& $aesTest
Assert-ExitCode 'Pure C AES-256 FIPS test'

$benchmark = Join-Path $build 'c_benchmark.exe'
$benchmarkArgs = $scalarFlags + @(
    '-I', $source,
    (Join-Path $source 'c_benchmark.c'),
    (Join-Path $source 'aes256.c'),
    '-o', $benchmark
)
& $gcc.Source @benchmarkArgs
Assert-ExitCode 'Pure C AES-256 benchmark build'

& powershell.exe '-NoProfile' '-ExecutionPolicy' 'Bypass' '-File' (Join-Path $tests 'test_forbidden_instructions.ps1') '-Binary' $benchmark
Assert-ExitCode 'CPU crypto instruction audit'
Run-PowerShell (Join-Path $tests 'test_c_benchmark.ps1') 'C benchmark test'
Run-PowerShell (Join-Path $tests 'test_rtl_provenance.ps1') 'RTL provenance test'
Run-PowerShell (Join-Path $tests 'test_rtl_results.ps1') 'RTL benchmark test'

$cResultPath = Join-Path $results 'c_results.txt'
$rtlResultPath = Join-Path $results 'rtl_results.txt'
$cIncluded = Read-Result $cResultPath 'C_KEY_INCLUDED'
$cExcluded = Read-Result $cResultPath 'C_KEY_EXCLUDED'
$rtlIncluded = Read-Result $rtlResultPath 'RTL_KEY_INCLUDED'
$rtlExcluded = Read-Result $rtlResultPath 'RTL_KEY_EXCLUDED'
$rtlClock = Read-Result $rtlResultPath 'RTL_CLOCK'

$blocks = Number $cIncluded.blocks
$frequency = Number $rtlClock.frequency_hz
$cIncludedSeconds = Number $cIncluded.seconds
$cExcludedSeconds = Number $cExcluded.seconds
$rtlIncludedCycles = Number $rtlIncluded.cycles
$rtlExcludedCycles = Number $rtlExcluded.cycles
$rtlIncludedSeconds = $rtlIncludedCycles / $frequency
$rtlExcludedSeconds = $rtlExcludedCycles / $frequency
$rtlIncludedNs = $rtlIncludedSeconds * 1e9 / $blocks
$rtlExcludedNs = $rtlExcludedSeconds * 1e9 / $blocks
$rtlIncludedGbps = $blocks * 128.0 / $rtlIncludedSeconds / 1e9
$rtlExcludedGbps = $blocks * 128.0 / $rtlExcludedSeconds / 1e9
$includedSpeedup = $cIncludedSeconds / $rtlIncludedSeconds
$excludedSpeedup = $cExcludedSeconds / $rtlExcludedSeconds

$cpuName = (Get-ItemProperty -LiteralPath 'HKLM:\HARDWARE\DESCRIPTION\System\CentralProcessor\0' -Name 'ProcessorNameString').ProcessorNameString.Trim()
$gccVersion = (& $gcc.Source '--version' | Select-Object -First 1).Trim()
$opensslVersion = (& $openssl.Source 'version' | Select-Object -First 1).Trim()
$objdumpVersion = (& $objdump.Source '--version' | Select-Object -First 1).Trim()
Push-Location $build
try {
    $vivadoVersion = (& $xvlog '--version' | Select-Object -First 1).Trim()
}
finally {
    Pop-Location
}
$timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss K'
$sourceRtl = 'D:\git\vivado_25.2_win\aes\AES_GCM_TX_PL_DIRECT_260811_1826\vivado\rtl\aes256_gcm'
$timingReport = 'D:\git\vivado_25.2_win\aes\AES_GCM_TX_PL_DIRECT_260811_1826\vivado\artifacts\timing_summary.rpt'

$report = @(
    '# AES-256 pure C versus FPGA core results',
    '',
    "- Run time: $timestamp",
    "- CPU: $cpuName (pinned to logical CPU 0)",
    "- C compiler: $gccVersion",
    "- OpenSSL golden generator: $opensslVersion",
    "- Disassembly audit: $objdumpVersion",
    "- FPGA simulator: $vivadoVersion",
    '- FPGA clock: 150 MHz (6.667 ns)',
    "- Original AES RTL: $sourceRtl",
    "- Post-route timing evidence: $timingReport (WNS 0.095 ns, all constraints met)",
    '',
    '## Main results',
    '',
    '| Condition | Pure C total (ms) | FPGA total (ms) | Pure C (ns/block) | FPGA (ns/block) | Pure C (Gbps) | FPGA (Gbps) | FPGA speedup |',
    '|---|---:|---:|---:|---:|---:|---:|---:|',
    "| Key expansion included | $(Fixed ($cIncludedSeconds * 1000.0) 6) | $(Fixed ($rtlIncludedSeconds * 1000.0) 6) | $(Fixed (Number $cIncluded.ns_per_block) 3) | $(Fixed $rtlIncludedNs 3) | $(Fixed (Number $cIncluded.gbps) 6) | $(Fixed $rtlIncludedGbps 6) | $(Fixed $includedSpeedup 3)x |",
    "| Key expansion excluded | $(Fixed ($cExcludedSeconds * 1000.0) 6) | $(Fixed ($rtlExcludedSeconds * 1000.0) 6) | $(Fixed (Number $cExcluded.ns_per_block) 3) | $(Fixed $rtlExcludedNs 3) | $(Fixed (Number $cExcluded.gbps) 6) | $(Fixed $rtlExcludedGbps 6) | $(Fixed $excludedSpeedup 3)x |",
    '',
    'FPGA speedup is pure-C total time divided by FPGA total time. A value above 1 means the FPGA is faster.',
    '',
    '## Correctness',
    '',
    '| Comparison | Key expansion included | Key expansion excluded |',
    '|---|---:|---:|',
    "| Pure C versus OpenSSL | $($cIncluded.matches)/10000 | $($cExcluded.matches)/10000 |",
    "| FPGA RTL versus OpenSSL | $($rtlIncluded.matches)/10000 | $($rtlExcluded.matches)/10000 |",
    '',
    '- FIPS-197 AES-256 single-block KAT: PASS in OpenSSL, pure C, and FPGA RTL',
    '- Forbidden CPU instructions: 0 AESENC/AESDEC/AESKEYGENASSIST/VAES/PCLMUL-family instructions',
    '- Pure-C build: compiler auto-vectorization and AES/CLMUL/AVX/AVX2 disabled',
    '',
    '## FPGA cycle measurements',
    '',
    '| Condition | Total cycles for 10,000 blocks | Continuous cycles/block | Single-operation latency |',
    '|---|---:|---:|---:|',
    "| Key expansion included | $([long]$rtlIncludedCycles) | $(Fixed ($rtlIncludedCycles / $blocks) 4) | 41 cycles (key 27 + block 14) |",
    "| Key expansion excluded | $([long]$rtlExcludedCycles) | $(Fixed ($rtlExcludedCycles / $blocks) 4) | 14 cycles |",
    '',
    'Total time and throughput use the measured cycle count from continuous valid/ready traffic.',
    '',
    '## Scope and fairness',
    '',
    '- Both sides process the same 10,000 AES-256 ECB single-block records.',
    '- Included mode expands a distinct 256-bit key for every record and encrypts one block.',
    '- Excluded mode expands or loads the same fixed key once before timing and encrypts 10,000 blocks.',
    '- File I/O, vector generation, OpenSSL, compilation, RTL elaboration, and simulator wall time are not timed.',
    '- OpenSSL creates expected ciphertext and runs KATs only; its speed is not part of the comparison.',
    '- FPGA time converts RTL handshake cycles using the original implemented design post-route 150 MHz clock.',
    '- C time is the median of 11 runs of 10,000 blocks after warm-up, pinned to CPU 0.'
)

$reportPath = Join-Path $results 'comparison.md'
$report | Set-Content -LiteralPath $reportPath -Encoding utf8
Write-Output "Comparison report: $reportPath"
Write-Output "FPGA speedup: key-included=$(Fixed $includedSpeedup 3)x key-excluded=$(Fixed $excludedSpeedup 3)x"
