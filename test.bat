@echo off
REM ============================================================================
REM  test.bat - Windows, ONE FILE ONLY (the PowerShell code is embedded inside)
REM  Double-click to run the autotest (mvn test). Installs nothing.
REM ============================================================================
setlocal
set "PROJECT_ROOT=%~dp0"
set "TMPPS=%TEMP%\fcm_test_%RANDOM%.ps1"
REM Extract the embedded PowerShell part (everything below the PS-BEGIN marker line) into a temp file
powershell -NoProfile -ExecutionPolicy Bypass -Command "$t=Get-Content -LiteralPath '%~f0' -Raw; $i=$t.IndexOf('#'+'#PS-BEGIN'); Set-Content -LiteralPath '%TMPPS%' -Value $t.Substring($i) -Encoding UTF8"
powershell -NoProfile -ExecutionPolicy Bypass -File "%TMPPS%" %*
set EXITCODE=%ERRORLEVEL%
del "%TMPPS%" >nul 2>&1
echo.
pause
exit /b %EXITCODE%

##PS-BEGIN
# =============================================================================
#  Embedded PowerShell part of test.bat (Windows PowerShell 5.1+ / PowerShell 7)
#  ONLY RUNS THE AUTOTEST (mvn test). Installs nothing.
#  If JDK/Maven is missing, it tells you to run setup.bat first.
#
#  Usage (recommended: double-click test.bat), or from a terminal:
#    .\test.bat                              # run all tests
#    .\test.bat -Dtest=FcmFlowTest test      # run only the FcmFlowTest class
# =============================================================================
$ErrorActionPreference = 'Stop'
# Refresh PATH from the system settings (a terminal opened before Java/Maven was installed keeps an old PATH) 
try {
    $machinePath = [Environment]::ExpandEnvironmentVariables([Environment]::GetEnvironmentVariable('Path', 'Machine'))
    $userPath    = [Environment]::ExpandEnvironmentVariables([Environment]::GetEnvironmentVariable('Path', 'User'))
    $env:PATH    = (@($env:PATH, $machinePath, $userPath) | Where-Object { $_ }) -join ';'
} catch {}
$Root = $env:PROJECT_ROOT.TrimEnd('\')
Set-Location -LiteralPath $Root
$Tools    = Join-Path $Root '.tools'
$MinJava  = 17
$MaxJava  = 21
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
        if ($v -ge $MinJava -and $v -le $MaxJava) { Ok "Use JDK $v of system."; return }
    }
    $jdk = Join-Path $Tools 'jdk'
    if (Test-Path (Join-Path $jdk 'bin\javac.exe')) {
        $env:JAVA_HOME = $jdk
        $env:PATH      = (Join-Path $jdk 'bin') + ';' + $env:PATH
        Ok "Use portable JDK: $jdk"; return
    }
    Die "No suitable JDK $MinJava-$MaxJava found. Please run:  setup.bat"
}

function Use-Maven {
    if (Get-Command mvn -ErrorAction SilentlyContinue) { Ok "Use Maven of system."; return }
    $mvn = Join-Path $Tools 'maven'
    if (Test-Path (Join-Path $mvn 'bin\mvn.cmd')) {
        $env:PATH = (Join-Path $mvn 'bin') + ';' + $env:PATH
        Ok "Use portable Maven: $mvn"; return
    }
    Die "No Maven found. Please run:  setup.bat"
}

if (-not (Test-Path 'pom.xml')) { Die "No pom.xml found. Please run this script in the root directory of the project." }
Use-Jdk
Use-Maven

if (-not ([IO.File]::ReadAllText((Join-Path $Root 'pom.xml')) -match 'spring-boot-starter-test')) {
    Die "pom.xml does not contain spring-boot-starter-test. Run setup.bat (auto-add) or manually add this dependency."
}
if (-not (Test-Path $TestFile)) { Die "No $TestFile found. Please copy FcmFlowTest.java to the correct path." }

Write-Host ''
# @(...) is required: otherwise PowerShell unwraps a one-element array into a string and mvn receives it split into single characters
$mvnArgs = @(if ($args.Count -eq 0) { 'test' } else { $args })
$eapOld = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
$jv = (& java -version 2>&1 | Select-Object -First 1)
$ErrorActionPreference = $eapOld
Say "JDK currently in use: $jv"
Say ("Run: mvn -B " + ($mvnArgs -join ' '))
& mvn -B @mvnArgs
$code = $LASTEXITCODE

Write-Host ''
if ($code -eq 0) { Ok 'ALL TESTS PASSED.' }
else {
    Warn "Some tests failed (exit $code). See details: target\surefire-reports\com.seminar.fcm.FcmFlowTest.txt"
    Say "Root cause (first 'Caused by' lines):"
    $causes = Get-ChildItem 'target\surefire-reports\*.txt' -ErrorAction SilentlyContinue |
        Select-String -Pattern 'Caused by' | ForEach-Object { $_.Line.Trim() } | Select-Object -Unique -First 6
    foreach ($c in $causes) { Write-Host ("  " + $c) }
}
exit $code
