@echo off
REM ============================================================================
REM  setup.bat - Windows, 1 FILE DUY NHAT (ben trong co chua san code PowerShell)
REM  Double-click de chay, hoac chay trong terminal kem tham so.
REM ============================================================================
setlocal
set "PROJECT_ROOT=%~dp0"
set "TMPPS=%TEMP%\fcm_setup_%RANDOM%.ps1"
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
#  setup.ps1  -  Windows (PowerShell 5.1+ / PowerShell 7)
#  CHI CAI MOI TRUONG (JDK 17+, Maven).
#  - Cai nao may da co thi BO QUA.
#  - Cai nao thieu thi tai ban portable vao .\.tools (khong can quyen Admin).
#  Sau khi cai xong, chay test bang: test.bat (hoac .\test.ps1)
# =============================================================================
$ErrorActionPreference = 'Stop'
# Lam moi PATH tu he thong (terminal mo truoc khi cai Java/Maven se bi giu PATH cu)
try {
    $machinePath = [Environment]::ExpandEnvironmentVariables([Environment]::GetEnvironmentVariable('Path', 'Machine'))
    $userPath    = [Environment]::ExpandEnvironmentVariables([Environment]::GetEnvironmentVariable('Path', 'User'))
    $env:PATH    = (@($env:PATH, $machinePath, $userPath) | Where-Object { $_ }) -join ';'
} catch {}
$ProgressPreference    = 'SilentlyContinue'   # tang toc Invoke-WebRequest
try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 } catch {}

