# Auto Elevate Plugin v0.0.0.1

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

- **Debug Build**: Includes debug symbols, larger file size (~750 KB)
- **Release Build**: Optimized, smaller file size (~60 KB)

## Notes

- Requires UAC approval to elevate
- Running applications with administrator privileges can pose security risks
- Helper scripts are created in `%TEMP%` and cleaned up automatically
