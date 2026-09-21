param(
    [switch]$SkipInstaller
)

$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
Set-Location $Root

if (-not (Test-Path "windows")) {
    Write-Host "windows runner missing; creating it..."
    flutter create --platforms=windows .
}

flutter pub get
if ($LASTEXITCODE -ne 0) {
    throw "Flutter package resolution failed."
}

flutter build windows --release
if ($LASTEXITCODE -ne 0) {
    throw "Flutter Windows build failed."
}

$VersionLine = Select-String -Path "pubspec.yaml" -Pattern '^version:\s*([^+\s]+)' | Select-Object -First 1
if (-not $VersionLine) {
    throw "Unable to read version from pubspec.yaml."
}
$Version = $VersionLine.Matches[0].Groups[1].Value
$ReleaseDir = Join-Path $Root "build\windows\x64\runner\Release"
$DistDir = Join-Path $Root "dist\windows"
$ZipPath = Join-Path $DistDir "Log4App-$Version-windows-x64-portable.zip"

New-Item -ItemType Directory -Force -Path $DistDir | Out-Null
if (Test-Path $ZipPath) {
    Remove-Item $ZipPath
}
Compress-Archive -Path "$ReleaseDir\*" -DestinationPath $ZipPath -CompressionLevel Optimal

Write-Host ""
Write-Host "Portable package:"
Write-Host $ZipPath

if ($SkipInstaller) {
    Write-Host "Installer skipped because -SkipInstaller was specified."
    exit 0
}

$Iscc = Get-Command "iscc.exe" -ErrorAction SilentlyContinue
if (-not $Iscc) {
    $Candidates = @(
        "${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe",
        "$env:ProgramFiles\Inno Setup 6\ISCC.exe"
    )
    $IsccPath = $Candidates | Where-Object { Test-Path $_ } | Select-Object -First 1
} else {
    $IsccPath = $Iscc.Source
}

if (-not $IsccPath) {
    throw "Inno Setup 6 was not found. Install it from https://jrsoftware.org/isdl.php, then rerun this script. The portable ZIP was still created at $ZipPath"
}

& $IsccPath "/DMyAppVersion=$Version" "packaging\windows\android_log_center.iss"
if ($LASTEXITCODE -ne 0) {
    throw "Inno Setup compilation failed."
}

Write-Host ""
Write-Host "Windows installer:"
Write-Host (Join-Path $DistDir "Log4App-$Version-windows-x64-setup.exe")
