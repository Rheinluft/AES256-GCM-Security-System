# ---------------------------------------------------------------------------
# AES-256 ECB Known Answer Test (NIST AESAVS) - Vivado xsim launcher
#
#   .\run_aes_core_kat.ps1                    전체 405 벡터 검증 (파형 없음)
#   .\run_aes_core_kat.ps1 -DumpWave          파형 기록 + Vivado GUI 로 열기
#   .\run_aes_core_kat.ps1 -DumpWave -MaxVectors 20
#   .\run_aes_core_kat.ps1 -VivadoBin "C:\Xilinx\Vivado\2020.2\bin"
#
# 소스 목록은 aes256_core_kat.f 하나만 쓴다.  VCS 쪽(run_aes_core_kat.sh)도
# 같은 파일을 읽으므로 파일이 추가/삭제되어도 두 플로우가 어긋나지 않는다.
# ---------------------------------------------------------------------------
param(
    [string]$VivadoBin,
    [switch]$DumpWave,
    [int]$MaxVectors = 0,     # 0 = 405 벡터 전체
    [switch]$NoGui
)

$ErrorActionPreference = 'Stop'
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$root      = Split-Path -Parent $scriptDir          # uvm_verification/
$vectors   = Join-Path $root 'kat_vectors'

# 이 프로젝트는 Vivado 2025.2 를 기준으로 한다.  PATH 에 구버전(2020.2)이
# 잡혀 있어서, PATH 를 먼저 보면 GUI 프로젝트와 다른 시뮬레이터를 타게 된다.
# 설치 경로를 먼저 찾고, 못 찾을 때만 PATH 로 폴백한다.
$vivado = $VivadoBin
if (-not $vivado) {
    $candidates = @(
        'D:\2025.2\Vivado\bin',
        'C:\Xilinx\Vivado\2025.2\bin'
    )
    foreach ($c in $candidates) {
        if (Test-Path (Join-Path $c 'xvlog.bat')) { $vivado = $c; break }
    }
}
if (-not $vivado) {
    $xvlogCommand = Get-Command 'xvlog.bat', 'xvlog' -ErrorAction SilentlyContinue |
        Select-Object -First 1
    if (-not $xvlogCommand) {
        throw 'Vivado tools not found. Pass -VivadoBin <Vivado-bin-folder>.'
    }
    $vivado = Split-Path -Parent $xvlogCommand.Source
}

$verLine = (& (Join-Path $vivado 'xvlog.bat') --version 2>&1 | Select-Object -First 1)
if ($verLine -notmatch '2025') {
    Write-Warning "Vivado 2025.x 가 아닙니다: $verLine  ($vivado)"
}
Write-Host "simulator: $verLine  [$vivado]"

# VCS 쪽 Makefile 과 같은 filelist.f 를 읽는다.  파일이 추가/삭제되어도 두
# 시뮬레이터 플로우가 어긋나지 않는다.  경로는 root 기준 상대경로라 절대경로로
# 펼치고, VCS 스타일 주석(//)과 # 주석을 걸러낸다.
$filelist = Join-Path $root 'filelist.f'
$sources  = Get-Content $filelist |
    ForEach-Object { $_.Trim() } |
    Where-Object { $_ -ne '' -and -not $_.StartsWith('//') -and -not $_.StartsWith('#') } |
    ForEach-Object { Join-Path $root ($_ -replace '^\./', '') }

# 작업 디렉토리를 트리 밖에 두어 xsim 산출물이 소스를 오염시키지 않게 한다.
$work = Join-Path ([System.IO.Path]::GetTempPath()) 'pcam-aes-gcm\aes-core-kat'
New-Item -ItemType Directory -Path $work -Force | Out-Null

# TB 는 작업 디렉토리에서 .rsp 를 파일명만으로 연다.  xsim 2020.2 의
# -testplusarg 가 값 형태를 가리지 않고 거부해서, 경로를 인자로 넘기는 대신
# 벡터를 작업 디렉토리로 복사한다.  RX 쪽 캡처 프레임 TB 와 같은 방식이고,
# VCS 로 옮겨도 인용부호 문제 없이 그대로 동작한다.
Copy-Item (Join-Path $vectors '*.rsp') -Destination $work -Force

