@echo off
REM start.bat - ONE CLICK: installs missing tools, checks Firebase config, runs the app. Double-click to run.
setlocal
set "PROJECT_ROOT=%~dp0"
set "TMPPS=%TEMP%\fcm_start_%RANDOM%.ps1"
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
$Port         = 8080
$Url          = "http://localhost:$Port"
$ServiceAcc   = Join-Path $Root 'firebase-service-account.json'
$WebCfg       = Join-Path $Root 'src\main\resources\static\firebase-config.js'
$WebCfgSample = Join-Path $Root 'src\main\resources\static\firebase-config.example.js'

function Say($m)  { Write-Host "[start] $m" -ForegroundColor Cyan }
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

function Download($urls, $file) {
    foreach ($u in @($urls)) {
        try {
            Say "Trying: $u"
            Invoke-WebRequest -Uri $u -OutFile $file -UseBasicParsing -TimeoutSec 300
            if ((Test-Path -LiteralPath $file) -and ((Get-Item -LiteralPath $file).Length -gt 1MB)) { return }
            Warn "Downloaded file is corrupt or too small."
        } catch {
            Warn "Failed: $($_.Exception.Message)"
        }
        Remove-Item -LiteralPath $file -Force -ErrorAction SilentlyContinue
    }
    Die "Could not download from any source. Check your network / VPN / proxy / firewall and run again."
}

function Expand-Flat($zip, $dest) {
    $tmp = Join-Path $Tools ('_extract_' + [guid]::NewGuid().ToString('N'))
    Expand-Archive -LiteralPath $zip -DestinationPath $tmp -Force
    $inner = Get-ChildItem -LiteralPath $tmp | Select-Object -First 1
    if (Test-Path -LiteralPath $dest) { Remove-Item -LiteralPath $dest -Recurse -Force }
    Move-Item -LiteralPath $inner.FullName -Destination $dest
    Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
}

function Test-PortBusy([int]$p) {
    $c = New-Object System.Net.Sockets.TcpClient
    try { $c.Connect('127.0.0.1', $p); return $true } catch { return $false } finally { $c.Close() }
}

function Open-Browser([string]$url) {
    $cands = @(
        "$env:ProgramFiles\Google\Chrome\Application\chrome.exe",
        "${env:ProgramFiles(x86)}\Google\Chrome\Application\chrome.exe",
        "$env:LocalAppData\Google\Chrome\Application\chrome.exe",
        "${env:ProgramFiles(x86)}\Microsoft\Edge\Application\msedge.exe",
        "$env:ProgramFiles\Microsoft\Edge\Application\msedge.exe"
    )
    foreach ($c in $cands) {
        if ($c -and (Test-Path -LiteralPath $c)) { Start-Process -FilePath $c -ArgumentList $url; return }
    }
    Start-Process $url
}

function Ensure-Jdk {
    if ($env:FCM_FORCE_PORTABLE_TOOLS -ne '1') {
        $java  = Get-Command java  -CommandType Application -ErrorAction SilentlyContinue
        $javac = Get-Command javac -CommandType Application -ErrorAction SilentlyContinue
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
                Ok "JDK $v found on this machine - skipping JDK download."
                return
            }
        }
        Warn "System Java/JDK is missing, mismatched, or outside versions $MinJava-$MaxJava; checking portable JDK."
    }
    if (-not (Test-Path (Join-Path $JdkDir 'bin\javac.exe'))) {
        Say "Downloading JDK $JdkVersion (Temurin, windows/x64) ..."
        New-Item -ItemType Directory -Force -Path $Tools | Out-Null
        $zip = Join-Path $Tools 'jdk.zip'
        Download "https://api.adoptium.net/v3/binary/latest/$JdkVersion/ga/windows/x64/jdk/hotspot/normal/eclipse" $zip
        Expand-Flat $zip $JdkDir
        Remove-Item -LiteralPath $zip -Force
    }
    $javaExe = Join-Path $JdkDir 'bin\java.exe'
    $javacExe = Join-Path $JdkDir 'bin\javac.exe'
    if (-not (Test-Path $javacExe)) { Die "Portable JDK is missing bin\javac.exe." }
    $v = Get-JavaMajor $javaExe
    if ($v -lt $MinJava -or $v -gt $MaxJava) { Die "Portable JDK version must be $MinJava-$MaxJava; found $v." }
    $env:JAVA_HOME = $JdkDir
    $env:PATH = (Join-Path $JdkDir 'bin') + ';' + $env:PATH
    Ok "Using portable JDK $v at $JdkDir"
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

