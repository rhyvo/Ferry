
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <mmsystem.h>
#include <tlhelp32.h>
#include <wchar.h>
#include "pad-keys.h"

typedef struct {
    WORD wButtons;
    BYTE bLeftTrigger, bRightTrigger;
    SHORT sThumbLX, sThumbLY, sThumbRX, sThumbRY;
} PAD;
typedef struct { DWORD dwPacketNumber; PAD Gamepad; } PAD_STATE;
typedef DWORD (WINAPI *GetStateFn)(DWORD, PAD_STATE *);

static WCHAR folder[1024];
static size_t folderLength;

static BOOL fromGameFolder(DWORD pid) {
    HANDLE process = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, FALSE, pid);
    if (!process) return FALSE;
    WCHAR path[1024];
    DWORD length = 1024;
    BOOL ok = QueryFullProcessImageNameW(process, 0, path, &length);
    CloseHandle(process);
    return ok && length > folderLength && _wcsnicmp(path, folder, folderLength) == 0;
}

static BOOL gameRunning(void) {
    HANDLE snap = CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0);
    if (snap == INVALID_HANDLE_VALUE) return TRUE;
    PROCESSENTRY32W entry = { .dwSize = sizeof entry };
    BOOL found = FALSE;
    for (BOOL more = Process32FirstW(snap, &entry); more && !found; more = Process32NextW(snap, &entry))
        found = entry.th32ProcessID != GetCurrentProcessId() && fromGameFolder(entry.th32ProcessID);
    CloseHandle(snap);
    return found;
}

static DWORD focusPid;
static BOOL focusIsGame;
static BOOL mayType(void) {
    HWND window = GetForegroundWindow();
    if (!window) return TRUE;
    DWORD pid = 0;
    GetWindowThreadProcessId(window, &pid);
    if (pid != focusPid) { focusPid = pid; focusIsGame = fromGameFolder(pid); }
    return focusIsGame;
}

static void sendKey(int code, int down) {
    INPUT in = { .type = INPUT_KEYBOARD };
    in.ki.wScan = (WORD)(code & 0xFF);
    in.ki.dwFlags = KEYEVENTF_SCANCODE | (code & 0xE000 ? KEYEVENTF_EXTENDEDKEY : 0) | (down ? 0 : KEYEVENTF_KEYUP);
    SendInput(1, &in, sizeof in);
}

static void sendMouse(DWORD flags, LONG dx, LONG dy, DWORD data) {
    INPUT in = { .type = INPUT_MOUSE };
    in.mi.dx = dx;
    in.mi.dy = dy;
    in.mi.mouseData = data;
    in.mi.dwFlags = flags;
    SendInput(1, &in, sizeof in);
}

static void sendBind(int bind, int down) {
    if (bind >= PK_KEY) sendKey(bind - PK_KEY, down);
    else if (bind == PK_LEFT) sendMouse(down ? MOUSEEVENTF_LEFTDOWN : MOUSEEVENTF_LEFTUP, 0, 0, 0);
    else if (bind == PK_RIGHT) sendMouse(down ? MOUSEEVENTF_RIGHTDOWN : MOUSEEVENTF_RIGHTUP, 0, 0, 0);
    else if (bind == PK_MIDDLE) sendMouse(down ? MOUSEEVENTF_MIDDLEDOWN : MOUSEEVENTF_MIDDLEUP, 0, 0, 0);
    else if ((bind == PK_WHEEL_UP || bind == PK_WHEEL_DOWN) && down)
        sendMouse(MOUSEEVENTF_WHEEL, 0, 0, (DWORD)(bind == PK_WHEEL_UP ? WHEEL_DELTA : -WHEEL_DELTA));
}

static GetStateFn loadXInput(void) {
    const char *names[] = { "xinput1_4.dll", "xinput1_3.dll", "xinput9_1_0.dll" };
    for (int i = 0; i < 3; i++) {
        HMODULE m = LoadLibraryA(names[i]);
        FARPROC fn = m ? GetProcAddress(m, "XInputGetState") : NULL;
        if (fn) return (GetStateFn)fn;
    }
    return NULL;
}

