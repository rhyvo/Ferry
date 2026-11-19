
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include "pad-remap.h"

typedef struct {
    WORD wButtons;
    BYTE bLeftTrigger, bRightTrigger;
    SHORT sThumbLX, sThumbLY, sThumbRX, sThumbRY;
} PAD;
typedef struct { DWORD dwPacketNumber; PAD Gamepad; } PAD_STATE;

static HMODULE self, real;
static int remapping;

static FARPROC original(const char *name) {
    if (!real) {
        WCHAR mine[MAX_PATH], path[MAX_PATH];
        DWORD n = GetModuleFileNameW(self, mine, MAX_PATH);
        while (n > 0 && mine[n - 1] != L'\\') n--;
        UINT s = GetSystemDirectoryW(path, MAX_PATH);
        path[s] = L'\\';
        lstrcpyW(path + s + 1, mine + n);
        real = LoadLibraryW(path);
    }
    return real ? GetProcAddress(real, name) : NULL;
}

typedef DWORD (WINAPI *GetStateFn)(DWORD, PAD_STATE *);

static DWORD getState(const char *name, DWORD user, PAD_STATE *state) {
    GetStateFn fn = (GetStateFn)original(name);
    DWORD r = fn ? fn(user, state) : ERROR_DEVICE_NOT_CONNECTED;
    if (r == ERROR_SUCCESS && state && remapping)
        pad_remap(&state->Gamepad.wButtons, &state->Gamepad.bLeftTrigger, &state->Gamepad.bRightTrigger);
    return r;
}

DWORD WINAPI ferry_XInputGetState(DWORD user, PAD_STATE *state) { return getState("XInputGetState", user, state); }

DWORD WINAPI ferry_XInputGetStateEx(DWORD user, PAD_STATE *state) {
    GetStateFn fn = (GetStateFn)original((LPCSTR)100);
    return fn ? getState((LPCSTR)100, user, state) : getState("XInputGetState", user, state);
}

#define PASS(ret, fail, name, params, args)                                                                           \
    ret WINAPI ferry_##name params {                                                                                   \
        typedef ret (WINAPI *Fn) params;                                                                               \
        Fn fn = (Fn)original(#name);                                                                                   \
        return fn ? fn args : fail;                                                                                    \
    }
#define PASS_ORDINAL(ret, fail, name, ordinal, params, args)                                                          \
    ret WINAPI ferry_##name params {                                                                                   \
        typedef ret (WINAPI *Fn) params;                                                                               \
        Fn fn = (Fn)original((LPCSTR)ordinal);                                                                         \
        return fn ? fn args : fail;                                                                                    \
    }

PASS(DWORD, ERROR_DEVICE_NOT_CONNECTED, XInputSetState, (DWORD u, void *v), (u, v))
PASS(DWORD, ERROR_DEVICE_NOT_CONNECTED, XInputGetCapabilities, (DWORD u, DWORD f, void *c), (u, f, c))
PASS(DWORD, ERROR_DEVICE_NOT_CONNECTED, XInputGetDSoundAudioDeviceGuids, (DWORD u, GUID *r, GUID *c), (u, r, c))
PASS(DWORD, ERROR_DEVICE_NOT_CONNECTED, XInputGetBatteryInformation, (DWORD u, BYTE t, void *b), (u, t, b))
PASS(DWORD, ERROR_DEVICE_NOT_CONNECTED, XInputGetKeystroke, (DWORD u, DWORD r, void *k), (u, r, k))
PASS(DWORD, ERROR_DEVICE_NOT_CONNECTED, XInputGetAudioDeviceIds, (DWORD u, WCHAR *r, UINT *rc, WCHAR *c, UINT *cc),
     (u, r, rc, c, cc))
PASS_ORDINAL(DWORD, ERROR_DEVICE_NOT_CONNECTED, XInputWaitForGuideButton, 101, (DWORD u, DWORD f, void *l), (u, f, l))
PASS_ORDINAL(DWORD, ERROR_DEVICE_NOT_CONNECTED, XInputCancelGuideButtonWait, 102, (DWORD u), (u))
PASS_ORDINAL(DWORD, ERROR_DEVICE_NOT_CONNECTED, XInputPowerOffController, 103, (DWORD u), (u))
PASS_ORDINAL(DWORD, ERROR_DEVICE_NOT_CONNECTED, XInputGetBaseBusInformation, 104, (DWORD u, void *i), (u, i))
PASS_ORDINAL(DWORD, ERROR_DEVICE_NOT_CONNECTED, XInputGetCapabilitiesEx, 108, (DWORD a, DWORD u, DWORD f, void *c),
             (a, u, f, c))

void WINAPI ferry_XInputEnable(BOOL enable) {
    typedef void (WINAPI *Fn)(BOOL);
    Fn fn = (Fn)original("XInputEnable");
    if (fn) fn(enable);
}

BOOL WINAPI DllMain(HINSTANCE instance, DWORD reason, LPVOID reserved) {
    (void)reserved;
    if (reason == DLL_PROCESS_ATTACH) {
        self = instance;
        char map[512];
        DWORD n = GetEnvironmentVariableA("FERRY_PAD_MAP", map, sizeof map);
        remapping = n > 0 && n < sizeof map && pad_parse(map);
        DisableThreadLibraryCalls(instance);
    }
    return TRUE;
}
