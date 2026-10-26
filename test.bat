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
$AdminTestFile = 'src\test\java\com\seminar\fcm\AdminKeyTest.java'

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

function Get-JavacMajor([string]$javacExe) {
    $old = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try { $out = (& $javacExe -version 2>&1 | Out-String) } catch { $out = '' }
    $ErrorActionPreference = $old
    if ($out -match 'javac\s+(\d+)(?:\.(\d+))?') {
        $major = [int]$Matches[1]
        if ($major -eq 1 -and $Matches[2]) { $major = [int]$Matches[2] }
        return $major
    }
    return 0
}

function Use-Jdk {
    if ($env:FCM_FORCE_PORTABLE_TOOLS -ne '1') {
        $java  = Get-Command java  -ErrorAction SilentlyContinue
        $javac = Get-Command javac -ErrorAction SilentlyContinue
        if ($java -and $javac) {
            $v = Get-JavaMajor $java.Source
            $cv = Get-JavacMajor $javac.Source
            if ($v -ge $MinJava -and $v -le $MaxJava -and $v -eq $cv) {
                $home = $null
                if ($env:JAVA_HOME -and (Test-Path (Join-Path $env:JAVA_HOME 'bin\javac.exe'))) {
                    $home = $env:JAVA_HOME.Trim().Trim('"')
                } else {
                    $home = (Get-Item -LiteralPath $javac.Source).Directory.Parent.FullName
                }
                if ($home -and (Test-Path (Join-Path $home 'bin\java.exe'))) {
                    $env:JAVA_HOME = $home
                    $env:PATH = (Join-Path $home 'bin') + ';' + $env:PATH
                }
                Ok "Use system JDK $v."
                return
            }
        }
    }
    $jdk = Join-Path $Tools 'jdk'
    $javaExe = Join-Path $jdk 'bin\java.exe'
    $javacExe = Join-Path $jdk 'bin\javac.exe'
    if ((Test-Path $javaExe) -and (Test-Path $javacExe)) {
        $v = Get-JavaMajor $javaExe
        if ($v -ge $MinJava -and $v -le $MaxJava) {
            $env:JAVA_HOME = $jdk
            $env:PATH = (Join-Path $jdk 'bin') + ';' + $env:PATH
            Ok "Use portable JDK ${v}: $jdk"
            return
        }
    }
    Die "No suitable JDK $MinJava-$MaxJava found. Please run setup.bat"
}
function Test-MavenCompatible([string]$version) {
    if ($version -notmatch '^(\d+)\.(\d+)\.(\d+)') { return $false }
    $major = [int]$Matches[1]; $minor = [int]$Matches[2]; $patch = [int]$Matches[3]
    return ($major -gt 3 -or ($major -eq 3 -and ($minor -gt 6 -or ($minor -eq 6 -and $patch -ge 3))))
}

function Get-MavenVersion([string]$mvnExe) {
    $old = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try { $out = (& $mvnExe -v 2>&1 | Out-String) } catch { $out = '' }
    $ErrorActionPreference = $old
    if ($out -match 'Apache Maven\s+(\d+\.\d+\.\d+)') { return $Matches[1] }
    return ''
}

function Use-Maven {
    if ($env:FCM_FORCE_PORTABLE_TOOLS -ne '1') {
        $mvn = Get-Command mvn -ErrorAction SilentlyContinue
        if ($mvn) {
            $version = Get-MavenVersion $mvn.Source
            if (Test-MavenCompatible $version) { Ok "Use system Maven $version."; return }
            Warn "System Maven version '$version' is missing or too old."
        }
    }
    $mvnCmd = Join-Path $Tools 'maven\bin\mvn.cmd'
    if (Test-Path $mvnCmd) {
        $version = Get-MavenVersion $mvnCmd
        if (Test-MavenCompatible $version) {
            $env:PATH = (Join-Path $Tools 'maven\bin') + ';' + $env:PATH
            Ok "Use portable Maven $version."
            return
        }
    }
    Die "No compatible Maven found. Please run setup.bat"
}
if (-not (Test-Path 'pom.xml')) { Die "No pom.xml found. Please run this script in the root directory of the project." }
Use-Jdk
Use-Maven

if (-not ([IO.File]::ReadAllText((Join-Path $Root 'pom.xml')) -match 'spring-boot-starter-test')) {
    Die "pom.xml does not contain spring-boot-starter-test. Run setup.bat (auto-add) or manually add this dependency."
}
if (-not (Test-Path $TestFile)) { Die "No $TestFile found. Please copy FcmFlowTest.java to the correct path." }
if (-not (Test-Path $AdminTestFile)) { Die "No $AdminTestFile found. Admin-key security tests are required." }

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
    Warn "Some tests failed (exit $code). Review reports in target\surefire-reports\."
    Say "Root cause (first 'Caused by' lines):"
    $causes = Get-ChildItem 'target\surefire-reports\*.txt' -ErrorAction SilentlyContinue |
        Select-String -Pattern 'Caused by' | ForEach-Object { $_.Line.Trim() } | Select-Object -Unique -First 6
    foreach ($c in $causes) { Write-Host ("  " + $c) }
}
exit $code
