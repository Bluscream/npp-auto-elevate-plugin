#ifndef AUTO_ELEVATE_H
#define AUTO_ELEVATE_H

#include <windows.h>
#include <shellapi.h>
#include <shlobj.h>
#include <sddl.h>
#include <string>

// Notepad++ Plugin Interface
#define NPPMSG (WM_USER + 1000)
#define NPPM_GETPLUGINSCONFIGDIR (NPPMSG + 46)
#define NPPM_GETMENUHANDLE (NPPMSG + 25)
#define NPPPLUGINMENU 0
#define NPPN_FIRST 1000
#define NPPN_READY (NPPN_FIRST + 1)

// Function pointer type for plugin commands
typedef void (__cdecl *PFUNCPLUGINCMD)();

// Shortcut key structure
struct ShortcutKey {
    bool _isCtrl = false;
    bool _isAlt = false;
    bool _isShift = false;
    UCHAR _key = 0;
};

// SCNotification structure (simplified version)
struct SCNotification {
    struct SciNotifyHeader {
        void* hwndFrom;
        unsigned int idFrom;
        unsigned int code;
    } nmhdr;
    int position;
    int ch;
    int modifiers;
    int modificationType;
    const char* text;
    int length;
    int linesAdded;
    int message;
    unsigned long long wParam;
    long long lParam;
    int line;
    int foldLevelNow;
    int foldLevelPrev;
    int margin;
    int listType;
    int x;
    int y;
    int token;
    int annotationLinesAdded;
    int updated;
    int listCompletionMethod;
    int characterSource;
};

// Plugin data structure
struct NppData {
    HWND _nppHandle;
    HWND _scintillaMainHandle;
    HWND _scintillaSecondHandle;
};

// Function item structure for plugin menu
struct FuncItem {
    wchar_t _itemName[64];
    PFUNCPLUGINCMD _pFunc;
    int _cmdID;
    bool _init2Check;
    ShortcutKey* _pShKey;
};

// Number of plugin commands
const int nbFunc = 2;

// Function declarations
extern "C" __declspec(dllexport) const wchar_t* getName();
extern "C" __declspec(dllexport) void setInfo(NppData);
extern "C" __declspec(dllexport) void beNotified(SCNotification*);
extern "C" __declspec(dllexport) LRESULT messageProc(UINT, WPARAM, LPARAM);
extern "C" __declspec(dllexport) BOOL isUnicode();
extern "C" __declspec(dllexport) FuncItem* getFuncsArray(int* pnbFuncItems);

// Helper functions
bool IsRunAsAdmin();
bool RestartAsAdmin();
std::wstring GetExecutablePath();
std::wstring GetConfigFilePath();
void LoadSettings();
void SaveSettings();
void __cdecl ToggleAutoElevate();
void __cdecl ManualElevate();
void commandMenuInit();

// Settings
extern bool g_autoElevateEnabled;

#endif // AUTO_ELEVATE_H