int WINAPI wWinMain(HINSTANCE instance, HINSTANCE previous, PWSTR args, int show) {
    (void)instance; (void)previous; (void)show;
    const WCHAR *start = args;
    while (*start == L' ' || *start == L'"') start++;
    lstrcpynW(folder, start, 1024);
    folderLength = wcslen(folder);
    while (folderLength && (folder[folderLength - 1] == L'"' || folder[folderLength - 1] == L' ')) folder[--folderLength] = 0;
    if (folderLength && folder[folderLength - 1] != L'\\') { folder[folderLength++] = L'\\'; folder[folderLength] = 0; }

    char text[1024];
    DWORD n = GetEnvironmentVariableA("FERRY_PAD_KEYS", text, sizeof text);
    if (!n || n >= sizeof text || !pk_parse(text)) return 0;
    GetStateFn getState = loadXInput();
    if (!getState) return 0;
    timeBeginPeriod(1);

    int held[PK_CONTROLS] = {0}, stickKeys[2][4] = {{0}}, user = 0;
    DWORD lastWheel = 0, lastCheck = GetTickCount(), lastSeen = GetTickCount();
    float carryX = 0, carryY = 0;
    for (;;) {
        Sleep(8);
        DWORD now = GetTickCount();
        if (now - lastCheck > 5000) {
            lastCheck = now;
            if (gameRunning()) lastSeen = now;
            else if (now - lastSeen > 30000) break;
        }
        PAD_STATE s = {0};
        BOOL connected = getState(user, &s) == ERROR_SUCCESS;
        if (!connected) {
            for (int u = 0; u < 4 && !connected; u++) if (getState(u, &s) == ERROR_SUCCESS) { user = u; connected = TRUE; }
        }
        BOOL live = connected && mayType();
        int pressed[PK_CONTROLS];
        pk_held(live ? s.Gamepad.wButtons : 0, live ? s.Gamepad.bLeftTrigger : 0, live ? s.Gamepad.bRightTrigger : 0, pressed);
        for (int i = 0; i < PK_CONTROLS; i++) {
            if (pressed[i] != held[i] && pk_bind[i]) sendBind(pk_bind[i], pressed[i]);
            held[i] = pressed[i];
        }
        int wheel = 0;
        for (int i = 0; i < PK_CONTROLS; i++)
            if (held[i] && (pk_bind[i] == PK_WHEEL_UP || pk_bind[i] == PK_WHEEL_DOWN)) wheel = pk_bind[i];
        if (wheel && now - lastWheel > 150) { if (lastWheel) sendBind(wheel, 1); lastWheel = now; }
        if (!wheel) lastWheel = 0;
        SHORT axes[2][2] = { { s.Gamepad.sThumbLX, s.Gamepad.sThumbLY }, { s.Gamepad.sThumbRX, s.Gamepad.sThumbRY } };
        for (int k = 0; k < 2; k++) {
            int mode = pk_stick[k], dirs[4] = {0};
            if (live && (mode == PK_WASD || mode == PK_ARROWS)) pk_stick_keys(axes[k][0], axes[k][1], dirs);
            for (int d = 0; d < 4; d++) {
                int code = mode == PK_ARROWS ? pk_arrow_codes[d] : pk_wasd_codes[d];
                if (dirs[d] != stickKeys[k][d]) sendKey(code, dirs[d]);
                stickKeys[k][d] = dirs[d];
            }
            if (live && mode == PK_MOUSE) {
                float dx, dy;
                pk_mouse_step(axes[k][0], axes[k][1], pk_speed, &dx, &dy);
                carryX += dx;
                carryY += dy;
                LONG mx = (LONG)carryX, my = (LONG)carryY;
                if (mx || my) { sendMouse(MOUSEEVENTF_MOVE, mx, my, 0); carryX -= mx; carryY -= my; }
            }
        }
    }
    for (int i = 0; i < PK_CONTROLS; i++) if (held[i] && pk_bind[i]) sendBind(pk_bind[i], 0);
    timeEndPeriod(1);
    return 0;
}
