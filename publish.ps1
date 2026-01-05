# Publish script for AutoElevate Notepad++ Plugin
# Handles version bumping, building, and GitHub release creation

param(
    [Parameter(Mandatory=$false)]
    [ValidateSet("patch", "minor", "major")]
    [string]$BumpType = "patch",
    
    [Parameter(Mandatory=$false)]
    [string]$Version = "",
    
    [Parameter(Mandatory=$false)]
    [switch]$SkipBuild = $false,
    
    [Parameter(Mandatory=$false)]
    [switch]$SkipPush = $false,
    
    [Parameter(Mandatory=$false)]
    [switch]$Draft = $false
)

$ErrorActionPreference = "Stop"

# Get script directory
$scriptRoot = $PSScriptRoot
if (-not $scriptRoot) {
    $scriptRoot = Get-Location
}

Write-Host "=== AutoElevate Plugin Publisher ===" -ForegroundColor Cyan
Write-Host ""

# Find MSBuild
$msbuild = $null
$knownMsBuildPaths = @(
    "P:\Program Files\Microsoft Visual Studio\18\Insiders\MSBuild\Current\Bin\MSBuild.exe",
    "D:\Coding\Program Files\Microsoft Visual Studio\2022\Community\MSBuild\Current\Bin\MSBuild.exe",
    "${env:ProgramFiles}\Microsoft Visual Studio\2022\Community\MSBuild\Current\Bin\MSBuild.exe",
    "${env:ProgramFiles}\Microsoft Visual Studio\2022\Professional\MSBuild\Current\Bin\MSBuild.exe",
    "${env:ProgramFiles}\Microsoft Visual Studio\2022\Enterprise\MSBuild\Current\Bin\MSBuild.exe",
    "${env:ProgramFiles(x86)}\Microsoft Visual Studio\2022\Community\MSBuild\Current\Bin\MSBuild.exe"
)

foreach ($path in $knownMsBuildPaths) {
    if (Test-Path $path) {
        $msbuild = $path
        break
    }
}

if (-not $msbuild) {
    Write-Host "ERROR: MSBuild not found!" -ForegroundColor Red
    Write-Host "Please install Visual Studio or specify MSBuild path." -ForegroundColor Yellow
    exit 1
}

Write-Host "Found MSBuild: $msbuild" -ForegroundColor Green
Write-Host ""

# Determine version
if ($Version) {
    $newVersion = $Version
    Write-Host "Using specified version: $newVersion" -ForegroundColor Cyan
} else {
    # Get latest version from git tags
    $latestTag = git tag --sort=-version:refname | Select-Object -First 1
    if ($latestTag) {
        Write-Host "Latest version: $latestTag" -ForegroundColor Cyan
        $versionParts = $latestTag -replace '^v', '' -split '\.'
        $major = [int]$versionParts[0]
        $minor = [int]$versionParts[1]
        $patch = [int]$versionParts[2]
        
        switch ($BumpType) {
            "major" { $major++; $minor = 0; $patch = 0 }
            "minor" { $minor++; $patch = 0 }
            "patch" { $patch++ }
        }
        
        $newVersion = "v$major.$minor.$patch"
    } else {
        $newVersion = "v0.0.1"
        Write-Host "No existing tags found, starting with: $newVersion" -ForegroundColor Cyan
    }
    Write-Host "New version: $newVersion" -ForegroundColor Green
}

Write-Host ""

# Check for uncommitted changes
$gitStatus = git status --porcelain
if ($gitStatus) {
    Write-Host "WARNING: Uncommitted changes detected:" -ForegroundColor Yellow
    git status --short
    Write-Host ""
    $response = Read-Host "Continue anyway? (y/N)"
    if ($response -ne "y" -and $response -ne "Y") {
        Write-Host "Aborted." -ForegroundColor Red
        exit 1
    }
}

# Build both configurations
if (-not $SkipBuild) {
    Write-Host "=== Building Debug Configuration ===" -ForegroundColor Cyan
    & $msbuild "$scriptRoot\AutoElevate.vcxproj" /p:Configuration=Debug /p:Platform=x64 /t:Rebuild /v:minimal
    if ($LASTEXITCODE -ne 0) {
        Write-Host "Debug build failed!" -ForegroundColor Red
        exit 1
    }
    Write-Host "Debug build succeeded!" -ForegroundColor Green
    Write-Host ""
    
    Write-Host "=== Building Release Configuration ===" -ForegroundColor Cyan
    & $msbuild "$scriptRoot\AutoElevate.vcxproj" /p:Configuration=Release /p:Platform=x64 /t:Rebuild /v:minimal
    if ($LASTEXITCODE -ne 0) {
        Write-Host "Release build failed!" -ForegroundColor Red
        exit 1
    }
    Write-Host "Release build succeeded!" -ForegroundColor Green
    Write-Host ""
} else {
    Write-Host "Skipping build (--SkipBuild specified)" -ForegroundColor Yellow
    Write-Host ""
}