$Root = $env:PROJECT_ROOT.TrimEnd('\')
Set-Location -LiteralPath $Root
$Tools        = Join-Path $Root '.tools'
$JdkDir       = Join-Path $Tools 'jdk'
$MvnDir       = Join-Path $Tools 'maven'
$MinJava      = 17
$MaxJava = 21
$JdkVersion   = 17
$MavenVersion = '3.9.9'
$TestFile     = 'src\test\java\com\seminar\fcm\FcmFlowTest.java'

function Say($m)  { Write-Host "[setup] $m" -ForegroundColor Cyan }
function Ok($m)   { Write-Host "[ ok  ] $m" -ForegroundColor Green }
function Warn($m) { Write-Host "[warn ] $m" -ForegroundColor Yellow }
function Die($m)  { Write-Host "[error] $m" -ForegroundColor Red; exit 1 }

function Get-JavaMajor([string]$javaExe) {
    $old = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'   # java -version ghi ra stderr, khong duoc nem loi
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
    # Thu lan luot tung nguon, nguon nao tai duoc thi dung
    foreach ($url in @($urls)) {
        try {
            Say "Thu tai: $url"
            Invoke-WebRequest -Uri $url -OutFile $file -UseBasicParsing -TimeoutSec 180
            if ((Test-Path -LiteralPath $file) -and ((Get-Item -LiteralPath $file).Length -gt 1MB)) { return }
            Warn "File tai ve bi loi/qua nho."
        } catch {
            Warn "That bai: $($_.Exception.Message)"
        }
        Remove-Item -LiteralPath $file -Force -ErrorAction SilentlyContinue
    }
    Die "Khong tai duoc tu bat ky nguon nao.`nKiem tra mang / VPN / proxy / firewall, hoac tai thu cong (xem huong dan trong tin nhan)."
}

function Expand-Flat($zip, $dest) {
    # Giai nen zip va bo thu muc goc (giong tar --strip-components=1)
    $tmp = Join-Path $Tools ('_extract_' + [guid]::NewGuid().ToString('N'))
    Expand-Archive -LiteralPath $zip -DestinationPath $tmp -Force
    $inner = Get-ChildItem -LiteralPath $tmp | Select-Object -First 1
    if (Test-Path -LiteralPath $dest) { Remove-Item -LiteralPath $dest -Recurse -Force }
    Move-Item -LiteralPath $inner.FullName -Destination $dest
    Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
}

# ---------------------------------------------------------------- 1) JDK
function Ensure-Jdk {
    $java  = Get-Command java  -ErrorAction SilentlyContinue
    $javac = Get-Command javac -ErrorAction SilentlyContinue
    if ($java -and $javac) {
        $v = Get-JavaMajor $java.Source
        if ($v -ge $MinJava -and $v -le $MaxJava) { Ok "Da co JDK $v tren may -> bo qua cai dat."; return }
        Warn "JDK tren may la ban $v (can $MinJava-$MaxJava) -> se dung ban portable."
    }

    if (-not (Test-Path (Join-Path $JdkDir 'bin\javac.exe'))) {
        Say "Tai JDK $JdkVersion (Temurin, windows/x64) ..."
        New-Item -ItemType Directory -Force -Path $Tools | Out-Null
        $zip = Join-Path $Tools 'jdk.zip'
        Download "https://api.adoptium.net/v3/binary/latest/$JdkVersion/ga/windows/x64/jdk/hotspot/normal/eclipse" $zip
        Expand-Flat $zip $JdkDir
        Remove-Item -LiteralPath $zip -Force
        if (-not (Test-Path (Join-Path $JdkDir 'bin\javac.exe'))) { Die "Giai nen JDK xong nhung khong thay bin\javac.exe" }
        Ok "Da cai JDK portable tai $JdkDir"
    } else {
        Ok "Dung JDK portable co san tai $JdkDir"
    }
    $env:JAVA_HOME = $JdkDir
    $env:PATH      = (Join-Path $JdkDir 'bin') + ';' + $env:PATH
}

# ---------------------------------------------------------------- 2) Maven
function Ensure-Maven {
    if (Get-Command mvn -ErrorAction SilentlyContinue) { Ok "Da co Maven tren may -> bo qua cai dat."; return }

    if (-not (Test-Path (Join-Path $MvnDir 'bin\mvn.cmd'))) {
        Say "Tai Maven $MavenVersion ..."
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
        Ok "Da cai Maven portable tai $MvnDir"
    } else {
        Ok "Dung Maven portable co san tai $MvnDir"
    }
    $env:PATH = (Join-Path $MvnDir 'bin') + ';' + $env:PATH
}

# ---------------------------------------------------------------- 3) Kiem tra project
function Ensure-Project {
    if (-not (Test-Path 'pom.xml')) { Die "Khong thay pom.xml. Hay chay script o thu muc goc cua project." }

    $pom = [IO.File]::ReadAllText((Join-Path $Root 'pom.xml'))
    if ($pom -notmatch 'spring-boot-starter-test') {
        Say "pom.xml chua co spring-boot-starter-test -> tu them vao."
        Copy-Item pom.xml pom.xml.bak -Force
        $dep = "        <dependency>`n            <groupId>org.springframework.boot</groupId>`n            <artifactId>spring-boot-starter-test</artifactId>`n            <scope>test</scope>`n        </dependency>`n    </dependencies>"
        $re  = [regex]'</dependencies>'
        $new = $re.Replace($pom, $dep, 1)
        [IO.File]::WriteAllText((Join-Path $Root 'pom.xml'), $new, (New-Object Text.UTF8Encoding($false)))
        Ok "Da them dependency (ban goc luu o pom.xml.bak)."
    }

    if (-not (Test-Path $TestFile)) { Warn "Chua thay $TestFile - hay chep FcmFlowTest.java vao do truoc khi chay test." }

    if (Test-Path '.gitignore') {
        $gi = Get-Content '.gitignore' -ErrorAction SilentlyContinue
        if ($gi -notcontains '.tools/') { Add-Content '.gitignore' "`n# cong cu portable do setup-and-test tai ve`n.tools/" }
    }
}

# ---------------------------------------------------------------- main
Say "He dieu hanh: Windows"
Ensure-Jdk
Ensure-Maven
Ensure-Project

Write-Host ''
$old = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
(& java -version 2>&1 | Select-Object -First 1) | ForEach-Object { "$_" }
(& mvn -v 2>&1 | Select-Object -First 1) | ForEach-Object { "$_" }
$ErrorActionPreference = $old
Write-Host ''
Ok 'Cai moi truong xong. Gio chay test bang: test.bat'
