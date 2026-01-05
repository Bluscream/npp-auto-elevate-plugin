# Notepad++ Auto Elevate Plugin

Automatically elevates Notepad++ to run with administrator privileges on startup (if enabled) or via manual menu command.

## Features

- **Auto-Elevate on Startup**: Automatically requests elevation when Notepad++ starts (configurable)
- **Manual Elevate**: Menu command to elevate the current instance
- **Single-Instance Compatible**: Works correctly with Notepad++ single-instance mode
- **Settings Persistence**: Saves auto-elevate preference to config file
- **Debug Logging**: Comprehensive logging to `%APPDATA%\Notepad++\plugins\config\AutoElevate\debug.log`

## Building

### Prerequisites

- Windows 7 or later
- Visual Studio 2019 or later (with C++ desktop development workload)
- Notepad++ installed

### Build Steps

1. Open `AutoElevate.vcxproj` in Visual Studio, OR
2. Use the provided PowerShell script:
   ```powershell
   .\rebuild-and-install.ps1
   ```

The script will:
- Find MSBuild automatically
- Rebuild the project in Debug configuration
- Copy DLL and PDB files to Notepad++ plugins folder

### Manual Build

```powershell
# Find MSBuild (adjust path as needed)
$msbuild = "P:\Program Files\Microsoft Visual Studio\18\Insiders\MSBuild\Current\Bin\MSBuild.exe"

# Build Debug configuration
& $msbuild AutoElevate.vcxproj /p:Configuration=Debug /p:Platform=x64 /t:Rebuild
```

Output: `x64\Debug\AutoElevate.dll`

## Installation

1. Build the plugin (see above)
2. Copy `AutoElevate.dll` (and optionally `AutoElevate.pdb` + `vc145.pdb` for debugging) to:
   - `C:\Program Files\Notepad++\plugins\AutoElevate\` (requires admin)
   - OR `%APPDATA%\Notepad++\plugins\AutoElevate\`
3. Restart Notepad++

The plugin will appear in the Plugins menu.

## Usage

### Auto-Elevate on Startup

1. Go to **Plugins > Auto Elevate > Auto-Elevate on Startup**
2. Check the menu item to enable, uncheck to disable
3. Setting is saved to `config.ini` and persists across restarts

### Manual Elevation

1. Go to **Plugins > Auto Elevate > Elevate**
2. UAC prompt will appear
3. Approve to restart Notepad++ with admin privileges

## How It Works

### Auto-Elevation Flow

1. Plugin loads when Notepad++ starts
2. After 3 seconds (or when `NPPN_READY` notification is received), checks if running as admin
3. If not elevated and auto-elevate is enabled:
   - Creates a PowerShell helper script in temp directory
   - Launches helper script (non-elevated)
   - Helper script waits for current Notepad++ process to exit
   - Helper script launches Notepad++ elevated after process exits
   - Current instance closes
4. New elevated instance starts

### Single-Instance Mode Compatibility

Notepad++ single-instance mode prevents launching a new instance while one is running. This plugin uses a helper script approach:

1. Helper script is launched first (non-elevated)
2. Current Notepad++ instance closes
3. Helper script detects process exit
4. Helper script launches Notepad++ elevated (now that no instance is running)

## Configuration

Settings are stored in: `%APPDATA%\Notepad++\plugins\config\AutoElevate\config.ini`

Format:
```ini
AutoElevate=1
```
- `1` = Enabled
- `0` = Disabled

## Debugging

Debug logs are written to: `%APPDATA%\Notepad++\plugins\config\AutoElevate\debug.log`

To view logs in real-time:
- Use DebugView (Sysinternals)
- Or attach Visual Studio debugger to `notepad++.exe`

## Project Structure

```
auto-elevate/
├── AutoElevate.cpp          # Main plugin implementation
├── AutoElevate.h            # Plugin header and interface definitions
├── AutoElevate.vcxproj      # Visual Studio project file
├── AutoElevate.vcxproj.user # User-specific project settings
├── AutoElevate.sln          # Visual Studio solution file
├── rebuild-and-install.ps1   # Build and install script
├── README.md                # This file
└── x64/
    └── Debug/               # Build output directory
        ├── AutoElevate.dll  # Plugin DLL
        ├── AutoElevate.pdb  # Debug symbols
        └── vc145.pdb        # Compiler debug database
```

## Requirements

- Windows 7 or later
- Notepad++ (any recent version)
- Visual Studio 2019+ or Build Tools (for building)
- C++17 compatible compiler

## Notes

- The plugin requires UAC approval to elevate
- Running applications with administrator privileges can pose security risks
- Helper scripts are created in `%TEMP%` and cleaned up automatically
- Debug logging is always enabled (even in Release builds)

## License

This plugin is provided as-is for educational and personal use.
