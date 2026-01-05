# Publish script for AutoElevate Notepad++ Plugin
# Handles version bumping, building, and GitHub release creation

param(
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

# Determine version (format: YYYY.MMDD.bump)
if ($Version) {
    $newVersion = $Version
    if (-not $newVersion.StartsWith("v")) {
        $newVersion = "v$newVersion"
    }
    Write-Host "Using specified version: $newVersion" -ForegroundColor Cyan
} else {
    # Get current date components
    $now = Get-Date
    $year = $now.Year
    $month = $now.Month.ToString("00")
    $day = $now.Day.ToString("00")
    $datePrefix = "$year.$month$day"
    
    # Get latest version from git tags
    $latestTag = git tag --sort=-version:refname | Select-Object -First 1
    if ($latestTag) {
        Write-Host "Latest version: $latestTag" -ForegroundColor Cyan
        $versionParts = $latestTag -replace '^v', '' -split '\.'
        
        # Check if latest tag is from today
        if ($versionParts.Count -ge 3) {
            $latestDatePrefix = "$($versionParts[0]).$($versionParts[1])"
            if ($latestDatePrefix -eq $datePrefix) {
                # Same day - increment bump number
                $bump = [int]$versionParts[2] + 1
            } else {
                # Different day - start with bump 1
                $bump = 1
            }
        } else {
            # Invalid format or first release - start with bump 1
            $bump = 1
        }
    } else {
        # No existing tags - start with bump 1
        Write-Host "No existing tags found, starting with date-based version" -ForegroundColor Cyan
        $bump = 1
    }
    
    $newVersion = "v$datePrefix.$bump"
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

# Build all configurations (Debug/Release x x64/Win32)
if (-not $SkipBuild) {
    Write-Host "=== Building Debug x64 ===" -ForegroundColor Cyan
    & $msbuild "$scriptRoot\AutoElevate.vcxproj" /p:Configuration=Debug /p:Platform=x64 /t:Rebuild /v:minimal
    if ($LASTEXITCODE -ne 0) {
        Write-Host "Debug x64 build failed!" -ForegroundColor Red
        exit 1
    }
    Write-Host "Debug x64 build succeeded!" -ForegroundColor Green
    Write-Host ""
    
    Write-Host "=== Building Debug Win32 ===" -ForegroundColor Cyan
    & $msbuild "$scriptRoot\AutoElevate.vcxproj" /p:Configuration=Debug /p:Platform=Win32 /t:Rebuild /v:minimal
    if ($LASTEXITCODE -ne 0) {
        Write-Host "Debug Win32 build failed!" -ForegroundColor Red
        exit 1
    }
    Write-Host "Debug Win32 build succeeded!" -ForegroundColor Green
    Write-Host ""
    
    Write-Host "=== Building Release x64 ===" -ForegroundColor Cyan
    & $msbuild "$scriptRoot\AutoElevate.vcxproj" /p:Configuration=Release /p:Platform=x64 /t:Rebuild /v:minimal
    if ($LASTEXITCODE -ne 0) {
        Write-Host "Release x64 build failed!" -ForegroundColor Red
        exit 1
    }
    Write-Host "Release x64 build succeeded!" -ForegroundColor Green
    Write-Host ""
    
    Write-Host "=== Building Release Win32 ===" -ForegroundColor Cyan
    & $msbuild "$scriptRoot\AutoElevate.vcxproj" /p:Configuration=Release /p:Platform=Win32 /t:Rebuild /v:minimal
    if ($LASTEXITCODE -ne 0) {
        Write-Host "Release Win32 build failed!" -ForegroundColor Red
        exit 1
    }
    Write-Host "Release Win32 build succeeded!" -ForegroundColor Green
    Write-Host ""
} else {
    Write-Host "Skipping build (--SkipBuild specified)" -ForegroundColor Yellow
    Write-Host ""
}

# Copy and rename DLLs with architecture suffixes
Write-Host "=== Preparing Release Files ===" -ForegroundColor Cyan
$debugX64Dll = Join-Path $scriptRoot "x64\Debug\AutoElevate.dll"
$debugWin32Dll = Join-Path $scriptRoot "Win32\Debug\AutoElevate.dll"
$releaseX64Dll = Join-Path $scriptRoot "x64\Release\AutoElevate.dll"
$releaseWin32Dll = Join-Path $scriptRoot "Win32\Release\AutoElevate.dll"

$debugX64Out = Join-Path $scriptRoot "AutoElevate.Debug.x64.dll"
$debugWin32Out = Join-Path $scriptRoot "AutoElevate.Debug.x86.dll"
$releaseX64Out = Join-Path $scriptRoot "AutoElevate.Release.x64.dll"
$releaseWin32Out = Join-Path $scriptRoot "AutoElevate.Release.x86.dll"

if (-not (Test-Path $debugX64Dll)) {
    Write-Host "ERROR: Debug x64 DLL not found at $debugX64Dll" -ForegroundColor Red
    exit 1
}

if (-not (Test-Path $debugWin32Dll)) {
    Write-Host "ERROR: Debug Win32 DLL not found at $debugWin32Dll" -ForegroundColor Red
    exit 1
}

if (-not (Test-Path $releaseX64Dll)) {
    Write-Host "ERROR: Release x64 DLL not found at $releaseX64Dll" -ForegroundColor Red
    exit 1
}

if (-not (Test-Path $releaseWin32Dll)) {
    Write-Host "ERROR: Release Win32 DLL not found at $releaseWin32Dll" -ForegroundColor Red
    exit 1
}

Copy-Item $debugX64Dll -Destination $debugX64Out -Force
Copy-Item $debugWin32Dll -Destination $debugWin32Out -Force
Copy-Item $releaseX64Dll -Destination $releaseX64Out -Force
Copy-Item $releaseWin32Dll -Destination $releaseWin32Out -Force

$debugX64Info = Get-Item $debugX64Out
$debugWin32Info = Get-Item $debugWin32Out
$releaseX64Info = Get-Item $releaseX64Out
$releaseWin32Info = Get-Item $releaseWin32Out

Write-Host "  Created: AutoElevate.Debug.x64.dll ($([math]::Round($debugX64Info.Length/1KB, 2)) KB)" -ForegroundColor Green
Write-Host "  Created: AutoElevate.Debug.x86.dll ($([math]::Round($debugWin32Info.Length/1KB, 2)) KB)" -ForegroundColor Green
Write-Host "  Created: AutoElevate.Release.x64.dll ($([math]::Round($releaseX64Info.Length/1KB, 2)) KB)" -ForegroundColor Green
Write-Host "  Created: AutoElevate.Release.x86.dll ($([math]::Round($releaseWin32Info.Length/1KB, 2)) KB)" -ForegroundColor Green
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

1. Download the appropriate DLL for your architecture:
   - **x64**: `AutoElevate.Release.x64.dll` (production) or `AutoElevate.Debug.x64.dll` (debugging)
   - **x86**: `AutoElevate.Release.x86.dll` (production) or `AutoElevate.Debug.x86.dll` (debugging)
2. Rename the downloaded file to `AutoElevate.dll`
3. Copy to `C:\Program Files\Notepad++\plugins\AutoElevate\` (requires admin) or `%APPDATA%\Notepad++\plugins\AutoElevate\`
4. Restart Notepad++

## Usage

- **Enable/Disable Auto-Elevate**: Plugins > Auto Elevate > Auto-Elevate on Startup
- **Manual Elevation**: Plugins > Auto Elevate > Elevate

## Requirements

- Windows 7 or later
- Notepad++ (any recent version)
- x64 or x86 architecture

## Technical Details

- Uses PowerShell helper script to handle single-instance mode
- Helper script waits for current process to exit, then launches elevated instance
- Settings stored in `%APPDATA%\Notepad++\plugins\config\AutoElevate\config.ini`

## Build Information

- **Debug x64**: Includes debug symbols (~$([math]::Round($debugX64Info.Length/1KB, 2)) KB)
- **Debug x86**: Includes debug symbols (~$([math]::Round($debugWin32Info.Length/1KB, 2)) KB)
- **Release x64**: Optimized (~$([math]::Round($releaseX64Info.Length/1KB, 2)) KB)
- **Release x86**: Optimized (~$([math]::Round($releaseWin32Info.Length/1KB, 2)) KB)

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
    
    $commitMessage = "Release $newVersion`n`n- Built Debug and Release configurations for x64 and x86`n- Updated release notes`n- Prepared release assets"
    git commit -m $commitMessage
    Write-Host "Committed changes" -ForegroundColor Green
} else {
    Write-Host "No changes to commit" -ForegroundColor Yellow
}

# Create tag
Write-Host ""
Write-Host "Creating tag: $newVersion" -ForegroundColor Cyan
$tagMessage = "Release $newVersion - Auto Elevate Plugin for Notepad++`n`nFeatures:`n- Auto-elevate on startup (configurable)`n- Manual elevation menu command`n- Single-instance mode compatible`n`nBuilds:`n- Debug x64: AutoElevate.Debug.x64.dll`n- Debug x86: AutoElevate.Debug.x86.dll`n- Release x64: AutoElevate.Release.x64.dll`n- Release x86: AutoElevate.Release.x86.dll"
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
        "AutoElevate.Debug.x64.dll" `
        "AutoElevate.Debug.x86.dll" `
        "AutoElevate.Release.x64.dll" `
        "AutoElevate.Release.x86.dll"
    
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
    Write-Host "  4. Upload: AutoElevate.Debug.x64.dll, AutoElevate.Debug.x86.dll, AutoElevate.Release.x64.dll, AutoElevate.Release.x86.dll" -ForegroundColor Yellow
    Write-Host "  5. Copy release notes from RELEASE_NOTES.md" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "=== Release Summary ===" -ForegroundColor Green
Write-Host "Version: $newVersion" -ForegroundColor Cyan
Write-Host "Debug x64 DLL: AutoElevate.Debug.x64.dll ($([math]::Round($debugX64Info.Length/1KB, 2)) KB)" -ForegroundColor Green
Write-Host "Debug x86 DLL: AutoElevate.Debug.x86.dll ($([math]::Round($debugWin32Info.Length/1KB, 2)) KB)" -ForegroundColor Green
Write-Host "Release x64 DLL: AutoElevate.Release.x64.dll ($([math]::Round($releaseX64Info.Length/1KB, 2)) KB)" -ForegroundColor Green
Write-Host "Release x86 DLL: AutoElevate.Release.x86.dll ($([math]::Round($releaseWin32Info.Length/1KB, 2)) KB)" -ForegroundColor Green
Write-Host ""
Write-Host "Done!" -ForegroundColor Green
