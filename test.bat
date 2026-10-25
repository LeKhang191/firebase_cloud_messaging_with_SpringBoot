@echo off
REM ============================================================================
REM  test.bat - Windows, 1 FILE DUY NHAT (ben trong co chua san code PowerShell)
REM  Double-click de chay, hoac chay trong terminal kem tham so.
REM ============================================================================
setlocal
set "PROJECT_ROOT=%~dp0"
set "TMPPS=%TEMP%\fcm_test_%RANDOM%.ps1"
REM Tach phan PowerShell (tu dong danh dau BEGIN tro xuong) ra file tam
powershell -NoProfile -ExecutionPolicy Bypass -Command "$t=Get-Content -LiteralPath '%~f0' -Raw; $i=$t.IndexOf('#'+'#PS-BEGIN'); Set-Content -LiteralPath '%TMPPS%' -Value $t.Substring($i) -Encoding UTF8"
powershell -NoProfile -ExecutionPolicy Bypass -File "%TMPPS%" %*
set EXITCODE=%ERRORLEVEL%
del "%TMPPS%" >nul 2>&1
echo.
pause
exit /b %EXITCODE%

##PS-BEGIN
# =============================================================================
#  test.ps1  -  Windows (PowerShell 5.1+ / PowerShell 7)
#  CHI CHAY AUTOTEST (mvn test). Khong cai dat gi ca.
#  Neu chua co JDK/Maven -> bao ban chay setup.bat truoc.
#
#  Dung (khuyen nghi: double-click test.bat), hoac:
#    .\test.ps1                              # chay toan bo test
#    .\test.ps1 -Dtest=FcmFlowTest test      # chi chay file FcmFlowTest
# =============================================================================
$ErrorActionPreference = 'Stop'
# Lam moi PATH tu he thong (terminal mo truoc khi cai Java/Maven se bi giu PATH cu)
try {
    $machinePath = [Environment]::ExpandEnvironmentVariables([Environment]::GetEnvironmentVariable('Path', 'Machine'))
    $userPath    = [Environment]::ExpandEnvironmentVariables([Environment]::GetEnvironmentVariable('Path', 'User'))
    $env:PATH    = (@($env:PATH, $machinePath, $userPath) | Where-Object { $_ }) -join ';'
} catch {}
$Root = $env:PROJECT_ROOT.TrimEnd('\')
Set-Location -LiteralPath $Root
$Tools    = Join-Path $Root '.tools'
$MinJava  = 17
$MaxJava = 21
$TestFile = 'src\test\java\com\seminar\fcm\FcmFlowTest.java'

function Say($m)  { Write-Host "[test ] $m" -ForegroundColor Cyan }
function Ok($m)   { Write-Host "[ ok  ] $m" -ForegroundColor Green }
function Warn($m) { Write-Host "[warn ] $m" -ForegroundColor Yellow }
function Die($m)  { Write-Host "[error] $m" -ForegroundColor Red; exit 1 }

function Get-JavaMajor([string]$javaExe) {
    $old = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try { $out = (& $javaExe -version 2>&1 | Out-String) } catch { $out = '' }
    $ErrorActionPreference = $old
    if ($out -match 'version "(\d+)(?:\.(\d+))?') {
        $major = [int]$Matches[1]
        if ($major -eq 1 -and $Matches[2]) { $major = [int]$Matches[2] }
        return $major
    }
    return 0
}

function Use-Jdk {
    $java  = Get-Command java  -ErrorAction SilentlyContinue
    $javac = Get-Command javac -ErrorAction SilentlyContinue
    if ($java -and $javac) {
        $v = Get-JavaMajor $java.Source
        if ($v -ge $MinJava -and $v -le $MaxJava) { Ok "Dung JDK $v cua he thong."; return }
    }
    $jdk = Join-Path $Tools 'jdk'
    if (Test-Path (Join-Path $jdk 'bin\javac.exe')) {
        $env:JAVA_HOME = $jdk
        $env:PATH      = (Join-Path $jdk 'bin') + ';' + $env:PATH
        Ok "Dung JDK portable: $jdk"; return
    }
    Die "Chua co JDK $MinJava-$MaxJava phu hop. Hay chay truoc: setup.bat"
}

function Use-Maven {
    if (Get-Command mvn -ErrorAction SilentlyContinue) { Ok "Dung Maven cua he thong."; return }
    $mvn = Join-Path $Tools 'maven'
    if (Test-Path (Join-Path $mvn 'bin\mvn.cmd')) {
        $env:PATH = (Join-Path $mvn 'bin') + ';' + $env:PATH
        Ok "Dung Maven portable: $mvn"; return
    }
    Die "Chua co Maven. Hay chay truoc: setup.bat"
}

if (-not (Test-Path 'pom.xml')) { Die "Khong thay pom.xml. Hay chay script o thu muc goc cua project." }
Use-Jdk
Use-Maven

if (-not ([IO.File]::ReadAllText((Join-Path $Root 'pom.xml')) -match 'spring-boot-starter-test')) {
    Die "pom.xml chua co spring-boot-starter-test. Chay setup.bat (tu them) hoac them tay dependency nay."
}
if (-not (Test-Path $TestFile)) { Die "Chua thay $TestFile. Hay chep FcmFlowTest.java vao dung duong dan do." }

Write-Host ''
# @(...) bat buoc: neu khong PowerShell se bien mang 1 phan tu thanh chuoi va tach tung ky tu
$mvnArgs = @(if ($args.Count -eq 0) { 'test' } else { $args })
$eapOld = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
$jv = (& java -version 2>&1 | Select-Object -First 1)
$ErrorActionPreference = $eapOld
Say "JDK dang dung: $jv"
Say ("Chay: mvn -B " + ($mvnArgs -join ' '))
& mvn -B @mvnArgs
$code = $LASTEXITCODE

Write-Host ''
if ($code -eq 0) { Ok 'TAT CA TEST PASS.' }
else {
    Warn "Co test loi (exit $code). Xem chi tiet: target\surefire-reports\com.seminar.fcm.FcmFlowTest.txt"
    Say "Nguyen nhan goc (cac dong 'Caused by' dau tien):"
    $causes = Get-ChildItem 'target\surefire-reports\*.txt' -ErrorAction SilentlyContinue |
        Select-String -Pattern 'Caused by' | ForEach-Object { $_.Line.Trim() } | Select-Object -Unique -First 6
    foreach ($c in $causes) { Write-Host ("  " + $c) }
}
exit $code
