#include "AutoElevate.h"
#include <fstream>
#include <process.h>
#pragma comment(lib, "advapi32.lib")
#pragma comment(lib, "shell32.lib")

// Global plugin data
NppData g_nppData;
bool g_isElevated = false;
bool g_restartAttempted = false;
bool g_autoElevateEnabled = true; // Default: enabled
bool g_elevationCheckPerformed = false; // Track if elevation check has been done
DWORD g_pluginStartTime = 0; // Track when plugin was loaded

// Function items array (required by Notepad++ plugin interface)
FuncItem funcItem[nbFunc];

// Forward declaration
void PerformElevationCheck();

// Thread function for elevation check
unsigned int __stdcall ElevationCheckThread(void* param) {
    UNREFERENCED_PARAMETER(param);
    
    Sleep(3000);
    
    if (!g_elevationCheckPerformed) {
        PerformElevationCheck();
        g_elevationCheckPerformed = true;
    }
    
    return 0;
}

// Check if current process is running as administrator
bool IsRunAsAdmin() {
    BOOL isAdmin = FALSE;
    PSID adminGroup = NULL;
    SID_IDENTIFIER_AUTHORITY ntAuthority = SECURITY_NT_AUTHORITY;
    
    if (AllocateAndInitializeSid(&ntAuthority, 2, SECURITY_BUILTIN_DOMAIN_RID,
        DOMAIN_ALIAS_RID_ADMINS, 0, 0, 0, 0, 0, 0, &adminGroup)) {
        CheckTokenMembership(NULL, adminGroup, &isAdmin);
        FreeSid(adminGroup);
    }
    
    return isAdmin == TRUE;
}

// Get the full path to the Notepad++ executable
// GetModuleFileNameW with NULL returns the path to the current process (Notepad++.exe)
std::wstring GetExecutablePath() {
    wchar_t path[MAX_PATH];
    DWORD length = GetModuleFileNameW(NULL, path, MAX_PATH);
    if (length == 0 || length >= MAX_PATH) {
        return L"";
    }
    return std::wstring(path);
}

// Restart the current process with administrator privileges
// Uses a helper script that waits for current process to exit, then launches elevated
// Returns: true if helper script was launched successfully, false if failed
bool RestartAsAdmin() {
    std::wstring exePath = GetExecutablePath();
    if (exePath.empty()) {
        return false;
    }
    
    DWORD currentPid = GetCurrentProcessId();
    
    // Get temp directory
    wchar_t tempPath[MAX_PATH];
    if (GetTempPathW(MAX_PATH, tempPath) == 0) {
        return false;
    }
    
    // Create unique temp script filename
    wchar_t scriptPath[MAX_PATH];
    swprintf_s(scriptPath, MAX_PATH, L"%sAutoElevate_%d.ps1", tempPath, currentPid);
    
    // Create PowerShell script that waits for current process to exit, then launches elevated
    std::wofstream scriptFile(scriptPath);
    if (!scriptFile.is_open()) {
        return false;
    }
    
    // Escape the executable path for PowerShell
    std::wstring escapedPath = exePath;
    size_t pos = 0;
    while ((pos = escapedPath.find(L"'", pos)) != std::wstring::npos) {
        escapedPath.replace(pos, 1, L"''");
        pos += 2;
    }
    
    scriptFile << L"$targetPid = " << currentPid << L"\n";
    scriptFile << L"$exePath = '" << escapedPath << L"'\n";
    scriptFile << L"$maxWait = 30\n";
    scriptFile << L"$waited = 0\n";
    scriptFile << L"while ($waited -lt $maxWait) {\n";
    scriptFile << L"    $process = Get-Process -Id $targetPid -ErrorAction SilentlyContinue\n";
    scriptFile << L"    if (-not $process) {\n";
    scriptFile << L"        Start-Sleep -Milliseconds 500\n";
    scriptFile << L"        Start-Process -FilePath $exePath -Verb RunAs\n";
    scriptFile << L"        exit 0\n";
    scriptFile << L"    }\n";
    scriptFile << L"    Start-Sleep -Seconds 1\n";
    scriptFile << L"    $waited++\n";
    scriptFile << L"}\n";
    scriptFile << L"exit 1\n";
    scriptFile.close();
    
    // Launch the helper script
    STARTUPINFOW si = {0};
    si.cb = sizeof(si);
    PROCESS_INFORMATION pi = {0};
    
    wchar_t cmdLine[1024];
    swprintf_s(cmdLine, 1024, L"powershell.exe -NoProfile -ExecutionPolicy Bypass -File \"%s\"", scriptPath);
    
    if (!CreateProcessW(NULL, cmdLine, NULL, NULL, FALSE, CREATE_NO_WINDOW, NULL, NULL, &si, &pi)) {
        DeleteFileW(scriptPath);
        return false;
    }
    
    CloseHandle(pi.hThread);
    CloseHandle(pi.hProcess);
    
    Sleep(500);
    return true;
}

