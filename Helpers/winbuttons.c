
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <shellapi.h>
#include <wchar.h>

static WCHAR folder[1024];
static size_t folderLength;
static int foundWindow;

static BOOL fromGameFolder(DWORD pid) {
    HANDLE process = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, FALSE, pid);
    if (!process) return FALSE;
    WCHAR path[1024];
    DWORD length = 1024;
    BOOL ok = QueryFullProcessImageNameW(process, 0, path, &length);
    CloseHandle(process);
    return ok && length > folderLength && _wcsnicmp(path, folder, folderLength) == 0;
}

static BOOL CALLBACK visit(HWND window, LPARAM unused) {
    (void)unused;
    DWORD pid = 0;
    GetWindowThreadProcessId(window, &pid);
    if (pid == GetCurrentProcessId() || !IsWindowVisible(window) || GetWindow(window, GW_OWNER)) return TRUE;
    if (!fromGameFolder(pid)) return TRUE;
    foundWindow = 1;
    LONG style = GetWindowLongW(window, GWL_STYLE);
    if ((style & WS_CAPTION) == WS_CAPTION && !(style & (WS_MAXIMIZEBOX | WS_CHILD))) {
        SetWindowLongW(window, GWL_STYLE, style | WS_MAXIMIZEBOX);
        SetWindowPos(window, NULL, 0, 0, 0, 0,
                     SWP_NOMOVE | SWP_NOSIZE | SWP_NOZORDER | SWP_NOACTIVATE | SWP_NOOWNERZORDER | SWP_FRAMECHANGED);
    }
    return TRUE;
}

int WINAPI wWinMain(HINSTANCE instance, HINSTANCE previous, PWSTR commandLine, int show) {
    (void)instance; (void)previous; (void)commandLine; (void)show;
    int count = 0;
    LPWSTR *args = CommandLineToArgvW(GetCommandLineW(), &count);
    if (!args || count < 2) return 1;
    size_t length = wcslen(args[1]);
    if (length == 0 || length > 1000) return 1;
    wcscpy(folder, args[1]);
    if (folder[length - 1] != L'\\') { folder[length++] = L'\\'; folder[length] = 0; }
    folderLength = length;
    LocalFree(args);

    int idleSeconds = 0;
    while (idleSeconds < 120) {
        foundWindow = 0;
        EnumWindows(visit, 0);
        idleSeconds = foundWindow ? 0 : idleSeconds + 1;
        Sleep(1000);
    }
    return 0;
}