# Copy and rename DLLs
Write-Host "=== Preparing Release Files ===" -ForegroundColor Cyan
$debugDll = Join-Path $scriptRoot "x64\Debug\AutoElevate.dll"
$releaseDll = Join-Path $scriptRoot "x64\Release\AutoElevate.dll"
$debugOut = Join-Path $scriptRoot "AutoElevate.Debug.dll"
$releaseOut = Join-Path $scriptRoot "AutoElevate.Release.dll"

if (-not (Test-Path $debugDll)) {
    Write-Host "ERROR: Debug DLL not found at $debugDll" -ForegroundColor Red
    exit 1
}

if (-not (Test-Path $releaseDll)) {
    Write-Host "ERROR: Release DLL not found at $releaseDll" -ForegroundColor Red
    exit 1
}

Copy-Item $debugDll -Destination $debugOut -Force
Copy-Item $releaseDll -Destination $releaseOut -Force

$debugInfo = Get-Item $debugOut
$releaseInfo = Get-Item $releaseOut

Write-Host "  Created: AutoElevate.Debug.dll ($([math]::Round($debugInfo.Length/1KB, 2)) KB)" -ForegroundColor Green
Write-Host "  Created: AutoElevate.Release.dll ($([math]::Round($releaseInfo.Length/1KB, 2)) KB)" -ForegroundColor Green
Write-Host ""

# Check if GitHub CLI is available
$ghAvailable = Get-Command gh -ErrorAction SilentlyContinue
if (-not $ghAvailable) {
    Write-Host "WARNING: GitHub CLI (gh) not found!" -ForegroundColor Yellow
    Write-Host "Release will be created locally but not published to GitHub." -ForegroundColor Yellow
    Write-Host "Install GitHub CLI from: https://cli.github.com/" -ForegroundColor Yellow
    Write-Host ""
}

# Create release notes
Write-Host "=== Creating Release Notes ===" -ForegroundColor Cyan
$releaseNotes = @"
# Auto Elevate Plugin $newVersion

## Features

- **Auto-Elevate on Startup**: Automatically requests elevation when Notepad++ starts (configurable via menu)
- **Manual Elevate**: Menu command to elevate the current instance
- **Single-Instance Compatible**: Works correctly with Notepad++ single-instance mode using helper script approach
- **Settings Persistence**: Saves auto-elevate preference to config file
- **Debug Logging**: Comprehensive logging to `%APPDATA%\Notepad++\plugins\config\AutoElevate\debug.log`

## Installation