// Plugin name
extern "C" __declspec(dllexport) const wchar_t* getName() {
    return L"Auto Elevate";
}

// Get configuration file path
std::wstring GetConfigFilePath() {
    wchar_t configDir[MAX_PATH];
    // Try to get plugin config directory from Notepad++
    if (g_nppData._nppHandle != NULL) {
        ::SendMessage(g_nppData._nppHandle, NPPM_GETPLUGINSCONFIGDIR, MAX_PATH, (LPARAM)configDir);
        std::wstring path = std::wstring(configDir) + L"\\AutoElevate\\config.ini";
        return path;
    }
    // Fallback to AppData
    wchar_t appData[MAX_PATH];
    if (SHGetFolderPathW(NULL, CSIDL_APPDATA, NULL, SHGFP_TYPE_CURRENT, appData) == S_OK) {
        std::wstring path = std::wstring(appData) + L"\\Notepad++\\plugins\\config\\AutoElevate\\config.ini";
        return path;
    }
    return L"";
}

// Load settings from config file
void LoadSettings() {
    std::wstring configPath = GetConfigFilePath();
    if (configPath.empty()) {
        g_autoElevateEnabled = true; // Default
        return;
    }
    
    // Create directory if it doesn't exist
    size_t lastSlash = configPath.find_last_of(L"\\/");
    if (lastSlash != std::wstring::npos) {
        std::wstring dir = configPath.substr(0, lastSlash);
        CreateDirectoryW(dir.c_str(), NULL);
    }
    
    std::wifstream file(configPath);
    if (file.is_open()) {
        std::wstring line;
        while (std::getline(file, line)) {
            if (line.find(L"AutoElevate=") == 0) {
                std::wstring value = line.substr(12);
                g_autoElevateEnabled = (value == L"1" || value == L"true" || value == L"True");
            }
        }
        file.close();
    }
}

// Save settings to config file
void SaveSettings() {
    std::wstring configPath = GetConfigFilePath();
    if (configPath.empty()) {
        return;
    }
    
    // Create directory if it doesn't exist
    size_t lastSlash = configPath.find_last_of(L"\\/");
    if (lastSlash != std::wstring::npos) {
        std::wstring dir = configPath.substr(0, lastSlash);
        CreateDirectoryW(dir.c_str(), NULL);
    }
    
    std::wofstream file(configPath);
    if (file.is_open()) {
        file << L"AutoElevate=" << (g_autoElevateEnabled ? L"1" : L"0") << std::endl;
        file.close();
    }
}

// Toggle auto-elevate setting
void ToggleAutoElevate() {
    g_autoElevateEnabled = !g_autoElevateEnabled;
    SaveSettings();
    
    // Update the menu item check state
    funcItem[1]._init2Check = g_autoElevateEnabled;
    
    // Show confirmation message
    ::MessageBoxW(g_nppData._nppHandle, 
        g_autoElevateEnabled ? 
            L"Auto-elevate on startup is now ENABLED.\n\nNotepad++ will automatically request elevation when it starts." :
            L"Auto-elevate on startup is now DISABLED.\n\nNotepad++ will start normally without requesting elevation.",
        L"Auto Elevate", MB_OK | MB_ICONINFORMATION);
}