function Ensure-Maven {
    if ($env:FCM_FORCE_PORTABLE_TOOLS -ne '1') {
        $mvn = Get-Command mvn -ErrorAction SilentlyContinue
        if ($mvn) {
            $version = Get-MavenVersion $mvn.Source
            if (Test-MavenCompatible $version) {
                Ok "Maven $version found on this machine - skipping Maven download."
                return
            }
            Warn "System Maven version '$version' is missing or too old; checking portable Maven."
        }
    }
    $mvnCmd = Join-Path $MvnDir 'bin\mvn.cmd'
    if (-not (Test-Path $mvnCmd)) {
        Say "Downloading Maven $MavenVersion ..."
        New-Item -ItemType Directory -Force -Path $Tools | Out-Null
        $zip = Join-Path $Tools 'maven.zip'
        Download @(
            "https://repo.maven.apache.org/maven2/org/apache/maven/apache-maven/$MavenVersion/apache-maven-$MavenVersion-bin.zip",
            "https://repo1.maven.org/maven2/org/apache/maven/apache-maven/$MavenVersion/apache-maven-$MavenVersion-bin.zip",
            "https://archive.apache.org/dist/maven/maven-3/$MavenVersion/binaries/apache-maven-$MavenVersion-bin.zip"
        ) $zip
        Expand-Flat $zip $MvnDir
        Remove-Item -LiteralPath $zip -Force
    }
    $version = Get-MavenVersion $mvnCmd
    if (-not (Test-MavenCompatible $version)) { Die "Portable Maven is too old or invalid (found '$version'; need Maven 3.6.3 or newer)." }
    $env:PATH = (Join-Path $MvnDir 'bin') + ';' + $env:PATH
    Ok "Using Maven $version at $MvnDir"
}
function Ensure-ServiceAccount {
    if (Test-Path -LiteralPath $ServiceAcc) { Ok "firebase-service-account.json found."; return }
    Warn "firebase-service-account.json is missing (server-side private key)."
    Write-Host "  How to get it: Firebase Console > Project settings (gear icon) > Service accounts"
    Write-Host "                 > Generate new private key > save the .json file"
    Start-Process "https://console.firebase.google.com/"
    while ($true) {
        $p = Read-Host "Drag and drop the .json file into this window (or paste its path), then press Enter. Type q to quit"
        if ($null -eq $p) { Die "Cancelled." }
        $p = $p.Trim().Trim('"')
        if ($p -eq 'q' -or $p -eq 'Q') { Die "Cancelled." }
        if (-not $p) { continue }
        if (-not (Test-Path -LiteralPath $p)) { Warn "File not found: $p"; continue }
        try {
            $j = Get-Content -LiteralPath $p -Raw -Encoding UTF8 | ConvertFrom-Json
            if ($j.type -ne 'service_account' -or -not $j.private_key) { Warn "This is not a service account file. Try again."; continue }
        } catch { Warn "Not a valid JSON file. Try again."; continue }
        Copy-Item -LiteralPath $p -Destination $ServiceAcc -Force
        Ok "Saved firebase-service-account.json (project: $($j.project_id))"
        return
    }
}

function Ensure-WebConfig {
    if (-not (Test-Path -LiteralPath $WebCfg)) {
        if (-not (Test-Path -LiteralPath $WebCfgSample)) { Die "firebase-config.example.js is missing." }
        Copy-Item -LiteralPath $WebCfgSample -Destination $WebCfg
        Say "Created firebase-config.js from the example file."
    }
    $first = $true
    while ((Get-Content -LiteralPath $WebCfg -Raw -Encoding UTF8) -match 'YOUR_') {
        if ($first) {
            Warn "firebase-config.js still contains placeholder values (YOUR_...). Opening Notepad for you to fill in."
            Write-Host "  Where to find the values: Firebase Console > Project settings > General > Your apps (Web)"
            Write-Host "                            and Cloud Messaging tab > Web Push certificates (VAPID key)"
            $first = $false
        }
        Start-Process notepad.exe -ArgumentList ('"' + $WebCfg + '"')
        [void](Read-Host "When done, press Ctrl+S in Notepad to SAVE, then press Enter here")
    }
    Ok "firebase-config.js is filled in."
}

function Check-ProjectMatch {
    try {
        $j = Get-Content -LiteralPath $ServiceAcc -Raw -Encoding UTF8 | ConvertFrom-Json
        $c = Get-Content -LiteralPath $WebCfg -Raw -Encoding UTF8
        if ($c -match 'projectId\s*:\s*"([^"]+)"') {
            if ($Matches[1] -ne $j.project_id) {
                Warn "projectId in firebase-config.js ($($Matches[1])) differs from the service account project_id ($($j.project_id))."
                Warn "Both files must belong to the same Firebase project, otherwise sending fails with SENDER_ID_MISMATCH."
            } else {
                Ok "projectId matches between the service account and firebase-config.js ($($j.project_id))."
            }
        }
    } catch {}
}

Write-Host ''
Write-Host '=== FCM + Spring Boot demo : ONE CLICK INSTALL & RUN ===' -ForegroundColor Magenta
if (-not (Test-Path -LiteralPath (Join-Path $Root 'pom.xml'))) { Die "pom.xml not found. Keep start.bat in the project root." }

Ensure-Jdk
Ensure-Maven
Ensure-ServiceAccount
Ensure-WebConfig
Check-ProjectMatch

if (Test-PortBusy $Port) {
    Warn "Port $Port is already in use (the app may already be running)."
    Say "Opening browser: $Url"
    Open-Browser $Url
    exit 0
}

Write-Host ''
Say "Starting the application (the first run downloads Maven dependencies and may take a few minutes) ..."
$proc = Start-Process -FilePath 'cmd.exe' -ArgumentList '/c', 'mvn -B spring-boot:run' -NoNewWindow -PassThru
$null = $proc.Handle
$deadline = (Get-Date).AddMinutes(10)
$up = $false
while ((Get-Date) -lt $deadline) {
    if ($proc.HasExited) { break }
    if (Test-PortBusy $Port) { $up = $true; break }
    Start-Sleep -Seconds 2
}
if (-not $up) {
    if (-not $proc.HasExited) { & taskkill /PID $proc.Id /T /F | Out-Null }
    Die "The application failed to start. See the ERROR lines above."
}

Write-Host ''
Ok "APPLICATION IS RUNNING: $Url"
Say "Opening browser. To stop the app press Ctrl+C or close this window."
Open-Browser $Url
$proc.WaitForExit()
exit $proc.ExitCode