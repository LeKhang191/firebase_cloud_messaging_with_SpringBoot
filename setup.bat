@echo off
REM setup.bat - installs the environment only (JDK 17-21 and Maven). Double-click to run.
setlocal
set "PROJECT_ROOT=%~dp0"
set "TMPPS=%TEMP%\fcm_setup_%RANDOM%.ps1"
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
$ProgressPreference = 'SilentlyContinue'
try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 } catch {}

$Root = $env:PROJECT_ROOT.TrimEnd('\')
Set-Location -LiteralPath $Root
$Tools        = Join-Path $Root '.tools'
$JdkDir       = Join-Path $Tools 'jdk'
$MvnDir       = Join-Path $Tools 'maven'
$MinJava      = 17
$MaxJava      = 21
$JdkVersion   = 17
$MavenVersion = '3.9.9'
$TestFile     = 'src\test\java\com\seminar\fcm\FcmFlowTest.java'

function Say($m)  { Write-Host "[setup] $m" -ForegroundColor Cyan }
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

function Download($urls, $file) {
    foreach ($url in @($urls)) {
        try {
            Say "Trying: $url"
            Invoke-WebRequest -Uri $url -OutFile $file -UseBasicParsing -TimeoutSec 180
            if ((Test-Path -LiteralPath $file) -and ((Get-Item -LiteralPath $file).Length -gt 1MB)) { return }
            Warn "Downloaded file is corrupt or too small."
        } catch {
            Warn "Failed: $($_.Exception.Message)"
        }
        Remove-Item -LiteralPath $file -Force -ErrorAction SilentlyContinue
    }
    Die "Could not download from any source. Check your network / VPN / proxy / firewall."
}

function Expand-Flat($zip, $dest) {
    $tmp = Join-Path $Tools ('_extract_' + [guid]::NewGuid().ToString('N'))
    Expand-Archive -LiteralPath $zip -DestinationPath $tmp -Force
    $inner = Get-ChildItem -LiteralPath $tmp | Select-Object -First 1
    if (Test-Path -LiteralPath $dest) { Remove-Item -LiteralPath $dest -Recurse -Force }
    Move-Item -LiteralPath $inner.FullName -Destination $dest
    Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
}

function Ensure-Jdk {
    $java  = Get-Command java  -ErrorAction SilentlyContinue
    $javac = Get-Command javac -ErrorAction SilentlyContinue
    if ($java -and $javac) {
        $v = Get-JavaMajor $java.Source
        if ($v -ge $MinJava -and $v -le $MaxJava) { Ok "JDK $v found on this machine - skipping install."; return }
        Warn "JDK on this machine is version $v (need $MinJava-$MaxJava) - using a portable JDK $JdkVersion."
    }
    if (-not (Test-Path (Join-Path $JdkDir 'bin\javac.exe'))) {
        Say "Downloading JDK $JdkVersion (Temurin, windows/x64) ..."
        New-Item -ItemType Directory -Force -Path $Tools | Out-Null
        $zip = Join-Path $Tools 'jdk.zip'
        Download "https://api.adoptium.net/v3/binary/latest/$JdkVersion/ga/windows/x64/jdk/hotspot/normal/eclipse" $zip
        Expand-Flat $zip $JdkDir
        Remove-Item -LiteralPath $zip -Force
        if (-not (Test-Path (Join-Path $JdkDir 'bin\javac.exe'))) { Die "JDK extracted but bin\javac.exe is missing." }
        Ok "Portable JDK installed at $JdkDir"
    } else {
        Ok "Using existing portable JDK at $JdkDir"
    }
    $env:JAVA_HOME = $JdkDir
    $env:PATH      = (Join-Path $JdkDir 'bin') + ';' + $env:PATH
}

function Ensure-Maven {
    if (Get-Command mvn -ErrorAction SilentlyContinue) { Ok "Maven found on this machine - skipping install."; return }
    if (-not (Test-Path (Join-Path $MvnDir 'bin\mvn.cmd'))) {
        Say "Downloading Maven $MavenVersion ..."
        New-Item -ItemType Directory -Force -Path $Tools | Out-Null
        $zip = Join-Path $Tools 'maven.zip'
        Download @(
            "https://repo.maven.apache.org/maven2/org/apache/maven/apache-maven/$MavenVersion/apache-maven-$MavenVersion-bin.zip",
            "https://repo1.maven.org/maven2/org/apache/maven/apache-maven/$MavenVersion/apache-maven-$MavenVersion-bin.zip",
            "https://downloads.apache.org/maven/maven-3/$MavenVersion/binaries/apache-maven-$MavenVersion-bin.zip",
            "https://archive.apache.org/dist/maven/maven-3/$MavenVersion/binaries/apache-maven-$MavenVersion-bin.zip"
        ) $zip
        Expand-Flat $zip $MvnDir
        Remove-Item -LiteralPath $zip -Force
        Ok "Portable Maven installed at $MvnDir"
    } else {
        Ok "Using existing portable Maven at $MvnDir"
    }
    $env:PATH = (Join-Path $MvnDir 'bin') + ';' + $env:PATH
}

function Ensure-Project {
    if (-not (Test-Path 'pom.xml')) { Die "pom.xml not found. Run this script from the project root." }

    $pom = [IO.File]::ReadAllText((Join-Path $Root 'pom.xml'))
    if ($pom -notmatch 'spring-boot-starter-test') {
        Say "pom.xml has no spring-boot-starter-test - adding it."
        Copy-Item pom.xml pom.xml.bak -Force
        $dep = "        <dependency>`n            <groupId>org.springframework.boot</groupId>`n            <artifactId>spring-boot-starter-test</artifactId>`n            <scope>test</scope>`n        </dependency>`n    </dependencies>"
        $re  = [regex]'</dependencies>'
        $new = $re.Replace($pom, $dep, 1)
        [IO.File]::WriteAllText((Join-Path $Root 'pom.xml'), $new, (New-Object Text.UTF8Encoding($false)))
        Ok "Dependency added (original saved as pom.xml.bak)."
    }

    if (-not (Test-Path $TestFile)) { Warn "$TestFile not found - copy FcmFlowTest.java there before running tests." }

    if (Test-Path '.gitignore') {
        $gi = Get-Content '.gitignore' -ErrorAction SilentlyContinue
        if ($gi -notcontains '.tools/') { Add-Content '.gitignore' "`n# portable tools downloaded by the setup scripts`n.tools/" }
    }
}

Say "Operating system: Windows"
Ensure-Jdk
Ensure-Maven
Ensure-Project

Write-Host ''
$old = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
(& java -version 2>&1 | Select-Object -First 1) | ForEach-Object { "$_" }
(& mvn -v 2>&1 | Select-Object -First 1) | ForEach-Object { "$_" }
$ErrorActionPreference = $old
Write-Host ''
Ok 'Environment ready. Run the tests with test.bat or start the app with start.bat'
