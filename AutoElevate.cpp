#include "AutoElevate.h"
#include <psapi.h>
#include <tlhelp32.h>
#include <fstream>
#include <sstream>
#include <iomanip>
#include <process.h>
#include <vector>
#pragma comment(lib, "advapi32.lib")
#pragma comment(lib, "shell32.lib")
#pragma comment(lib, "psapi.lib")

// No timer needed - we use NPPN_READY notification instead

// Debug logging
#ifdef _DEBUG
#define DEBUG_LOG(msg) DebugLog(msg)
#else
#define DEBUG_LOG(msg) ((void)0)
#endif

void DebugLog(const wchar_t* message) {
    // Output to debugger (visible in Visual Studio Output window or DebugView)
    OutputDebugStringW(L"[AutoElevate] ");
    OutputDebugStringW(message);
    OutputDebugStringW(L"\n");
    
    // Also write to a log file in AppData
    wchar_t appData[MAX_PATH];
    if (SHGetFolderPathW(NULL, CSIDL_APPDATA, NULL, SHGFP_TYPE_CURRENT, appData) == S_OK) {
        std::wstring logPath = std::wstring(appData) + L"\\Notepad++\\plugins\\config\\AutoElevate\\debug.log";
        
        // Create directory if it doesn't exist
        size_t lastSlash = logPath.find_last_of(L"\\/");
        if (lastSlash != std::wstring::npos) {
            std::wstring dir = logPath.substr(0, lastSlash);
            CreateDirectoryW(dir.c_str(), NULL);
        }
        
        std::wofstream logFile(logPath, std::ios::app);
        if (logFile.is_open()) {
            SYSTEMTIME st;
            GetLocalTime(&st);
            logFile << std::setfill(L'0') << std::setw(2) << st.wHour << L":"
                    << std::setw(2) << st.wMinute << L":" << std::setw(2) << st.wSecond
                    << L" - " << message << std::endl;
            logFile.close();
        }
    }
}

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

