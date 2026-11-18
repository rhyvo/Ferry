
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <stdio.h>
#include "dxgi-vsync-hooks.h"

static HMODULE self, real;
static int logging, vsync;

static void vsync_note(const char *text) {
    if (!logging) return;
    char path[MAX_PATH];
    DWORD n = GetModuleFileNameA(self, path, MAX_PATH);
    while (n > 0 && path[n - 1] != '\\') n--;
    lstrcpyA(path + n, "dxgi-vsync.log");
    FILE *f = fopen(path, "a");
    if (f) { fprintf(f, "%s\n", text); fclose(f); }
}

static FARPROC original(const char *name) {
    if (!real) {
        WCHAR mine[MAX_PATH], path[MAX_PATH];
        DWORD n = GetModuleFileNameW(self, mine, MAX_PATH);
        while (n > 0 && mine[n - 1] != L'\\') n--;
        UINT s = GetSystemDirectoryW(path, MAX_PATH);
        path[s] = L'\\';
        lstrcpyW(path + s + 1, mine + n);
        real = LoadLibraryW(path);
        vsync_note(real ? "loaded the real DLL from system32" : "could not load the real DLL from system32");
    }
    return real ? GetProcAddress(real, name) : NULL;
}

HRESULT WINAPI ferry_CreateDXGIFactory(REFIID iid, void **out) {
    typedef HRESULT (WINAPI *Fn)(REFIID, void **);
    Fn fn = (Fn)original("CreateDXGIFactory");
    HRESULT hr = fn ? fn(iid, out) : E_FAIL;
    if (vsync && SUCCEEDED(hr) && out) vsync_hookFactory(*out);
    return hr;
}

HRESULT WINAPI ferry_CreateDXGIFactory1(REFIID iid, void **out) {
    typedef HRESULT (WINAPI *Fn)(REFIID, void **);
    Fn fn = (Fn)original("CreateDXGIFactory1");
    HRESULT hr = fn ? fn(iid, out) : E_FAIL;
    if (vsync && SUCCEEDED(hr) && out) vsync_hookFactory(*out);
    return hr;
}

HRESULT WINAPI ferry_CreateDXGIFactory2(UINT flags, REFIID iid, void **out) {
    typedef HRESULT (WINAPI *Fn)(UINT, REFIID, void **);
    Fn fn = (Fn)original("CreateDXGIFactory2");
    HRESULT hr = fn ? fn(flags, iid, out) : E_FAIL;
    if (vsync && SUCCEEDED(hr) && out) vsync_hookFactory(*out);
    return hr;
}

HRESULT WINAPI ferry_DXGIGetDebugInterface1(UINT flags, REFIID iid, void **out) {
    typedef HRESULT (WINAPI *Fn)(UINT, REFIID, void **);
    Fn fn = (Fn)original("DXGIGetDebugInterface1");
    return fn ? fn(flags, iid, out) : E_NOINTERFACE;
}

HRESULT WINAPI ferry_DXGIDeclareAdapterRemovalSupport(void) {
    typedef HRESULT (WINAPI *Fn)(void);
    Fn fn = (Fn)original("DXGIDeclareAdapterRemovalSupport");
    return fn ? fn() : S_OK;
}

HRESULT WINAPI ferry_DXGID3D10CreateDevice(HMODULE d3d10core, void *factory, void *adapter, UINT flags,
                                          const void *levels, UINT count, void **device) {
    typedef HRESULT (WINAPI *Fn)(HMODULE, void *, void *, UINT, const void *, UINT, void **);
    Fn fn = (Fn)original("DXGID3D10CreateDevice");
    return fn ? fn(d3d10core, factory, adapter, flags, levels, count, device) : E_FAIL;
}

HRESULT WINAPI ferry_DXGID3D10RegisterLayers(const void *layers, UINT count) {
    typedef HRESULT (WINAPI *Fn)(const void *, UINT);
    Fn fn = (Fn)original("DXGID3D10RegisterLayers");
    return fn ? fn(layers, count) : E_FAIL;
}

HRESULT WINAPI ferry_D3D11CreateDevice(void *adapter, UINT type, HMODULE software, UINT flags, const void *levels,
                                       UINT count, UINT sdk, void **device, void *level, void **context) {
    typedef HRESULT (WINAPI *Fn)(void *, UINT, HMODULE, UINT, const void *, UINT, UINT, void **, void *, void **);
    Fn fn = (Fn)original("D3D11CreateDevice");
    HRESULT hr = fn ? fn(adapter, type, software, flags, levels, count, sdk, device, level, context) : E_FAIL;
    if (vsync && SUCCEEDED(hr) && device && *device) vsync_hookDeviceFactory(*device);
    return hr;
}

HRESULT WINAPI ferry_D3D11CreateDeviceAndSwapChain(void *adapter, UINT type, HMODULE software, UINT flags,
                                                   const void *levels, UINT count, UINT sdk, const void *desc,
                                                   void **chain, void **device, void *level, void **context) {
    typedef HRESULT (WINAPI *Fn)(void *, UINT, HMODULE, UINT, const void *, UINT, UINT, const void *, void **, void **,
                                 void *, void **);
    Fn fn = (Fn)original("D3D11CreateDeviceAndSwapChain");
    HRESULT hr = fn ? fn(adapter, type, software, flags, levels, count, sdk, desc, chain, device, level, context) : E_FAIL;
    if (vsync && SUCCEEDED(hr)) {
        if (chain && *chain) vsync_hookChain(*chain);
        if (device && *device) vsync_hookDeviceFactory(*device);
    }
    return hr;
}

HRESULT WINAPI ferry_D3D11On12CreateDevice(void *device, UINT flags, const void *levels, UINT count, void *const *queues,
                                           UINT queueCount, UINT mask, void **out, void **context, void *level) {
    typedef HRESULT (WINAPI *Fn)(void *, UINT, const void *, UINT, void *const *, UINT, UINT, void **, void **, void *);
    Fn fn = (Fn)original("D3D11On12CreateDevice");
    return fn ? fn(device, flags, levels, count, queues, queueCount, mask, out, context, level) : E_FAIL;
}

BOOL WINAPI DllMain(HINSTANCE instance, DWORD reason, LPVOID reserved) {
    (void)reserved;
    if (reason == DLL_PROCESS_ATTACH) {
        self = instance;
        char value[8];
        logging = GetEnvironmentVariableA("FERRY_DXGI_LOG", value, sizeof value) > 0;
        vsync = vsync_read_settings();
        vsync_init();
        DisableThreadLibraryCalls(instance);
    } else if (reason == DLL_PROCESS_DETACH && vsync_waits) {
        vsync_note("finished: frames waited for the display");
    }
    return TRUE;
}
