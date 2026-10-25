@echo off
REM test.bat - runs the autotests only (mvn test). Run setup.bat first if JDK/Maven are missing.
setlocal
set "PROJECT_ROOT=%~dp0"
set "TMPPS=%TEMP%\fcm_test_%RANDOM%.ps1"
powershell -NoProfile -ExecutionPolicy Bypass -Command "$t=Get-Content -LiteralPath '%~f0' -Raw; $i=$t.IndexOf('#'+'#PS-BEGIN'); Set-Content -LiteralPath '%TMPPS%' -Value $t.Substring($i) -Encoding UTF8"
powershell -NoProfile -ExecutionPolicy Bypass -File "%TMPPS%" %*
set EXITCODE=%ERRORLEVEL%
del "%TMPPS%" >nul 2>&1
echo.
pause
exit /b %EXITCODE%

##PS-BEGIN
$ErrorActionPreference = 'Stop'
try {
    $machinePath = [Environment]::ExpandEnvironmentVariables([Environment]::GetEnvironmentVariable('Path', 'Machine'))
    $userPath    = [Environment]::ExpandEnvironmentVariables([Environment]::GetEnvironmentVariable('Path', 'User'))
    $env:PATH    = (@($env:PATH, $machinePath, $userPath) | Where-Object { $_ }) -join ';'
} catch {}
$Root = $env:PROJECT_ROOT.TrimEnd('\')
Set-Location -LiteralPath $Root
$Tools    = Join-Path $Root '.tools'
$MinJava  = 17
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
        if ($v -ge $MinJava) { Ok "Using system JDK $v."; return }
    }
    $jdk = Join-Path $Tools 'jdk'
    if (Test-Path (Join-Path $jdk 'bin\javac.exe')) {
        $env:JAVA_HOME = $jdk
        $env:PATH      = (Join-Path $jdk 'bin') + ';' + $env:PATH
        Ok "Using portable JDK: $jdk"; return
    }
    Die "JDK $MinJava+ not found. Run setup.bat first."
}

function Use-Maven {
    if (Get-Command mvn -ErrorAction SilentlyContinue) { Ok "Using system Maven."; return }
    $mvn = Join-Path $Tools 'maven'
    if (Test-Path (Join-Path $mvn 'bin\mvn.cmd')) {
        $env:PATH = (Join-Path $mvn 'bin') + ';' + $env:PATH
        Ok "Using portable Maven: $mvn"; return
    }
    Die "Maven not found. Run setup.bat first."
}

if (-not (Test-Path 'pom.xml')) { Die "pom.xml not found. Run this script from the project root." }
Use-Jdk
Use-Maven

if (-not ([IO.File]::ReadAllText((Join-Path $Root 'pom.xml')) -match 'spring-boot-starter-test')) {
    Die "pom.xml has no spring-boot-starter-test. Run setup.bat (adds it) or add the dependency manually."
}
if (-not (Test-Path $TestFile)) { Die "$TestFile not found. Copy FcmFlowTest.java to that path." }

Write-Host ''
$mvnArgs = @(if ($args.Count -eq 0) { 'test' } else { $args })
Say ("Running: mvn -B " + ($mvnArgs -join ' '))
& mvn -B @mvnArgs
$code = $LASTEXITCODE

Write-Host ''
if ($code -eq 0) { Ok 'ALL TESTS PASSED.' }
else { Warn "Some tests failed (exit $code). Details: target\surefire-reports\com.seminar.fcm.FcmFlowTest.txt" }
exit $code
