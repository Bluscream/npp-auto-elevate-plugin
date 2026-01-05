# Auto Elevate Plugin v2026.0105.2

## Features

- **Auto-Elevate on Startup**: Automatically requests elevation when Notepad++ starts (configurable via menu)
- **Manual Elevate**: Menu command to elevate the current instance
- **Single-Instance Compatible**: Works correctly with Notepad++ single-instance mode using helper script approach
- **Settings Persistence**: Saves auto-elevate preference to config file
- **Debug Logging**: Comprehensive logging to %APPDATA%\Notepad++\plugins\config\AutoElevate\debug.log

## Installation

1. Download the appropriate DLL for your architecture:
   - **x64**: AutoElevate.Release.x64.dll (production) or AutoElevate.Debug.x64.dll (debugging)
   - **x86**: AutoElevate.Release.x86.dll (production) or AutoElevate.Debug.x86.dll (debugging)
2. Rename the downloaded file to AutoElevate.dll
3. Copy to C:\Program Files\Notepad++\plugins\AutoElevate\ (requires admin) or %APPDATA%\Notepad++\plugins\AutoElevate\
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
- Settings stored in %APPDATA%\Notepad++\plugins\config\AutoElevate\config.ini

## Build Information

- **Debug x64**: Includes debug symbols (~737.5 KB)
- **Debug x86**: Includes debug symbols (~526 KB)
- **Release x64**: Optimized (~53 KB)
- **Release x86**: Optimized (~48 KB)

## Notes

- Requires UAC approval to elevate
- Running applications with administrator privileges can pose security risks
- Helper scripts are created in %TEMP% and cleaned up automatically