// Manual elevation command
void ManualElevate() {
    if (IsRunAsAdmin()) {
        ::MessageBoxW(g_nppData._nppHandle, 
            L"Notepad++ is already running with administrator privileges.",
            L"Auto Elevate", MB_OK | MB_ICONINFORMATION);
        return;
    }
    
    if (RestartAsAdmin()) {
        Sleep(1000);
        if (g_nppData._nppHandle != NULL && IsWindow(g_nppData._nppHandle)) {
            PostMessage(g_nppData._nppHandle, WM_CLOSE, 0, 0);
        }
    }
}

// Initialize plugin commands
void commandMenuInit() {
    // Menu item 0: Manual Elevate
    wcscpy_s(funcItem[0]._itemName, 64, L"Elevate");
    funcItem[0]._pFunc = ManualElevate;
    funcItem[0]._init2Check = false;
    funcItem[0]._pShKey = nullptr;
    funcItem[0]._cmdID = 0;
    
    // Menu item 1: Toggle Auto-Elevate
    wcscpy_s(funcItem[1]._itemName, 64, L"Auto-Elevate on Startup");
    funcItem[1]._pFunc = ToggleAutoElevate;
    funcItem[1]._init2Check = g_autoElevateEnabled;
    funcItem[1]._pShKey = nullptr;
    funcItem[1]._cmdID = 1;
}

// Perform elevation check (called from thread)
void PerformElevationCheck() {
    if (!g_autoElevateEnabled || g_restartAttempted) {
        return;
    }
    
    // Prevent newly elevated instances from immediately trying to elevate again
    if (g_pluginStartTime != 0) {
        DWORD elapsed = GetTickCount() - g_pluginStartTime;
        if (elapsed < 2000) {
            return;
        }
    }
    
    g_isElevated = IsRunAsAdmin();
    if (!g_isElevated) {
        g_restartAttempted = true;
        if (RestartAsAdmin()) {
            Sleep(1500);
            if (g_nppData._nppHandle != NULL && IsWindow(g_nppData._nppHandle)) {
                PostMessage(g_nppData._nppHandle, WM_CLOSE, 0, 0);
            }
        } else {
            g_restartAttempted = false;
        }
    }
}

// Set plugin info
extern "C" __declspec(dllexport) void setInfo(NppData nppData) {
    g_pluginStartTime = GetTickCount();
    g_nppData = nppData;
    
    LoadSettings();
    commandMenuInit();
    funcItem[1]._init2Check = g_autoElevateEnabled;
    
    // Start thread for elevation check (waits 3 seconds then performs check)
    HANDLE hThread = (HANDLE)_beginthreadex(NULL, 0, ElevationCheckThread, NULL, 0, NULL);
    if (hThread != NULL) {
        CloseHandle(hThread);
    }
}

// Handle notifications from Notepad++
extern "C" __declspec(dllexport) void beNotified(SCNotification* notification) {
    UNREFERENCED_PARAMETER(notification);
}

// Handle messages from Notepad++
extern "C" __declspec(dllexport) LRESULT messageProc(UINT message, WPARAM wParam, LPARAM lParam) {
    UNREFERENCED_PARAMETER(message);
    UNREFERENCED_PARAMETER(wParam);
    UNREFERENCED_PARAMETER(lParam);
    return 0;
}

// Indicate Unicode support
extern "C" __declspec(dllexport) BOOL isUnicode() {
    return TRUE;
}

// Get function array (required by Notepad++ plugin interface)
extern "C" __declspec(dllexport) FuncItem* getFuncsArray(int* pnbFuncItems) {
    *pnbFuncItems = nbFunc;
    return funcItem;
}

// DLL Entry Point
BOOL APIENTRY DllMain(HMODULE hModule, DWORD dwReason, LPVOID lpReserved) {
    switch (dwReason) {
        case DLL_PROCESS_ATTACH:
            DisableThreadLibraryCalls(hModule);
            break;
        case DLL_PROCESS_DETACH:
            break;
    }
    return TRUE;
}