# xvlog.bat / xsim.bat 은 cmd 배치 래퍼라서 '=' 이 들어간 인자를 토큰 단위로
# 쪼갠다 (-d NAME=5 를 넘기면 '5' 를 파일명으로 착각하고, -testplusarg 도 같은
# 이유로 실패한다).  옵션 파일은 cmd 파싱을 거치지 않으므로 -f 로 넘긴다.
$xvlogOpts = @('-sv')
if ($DumpWave -and ($MaxVectors -ne 0)) {
    # 405 벡터 전체를 덤프해도 wdb 는 5.3 MB / 5 초 수준이라 기본값은 전체다.
    # 파형을 짧게 끊어 보고 싶을 때만 -MaxVectors 로 제한한다.
    $xvlogOpts += "-d KAT_MAX_VECTORS=$MaxVectors"
}
$xvlogOpts += ($sources | ForEach-Object { $_ -replace '\\', '/' })
$xvlogOpts | Set-Content -Path (Join-Path $work 'xvlog_opts.f') -Encoding ascii

$xelabArgs = @('tb_aes256_core_kat', '-timescale', '1ns/1ps', '-s', 'aes_core_kat_sim')
if ($DumpWave) {
    # -debug 없이 elaborate 하면 신호 프로빙이 비활성이라 log_wave 가 아무것도
    # 기록하지 못한다.  파형이 안 보이는 원인이 대개 이것이다.
    $xelabArgs += @('-debug', 'typical')
}

Push-Location $work
try {
    & (Join-Path $vivado 'xvlog.bat') -f 'xvlog_opts.f'
    if ($LASTEXITCODE -ne 0) { throw 'xvlog failed' }

    & (Join-Path $vivado 'xelab.bat') @xelabArgs
    if ($LASTEXITCODE -ne 0) { throw 'xelab failed' }

    if ($DumpWave) {
        # -runall 대신 tcl 배치를 쓴다.  log_wave 를 run 앞에 두어야 기록된다.
        @(
            'log_wave -recursive *'
            'run all'
            'quit'
        ) | Set-Content -Path 'dump.tcl' -Encoding ascii

        & (Join-Path $vivado 'xsim.bat') aes_core_kat_sim `
            -tclbatch 'dump.tcl' -wdb 'aes_core_kat.wdb' 2>&1 |
            Tee-Object -FilePath 'sim.log'
    } else {
        & (Join-Path $vivado 'xsim.bat') aes_core_kat_sim -runall 2>&1 |
            Tee-Object -FilePath 'sim.log'
    }
    if ($LASTEXITCODE -ne 0) { throw 'xsim failed' }

    # xsim 2020.2 는 $fatal 로 끝나도 종료 코드 0 을 낸다.  종료 코드만 믿으면
    # 벡터 불일치를 놓치므로, 로그의 최종 판정문을 확인한다.
    if (-not (Select-String -Path 'sim.log' -SimpleMatch 'RESULT     : PASS' -Quiet)) {
        throw "AES core KAT FAILED - see $work\sim.log"
    }
} finally {
    Pop-Location
}

$wdb = Join-Path $work 'aes_core_kat.wdb'
if ($DumpWave) {
    if ($MaxVectors -eq 0) {
        Write-Host "AES core KAT PASS - 405 벡터 전체" -ForegroundColor Green
    } else {
        Write-Host "AES core KAT PASS - 벡터 $MaxVectors 개 제한 실행 (전체 검증 아님)" -ForegroundColor Yellow
    }
    Write-Host "waveform : $wdb"
    if (-not $NoGui) {
        Write-Host "Vivado GUI 로 파형을 엽니다..."
        Start-Process -FilePath (Join-Path $vivado 'xsim.bat') `
            -ArgumentList '--gui', $wdb -WorkingDirectory $work
    }
} else {
    Write-Host "AES core KAT PASS ($work\sim.log)" -ForegroundColor Green
}