1. Download either `AutoElevate.Debug.dll` (for debugging) or `AutoElevate.Release.dll` (for production)
2. Rename the downloaded file to `AutoElevate.dll`
3. Copy to `C:\Program Files\Notepad++\plugins\AutoElevate\` (requires admin) or `%APPDATA%\Notepad++\plugins\AutoElevate\`
4. Restart Notepad++

## Usage

- **Enable/Disable Auto-Elevate**: Plugins > Auto Elevate > Auto-Elevate on Startup
- **Manual Elevation**: Plugins > Auto Elevate > Elevate

## Requirements

- Windows 7 or later
- Notepad++ (any recent version)
- x64 architecture

## Technical Details

- Uses PowerShell helper script to handle single-instance mode
- Helper script waits for current process to exit, then launches elevated instance
- Debug logging always enabled for troubleshooting
- Settings stored in `%APPDATA%\Notepad++\plugins\config\AutoElevate\config.ini`

## Build Information

- **Debug Build**: Includes debug symbols, larger file size (~$([math]::Round($debugInfo.Length/1KB, 2)) KB)
- **Release Build**: Optimized, smaller file size (~$([math]::Round($releaseInfo.Length/1KB, 2)) KB)

## Notes

- Requires UAC approval to elevate
- Running applications with administrator privileges can pose security risks
- Helper scripts are created in `%TEMP%` and cleaned up automatically
"@

$releaseNotesFile = Join-Path $scriptRoot "RELEASE_NOTES.md"
$releaseNotes | Out-File -FilePath $releaseNotesFile -Encoding UTF8
Write-Host "Created: RELEASE_NOTES.md" -ForegroundColor Green
Write-Host ""

# Git operations
Write-Host "=== Git Operations ===" -ForegroundColor Cyan

# Stage all changes (except release DLLs which are in .gitignore)
git add -A
$stagedFiles = git diff --cached --name-only
if ($stagedFiles) {
    Write-Host "Staging files:" -ForegroundColor Yellow
    $stagedFiles | ForEach-Object { Write-Host "  $_" -ForegroundColor Gray }
    Write-Host ""
    
    $commitMessage = "Release $newVersion`n`n- Built Debug and Release configurations`n- Updated release notes`n- Prepared release assets"
    git commit -m $commitMessage
    Write-Host "Committed changes" -ForegroundColor Green
} else {
    Write-Host "No changes to commit" -ForegroundColor Yellow
}

# Create tag
Write-Host ""
Write-Host "Creating tag: $newVersion" -ForegroundColor Cyan
$tagMessage = "Release $newVersion - Auto Elevate Plugin for Notepad++`n`nFeatures:`n- Auto-elevate on startup (configurable)`n- Manual elevation menu command`n- Single-instance mode compatible`n- Debug logging support`n`nBuilds:`n- Debug: AutoElevate.Debug.dll (with debug symbols)`n- Release: AutoElevate.Release.dll (optimized)"
git tag -a $newVersion -m $tagMessage
Write-Host "Tag created: $newVersion" -ForegroundColor Green
Write-Host ""

# Push to GitHub
if (-not $SkipPush) {
    Write-Host "=== Pushing to GitHub ===" -ForegroundColor Cyan
    git push origin main
    if ($LASTEXITCODE -ne 0) {
        Write-Host "Failed to push main branch!" -ForegroundColor Red
        exit 1
    }
    Write-Host "Pushed main branch" -ForegroundColor Green
    
    git push origin $newVersion
    if ($LASTEXITCODE -ne 0) {
        Write-Host "Failed to push tag!" -ForegroundColor Red
        exit 1
    }
    Write-Host "Pushed tag: $newVersion" -ForegroundColor Green
    Write-Host ""
} else {
    Write-Host "Skipping push (--SkipPush specified)" -ForegroundColor Yellow
    Write-Host ""
}

# Create GitHub release
if ($ghAvailable) {
    Write-Host "=== Creating GitHub Release ===" -ForegroundColor Cyan
    
    $draftFlag = if ($Draft) { "--draft" } else { "" }
    $releaseTitle = "$newVersion - Auto Elevate Plugin"
    
    gh release create $newVersion `
        --title $releaseTitle `
        --notes-file $releaseNotesFile `
        $draftFlag `
        "AutoElevate.Debug.dll" `
        "AutoElevate.Release.dll"
    
    if ($LASTEXITCODE -eq 0) {
        $releaseUrl = gh release view $newVersion --json url -q .url
        Write-Host ""
        Write-Host "Release created successfully!" -ForegroundColor Green
        Write-Host "Release URL: $releaseUrl" -ForegroundColor Cyan
    } else {
        Write-Host "Failed to create GitHub release!" -ForegroundColor Red
        exit 1
    }
} else {
    Write-Host "=== GitHub Release ===" -ForegroundColor Cyan
    Write-Host "GitHub CLI not available. To create release manually:" -ForegroundColor Yellow
    Write-Host "  1. Go to: https://github.com/Bluscream/npp-auto-elevate-plugin/releases/new" -ForegroundColor Yellow
    Write-Host "  2. Tag: $newVersion" -ForegroundColor Yellow
    Write-Host "  3. Title: $newVersion - Auto Elevate Plugin" -ForegroundColor Yellow
    Write-Host "  4. Upload: AutoElevate.Debug.dll and AutoElevate.Release.dll" -ForegroundColor Yellow
    Write-Host "  5. Copy release notes from RELEASE_NOTES.md" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "=== Release Summary ===" -ForegroundColor Green
Write-Host "Version: $newVersion" -ForegroundColor Cyan
Write-Host "Debug DLL: AutoElevate.Debug.dll ($([math]::Round($debugInfo.Length/1KB, 2)) KB)" -ForegroundColor Green
Write-Host "Release DLL: AutoElevate.Release.dll ($([math]::Round($releaseInfo.Length/1KB, 2)) KB)" -ForegroundColor Green
Write-Host ""
Write-Host "Done!" -ForegroundColor Green