// Thread function for fallback elevation check
unsigned int __stdcall ElevationCheckThread(void* param) {
    UNREFERENCED_PARAMETER(param);
    
    DebugLog(L"ElevationCheckThread: Starting, waiting 3 seconds...");
    Sleep(3000);
    
    if (!g_elevationCheckPerformed) {
        DebugLog(L"ElevationCheckThread: Timer expired, performing elevation check");
        PerformElevationCheck();
        g_elevationCheckPerformed = true;
    } else {
        DebugLog(L"ElevationCheckThread: Elevation check already performed, exiting");
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
        DebugLog(L"RestartAsAdmin: Failed to get executable path");
        return false;
    }
    
    DWORD currentPid = GetCurrentProcessId();
    wchar_t msg[200];
    swprintf_s(msg, 200, L"RestartAsAdmin: Current PID=%d, creating helper script", currentPid);
    DebugLog(msg);
    
    // Get temp directory
    wchar_t tempPath[MAX_PATH];
    if (GetTempPathW(MAX_PATH, tempPath) == 0) {
        DebugLog(L"RestartAsAdmin: Failed to get temp path");
        return false;
    }
    
    // Create unique temp script filename
    wchar_t scriptPath[MAX_PATH];
    swprintf_s(scriptPath, MAX_PATH, L"%sAutoElevate_%d.ps1", tempPath, currentPid);
    
    // Create PowerShell script that:
    // 1. Waits for current Notepad++ process to exit
    // 2. Launches Notepad++ elevated
    std::wofstream scriptFile(scriptPath);
    if (!scriptFile.is_open()) {
        swprintf_s(msg, 200, L"RestartAsAdmin: Failed to create script file: %s", scriptPath);
        DebugLog(msg);
        return false;
    }
    
    // Escape the executable path for PowerShell
    std::wstring escapedPath = exePath;
    size_t pos = 0;
    while ((pos = escapedPath.find(L"'", pos)) != std::wstring::npos) {
        escapedPath.replace(pos, 1, L"''");
        pos += 2;
    }
    
    scriptFile << L"# AutoElevate helper script - waits for Notepad++ to close, then launches elevated\n";
    scriptFile << L"$targetPid = " << currentPid << L"\n";
    scriptFile << L"$exePath = '" << escapedPath << L"'\n";
    scriptFile << L"\n";
    scriptFile << L"Write-Host \"Waiting for Notepad++ process (PID=$targetPid) to exit...\"\n";
    scriptFile << L"$maxWait = 30  # Wait up to 30 seconds\n";
    scriptFile << L"$waited = 0\n";
    scriptFile << L"while ($waited -lt $maxWait) {\n";
    scriptFile << L"    $process = Get-Process -Id $targetPid -ErrorAction SilentlyContinue\n";
    scriptFile << L"    if (-not $process) {\n";
    scriptFile << L"        Write-Host \"Process exited, launching elevated Notepad++...\"\n";
    scriptFile << L"        Start-Sleep -Milliseconds 500  # Brief delay to ensure process fully closed\n";
    scriptFile << L"        Start-Process -FilePath $exePath -Verb RunAs\n";
    scriptFile << L"        exit 0\n";
    scriptFile << L"    }\n";
    scriptFile << L"    Start-Sleep -Seconds 1\n";
    scriptFile << L"    $waited++\n";
    scriptFile << L"}\n";
    scriptFile << L"Write-Host \"Timeout waiting for process to exit\"\n";
    scriptFile << L"exit 1\n";
    scriptFile.close();
    
    swprintf_s(msg, 200, L"RestartAsAdmin: Created helper script: %s", scriptPath);
    DebugLog(msg);
    
    // Launch the helper script (non-elevated, it will launch Notepad++ elevated after we close)
    STARTUPINFOW si = {0};
    si.cb = sizeof(si);
    PROCESS_INFORMATION pi = {0};
    
    wchar_t cmdLine[1024];
    swprintf_s(cmdLine, 1024, L"powershell.exe -NoProfile -ExecutionPolicy Bypass -File \"%s\"", scriptPath);
    
    if (!CreateProcessW(NULL, cmdLine, NULL, NULL, FALSE, CREATE_NO_WINDOW, NULL, NULL, &si, &pi)) {
        DWORD error = GetLastError();
        swprintf_s(msg, 200, L"RestartAsAdmin: Failed to launch helper script, error=%d", error);
        DebugLog(msg);
        DeleteFileW(scriptPath); // Clean up
        return false;
    }
    
    CloseHandle(pi.hThread);
    CloseHandle(pi.hProcess);
    
    swprintf_s(msg, 200, L"RestartAsAdmin: Helper script launched (PID=%d), will wait for this process to exit", pi.dwProcessId);
    DebugLog(msg);
    
    // Give the script a moment to start
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
    DebugLog(L"ManualElevate called");
    
    if (IsRunAsAdmin()) {
        DebugLog(L"Already elevated");
        ::MessageBoxW(g_nppData._nppHandle, 
            L"Notepad++ is already running with administrator privileges.",
            L"Auto Elevate", MB_OK | MB_ICONINFORMATION);
        return;
    }
    
    DebugLog(L"Requesting elevation...");
    // Request elevation immediately (no confirmation dialog)
    if (RestartAsAdmin()) {
        DebugLog(L"Elevation succeeded, closing current instance");
        
        // Give the new process time to fully start before closing
        Sleep(1000);
        
        // Validate window handle before using it
        if (g_nppData._nppHandle != NULL && IsWindow(g_nppData._nppHandle)) {
            DebugLog(L"Sending WM_CLOSE to current instance");
            // Exit current instance
            PostMessage(g_nppData._nppHandle, WM_CLOSE, 0, 0);
        } else {
            DebugLog(L"Invalid window handle, cannot close");
        }
    } else {
        DebugLog(L"Elevation failed or cancelled");
    }
    // If elevation failed (user cancelled UAC), just continue running normally
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

// Perform elevation check (called from timer or notification)
void PerformElevationCheck() {
    DebugLog(L"PerformElevationCheck called");
    
    // Check if auto-elevate is enabled
    if (!g_autoElevateEnabled) {
        DebugLog(L"Auto-elevate is disabled, skipping");
        return;
    }
    
    // Prevent multiple restart attempts
    if (g_restartAttempted) {
        DebugLog(L"Restart already attempted, skipping");
        return;
    }
    
    // If plugin just started (within last 2 seconds), wait a bit more
    // This prevents newly elevated instances from immediately trying to elevate again
    if (g_pluginStartTime != 0) {
        DWORD currentTime = GetTickCount();
        DWORD elapsed = currentTime - g_pluginStartTime;
        if (elapsed < 2000) {
            wchar_t msg[200];
            swprintf_s(msg, 200, L"Plugin just started (%d ms ago), waiting before elevation check", elapsed);
            DebugLog(msg);
            return;
        }
    }
    
    // Check if we're already elevated
    g_isElevated = IsRunAsAdmin();
    DebugLog(g_isElevated ? L"Already running as admin" : L"Not running as admin");
    
    // If not elevated, restart as admin
    if (!g_isElevated) {
        DebugLog(L"Attempting to restart as admin...");
        g_restartAttempted = true;
        
        // Only close current instance if elevation was successful
        if (RestartAsAdmin()) {
            DebugLog(L"RestartAsAdmin succeeded, closing current instance");
            // Wait a bit more to ensure the new process is fully started
            Sleep(1500);
            
            // Validate window handle before using it
            if (g_nppData._nppHandle != NULL && IsWindow(g_nppData._nppHandle)) {
                DebugLog(L"Sending WM_CLOSE to current instance");
                // Exit current instance
                PostMessage(g_nppData._nppHandle, WM_CLOSE, 0, 0);
            }
        } else {
            DebugLog(L"RestartAsAdmin failed or cancelled");
            // Reset flag if elevation failed so user can try again
            g_restartAttempted = false;
        }
        // If elevation failed or was cancelled, continue running normally
    }
}

// Set plugin info
extern "C" __declspec(dllexport) void setInfo(NppData nppData) {
    // Record plugin start time
    g_pluginStartTime = GetTickCount();
    
    DebugLog(L"setInfo called - plugin initializing");
    g_nppData = nppData;
    
    wchar_t msg[200];
    swprintf_s(msg, 200, L"setInfo: nppHandle=%p, scintillaMain=%p, scintillaSecond=%p",
               g_nppData._nppHandle, g_nppData._scintillaMainHandle, g_nppData._scintillaSecondHandle);
    DebugLog(msg);
    
    // Load settings
    LoadSettings();
    DebugLog(g_autoElevateEnabled ? L"Auto-elevate enabled in settings" : L"Auto-elevate disabled in settings");
    
    // Initialize menu commands
    commandMenuInit();
    
    // Update menu item check state based on settings
    funcItem[1]._init2Check = g_autoElevateEnabled;
    
    // Set up multiple fallback mechanisms in case NPPN_READY is never received
    // 1. Windows timer (may not work if messageProc doesn't receive WM_TIMER)
    if (g_nppData._nppHandle != NULL && IsWindow(g_nppData._nppHandle)) {
        UINT_PTR timerId = SetTimer(g_nppData._nppHandle, 999, 3000, NULL);
        if (timerId != 0) {
            wchar_t timerMsg[200];
            swprintf_s(timerMsg, 200, L"Windows timer set (3 seconds), timerId=%p", (void*)timerId);
            DebugLog(timerMsg);
        } else {
            DebugLog(L"Failed to set Windows timer!");
        }
    } else {
        DebugLog(L"Invalid window handle, cannot set Windows timer");
    }
    
    // 2. Thread-based fallback (more reliable)
    HANDLE hThread = (HANDLE)_beginthreadex(NULL, 0, ElevationCheckThread, NULL, 0, NULL);
    if (hThread != NULL) {
        DebugLog(L"Fallback thread created for elevation check");
        CloseHandle(hThread); // We don't need to wait for it
    } else {
        DebugLog(L"Failed to create fallback thread!");
    }
    
    DebugLog(L"setInfo complete, waiting for NPPN_READY, timer, or thread");
}

// Handle notifications from Notepad++
extern "C" __declspec(dllexport) void beNotified(SCNotification* notification) {
    if (notification == NULL) {
        DebugLog(L"beNotified called with NULL notification");
        return;
    }
    
    // Log notification details for debugging
    unsigned int code = notification->nmhdr.code;
    
    // Handle NPPN_READY notification - Notepad++ is fully initialized
    // NPPN_READY = NPPN_FIRST + 1 = 1000 + 1 = 1001
    if (code == NPPN_READY) {
        wchar_t msg[200];
        swprintf_s(msg, 200, L"NPPN_READY notification received! (code=%d, idFrom=%d)", 
                   code, notification->nmhdr.idFrom);
        DebugLog(msg);
        
        // Perform elevation check after a short delay to ensure everything is ready
        Sleep(500);
        if (!g_elevationCheckPerformed) {
            PerformElevationCheck();
            g_elevationCheckPerformed = true;
        } else {
            DebugLog(L"NPPN_READY: Elevation check already performed, skipping");
        }
    } else if (code >= NPPN_FIRST && code < NPPN_FIRST + 50) {
        // Log other NPPN notifications
        wchar_t msg[200];
        swprintf_s(msg, 200, L"NPPN notification: code=%d (idFrom=%d)", 
                   code, notification->nmhdr.idFrom);
        DebugLog(msg);
    } else if (code < NPPN_FIRST) {
        // Log first few Scintilla notifications to see what we're getting
        static int scintillaCount = 0;
        if (scintillaCount < 5) {
            wchar_t msg[200];
            swprintf_s(msg, 200, L"Scintilla notification: code=%d (idFrom=%d)", 
                       code, notification->nmhdr.idFrom);
            DebugLog(msg);
            scintillaCount++;
        }
    }
}

// Handle messages from Notepad++
extern "C" __declspec(dllexport) LRESULT messageProc(UINT message, WPARAM wParam, LPARAM lParam) {
    // Log first few messages to see if messageProc is being called
    static int messageCount = 0;
    if (messageCount < 5) {
        wchar_t msg[200];
        swprintf_s(msg, 200, L"messageProc called: message=0x%04X, wParam=0x%p, lParam=0x%p", 
                   message, (void*)wParam, (void*)lParam);
        DebugLog(msg);
        messageCount++;
    }
    
    // Handle fallback timer for auto-elevation
    if (message == WM_TIMER && wParam == 999) {
        DebugLog(L"Windows timer fired - performing elevation check");
        KillTimer(g_nppData._nppHandle, 999);
        if (!g_elevationCheckPerformed) {
            PerformElevationCheck();
            g_elevationCheckPerformed = true;
        } else {
            DebugLog(L"Windows timer: Elevation check already performed, skipping");
        }
        return 0;
    }
    
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
