# Rebuild AutoElevate plugin in Debug configuration and copy all relevant files
# This script finds MSBuild and rebuilds the project, then copies DLL and PDB files

$ErrorActionPreference = "Stop"

$projectPath = Join-Path $PSScriptRoot "AutoElevate.vcxproj"
$sourceDir = Join-Path $PSScriptRoot "x64\Debug"
$destDir = "C:\Program Files\Notepad++\plugins\AutoElevate"

Write-Host "Rebuilding AutoElevate plugin..." -ForegroundColor Cyan
Write-Host ""

# Try to find MSBuild
$msbuild = $null

# Method 1: Check PATH
$msbuild = Get-Command msbuild -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Source

# Method 2: Check known Visual Studio MSBuild locations (prioritized)
if (-not $msbuild) {
    $knownMsBuildPaths = @(
        # Visual Studio 2022+ (Current versions - preferred)
        "P:\Program Files\Microsoft Visual Studio\18\Insiders\MSBuild\Current\Bin\MSBuild.exe",
        "D:\Coding\Program Files\Microsoft Visual Studio\2022\Community\MSBuild\Current\Bin\MSBuild.exe",
        # Standard Visual Studio locations
        "${env:ProgramFiles}\Microsoft Visual Studio\2022\Community\MSBuild\Current\Bin\MSBuild.exe",
        "${env:ProgramFiles}\Microsoft Visual Studio\2022\Professional\MSBuild\Current\Bin\MSBuild.exe",
        "${env:ProgramFiles}\Microsoft Visual Studio\2022\Enterprise\MSBuild\Current\Bin\MSBuild.exe",
        "${env:ProgramFiles}\Microsoft Visual Studio\2022\BuildTools\MSBuild\Current\Bin\MSBuild.exe",
        "${env:ProgramFiles(x86)}\Microsoft Visual Studio\2022\Community\MSBuild\Current\Bin\MSBuild.exe",
        "${env:ProgramFiles(x86)}\Microsoft Visual Studio\2022\Professional\MSBuild\Current\Bin\MSBuild.exe",
        "${env:ProgramFiles(x86)}\Microsoft Visual Studio\2022\Enterprise\MSBuild\Current\Bin\MSBuild.exe",
        "${env:ProgramFiles(x86)}\Microsoft Visual Studio\2022\BuildTools\MSBuild\Current\Bin\MSBuild.exe"
    )
    
    foreach ($path in $knownMsBuildPaths) {
        if (Test-Path $path) {
            $msbuild = $path
            break
        }
    }
}

# Method 3: Use vswhere to find latest Visual Studio
if (-not $msbuild) {
    $vswhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
    if (Test-Path $vswhere) {
        $vsPath = & $vswhere -latest -property installationPath -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 2>$null
        if ($vsPath) {
            $testPath = Join-Path $vsPath "MSBuild\Current\Bin\MSBuild.exe"
            if (Test-Path $testPath) {
                $msbuild = $testPath
            }
        }
    }
}

if (-not $msbuild) {
    Write-Host "ERROR: MSBuild not found!" -ForegroundColor Red
    Write-Host ""
    Write-Host "Please either:" -ForegroundColor Yellow
    Write-Host "1. Open the project in Visual Studio and use Build > Rebuild Solution"
    Write-Host "2. Install Visual Studio Build Tools"
    Write-Host "3. Add MSBuild to your PATH"
    Write-Host ""
    Write-Host "Current Debug build files will be copied instead..." -ForegroundColor Yellow
    $shouldRebuild = $false
} else {
    Write-Host "Found MSBuild: $msbuild" -ForegroundColor Green
    Write-Host ""
    Write-Host "Rebuilding project..." -ForegroundColor Cyan
    & $msbuild $projectPath /p:Configuration=Debug /p:Platform=x64 /t:Rebuild /v:minimal
    
    if ($LASTEXITCODE -ne 0) {
        Write-Host "Build failed with exit code $LASTEXITCODE" -ForegroundColor Red
        exit 1
    }
    
    Write-Host "Build succeeded!" -ForegroundColor Green
    Write-Host ""
    $shouldRebuild = $true
}

# Copy relevant files
Write-Host "Copying Debug files to Notepad++ plugins folder..." -ForegroundColor Cyan
Write-Host ""

# Ensure destination directory exists
New-Item -ItemType Directory -Force -Path $destDir | Out-Null

# Files to copy
$filesToCopy = @(
    "AutoElevate.dll",
    "AutoElevate.pdb",
    "vc145.pdb"
)

$copiedFiles = @()
$missingFiles = @()

foreach ($file in $filesToCopy) {
    $src = Join-Path $sourceDir $file
    $dst = Join-Path $destDir $file
    
    if (Test-Path $src) {
        Copy-Item $src -Destination $dst -Force
        $info = Get-Item $src
        Write-Host "  Copied: $file ($([math]::Round($info.Length/1KB, 2)) KB)" -ForegroundColor Green
        $copiedFiles += $file
    } else {
        Write-Host "  WARNING: $file not found in $sourceDir" -ForegroundColor Yellow
        $missingFiles += $file
    }
}

Write-Host ""
Write-Host "Installation Summary:" -ForegroundColor Cyan
Write-Host "  Destination: $destDir"
Write-Host "  Files copied: $($copiedFiles.Count)"
if ($copiedFiles.Count -gt 0) {
    Write-Host ""
    Write-Host "Installed files:" -ForegroundColor Green
    Get-ChildItem $destDir | Where-Object { $filesToCopy -contains $_.Name } | ForEach-Object {
        Write-Host "    $($_.Name) - $([math]::Round($_.Length/1KB, 2)) KB - $($_.LastWriteTime)"
    }
}

if ($missingFiles.Count -gt 0) {
    Write-Host ""
    Write-Host "Missing files:" -ForegroundColor Yellow
    $missingFiles | ForEach-Object { Write-Host "    $_" }
}

Write-Host ""
Write-Host "Restart Notepad++ to load the plugin with debug symbols." -ForegroundColor Yellow
