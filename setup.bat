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
$AdminTestFile = 'src\test\java\com\seminar\fcm\AdminKeyTest.java'

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
            "https://downloads.apache.org/maven/maven-3/$MavenVersion/binaries/apache-maven-$MavenVersion-bin.zip",
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
    if (-not (Test-Path $AdminTestFile)) { Warn "$AdminTestFile not found - admin-key security tests will be missing." }

    $gitignorePath = Join-Path $Root '.gitignore'
    if (-not (Test-Path -LiteralPath $gitignorePath)) { New-Item -ItemType File -Path $gitignorePath | Out-Null }
    $ignoreRules = @('.env', '.env.*', '!.env.example', '.tools/', 'firebase-service-account.json', 'src/main/resources/static/firebase-config.js')
    $existingRules = @(Get-Content -LiteralPath $gitignorePath -ErrorAction SilentlyContinue)
    foreach ($rule in $ignoreRules) {
        if ($existingRules -notcontains $rule) {
            Add-Content -LiteralPath $gitignorePath -Value $rule -Encoding UTF8
            $existingRules += $rule
        }
    }
    $git = Get-Command git -ErrorAction SilentlyContinue
    if ($git) {
        & $git.Source -C $Root rev-parse --is-inside-work-tree *> $null
        if ($LASTEXITCODE -eq 0) {
            & $git.Source -C $Root ls-files --error-unmatch -- .env *> $null
            if ($LASTEXITCODE -eq 0) {
                Warn '.env is already tracked by Git; .gitignore cannot untrack it. Run: git rm --cached .env'
                Warn 'If this key was pushed to a public repository, rotate ADMIN_KEY.'
            }
        }
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
