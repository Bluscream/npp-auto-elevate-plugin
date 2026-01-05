# Install Release DLL to Notepad++ plugins folder
# This script will wait for Notepad++ to close, then install the Release DLL

$ErrorActionPreference = "Stop"

$sourceDll = Join-Path $PSScriptRoot "x64\Release\AutoElevate.dll"
$destDir = "C:\Program Files\Notepad++\plugins\AutoElevate"
$destDll = Join-Path $destDir "AutoElevate.dll"

Write-Host "Installing Release DLL..." -ForegroundColor Cyan
Write-Host ""

# Check if source DLL exists
if (-not (Test-Path $sourceDll)) {
    Write-Host "ERROR: Release DLL not found at:" -ForegroundColor Red
    Write-Host "  $sourceDll" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "Please build the Release configuration first." -ForegroundColor Yellow
    exit 1
}

$dllInfo = Get-Item $sourceDll
Write-Host "Release DLL: $([math]::Round($dllInfo.Length/1KB, 2)) KB" -ForegroundColor Green
Write-Host "Modified: $($dllInfo.LastWriteTime)" -ForegroundColor Green
Write-Host ""

# Check if Notepad++ is running
$nppProcesses = Get-Process -Name "notepad++" -ErrorAction SilentlyContinue
if ($nppProcesses) {
    Write-Host "Notepad++ is running. Waiting for it to close..." -ForegroundColor Yellow
    Write-Host "  PIDs: $($nppProcesses.Id -join ', ')" -ForegroundColor Yellow
    Write-Host ""
    
    foreach ($proc in $nppProcesses) {
        $proc.WaitForExit()
        Write-Host "  Process $($proc.Id) exited" -ForegroundColor Green
    }
    
    Write-Host ""
    Write-Host "Notepad++ closed. Installing DLL..." -ForegroundColor Cyan
    Start-Sleep -Milliseconds 500  # Brief delay to ensure file handles are released
} else {
    Write-Host "Notepad++ is not running. Installing DLL..." -ForegroundColor Green
}

# Create destination directory
New-Item -ItemType Directory -Force -Path $destDir | Out-Null

# Copy DLL
Copy-Item $sourceDll -Destination $destDll -Force
Write-Host "  Copied: AutoElevate.dll" -ForegroundColor Green

# Remove PDB files
Write-Host ""
Write-Host "Removing debug files (PDB)..." -ForegroundColor Yellow
$pdbFiles = Get-ChildItem $destDir -Filter "*.pdb" -ErrorAction SilentlyContinue
if ($pdbFiles) {
    foreach ($pdb in $pdbFiles) {
        Remove-Item $pdb.FullName -Force -ErrorAction SilentlyContinue
        Write-Host "  Removed: $($pdb.Name)" -ForegroundColor Green
    }
} else {
    Write-Host "  No PDB files found" -ForegroundColor Gray
}

Write-Host ""
Write-Host "Installation Summary:" -ForegroundColor Cyan
Get-ChildItem $destDir | Select-Object Name, @{N='Size(KB)';E={[math]::Round($_.Length/1KB, 2)}}, LastWriteTime | Format-Table -AutoSize

Write-Host ""
Write-Host "SUCCESS: Release DLL installed!" -ForegroundColor Green
Write-Host "You can now start Notepad++ to use the Release build." -ForegroundColor Yellow
