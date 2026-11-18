
#include <windows.h>
#include "vsync-pace.h"

static void vsync_note(const char *text);

static const GUID vsync_IID_IDXGIFactory   = {0x7b7166ec, 0x21c7, 0x44ae, {0xb2, 0x1a, 0xc9, 0xae, 0x32, 0x1a, 0xe3, 0x69}};
static const GUID vsync_IID_IDXGIFactory2  = {0x50c83a1c, 0xe072, 0x4c48, {0x87, 0xb0, 0x36, 0x30, 0xfa, 0x36, 0xa6, 0xd0}};
static const GUID vsync_IID_IDXGISwapChain = {0x310d36a0, 0xd2e7, 0x4c0a, {0xaa, 0x04, 0x6a, 0x9d, 0x23, 0xb8, 0x88, 0x6a}};
static const GUID vsync_IID_IDXGISwapChain1 = {0x790a45f7, 0x0d42, 0x4876, {0x98, 0x3a, 0x0a, 0x55, 0xcf, 0xe6, 0xf4, 0xaa}};
static const GUID vsync_IID_IDXGIDevice    = {0x54ec77fa, 0x1377, 0x44e6, {0x8c, 0x32, 0x88, 0xfd, 0x5f, 0x44, 0xc8, 0x4c}};

enum {
    VSYNC_QUERY = 0, VSYNC_RELEASE = 2,
    VSYNC_GET_PARENT = 6,
    VSYNC_GET_ADAPTER = 7,
    VSYNC_PRESENT = 8, VSYNC_PRESENT1 = 22,
    VSYNC_CREATE = 10,
    VSYNC_CREATE_HWND = 15, VSYNC_CREATE_CORE = 16, VSYNC_CREATE_COMPOSITION = 24
};

typedef HRESULT (STDMETHODCALLTYPE *vsync_QueryFn)(void *, REFIID, void **);
typedef ULONG (STDMETHODCALLTYPE *vsync_ReleaseFn)(void *);
typedef HRESULT (STDMETHODCALLTYPE *vsync_GetFn)(void *, REFIID, void **);
typedef HRESULT (STDMETHODCALLTYPE *vsync_GetAdapterFn)(void *, void **);
typedef HRESULT (STDMETHODCALLTYPE *vsync_PresentFn)(void *, UINT, UINT);
typedef HRESULT (STDMETHODCALLTYPE *vsync_Present1Fn)(void *, UINT, UINT, const void *);
typedef HRESULT (STDMETHODCALLTYPE *vsync_CreateFn)(void *, void *, void *, void **);
typedef HRESULT (STDMETHODCALLTYPE *vsync_CreateHwndFn)(void *, void *, HWND, const void *, const void *, void *, void **);
typedef HRESULT (STDMETHODCALLTYPE *vsync_CreateCoreFn)(void *, void *, void *, const void *, void *, void **);
typedef HRESULT (STDMETHODCALLTYPE *vsync_CreateCompositionFn)(void *, void *, const void *, void *, void **);

#define VSYNC_TABLES 16
#define VSYNC_SLOTS 25
static struct { void **table; void *saved[VSYNC_SLOTS]; } vsync_tables[VSYNC_TABLES];
static CRITICAL_SECTION vsync_lock;
static volatile LONG vsync_ready, vsync_waits;

static void vsync_init(void) {
    if (InterlockedCompareExchange(&vsync_ready, 1, 0) == 0) InitializeCriticalSection(&vsync_lock);
}

static void *vsync_saved(void *object, int slot) {
    void **table = *(void ***)object;
    for (int i = 0; i < VSYNC_TABLES; i++) if (vsync_tables[i].table == table) return vsync_tables[i].saved[slot];
    return NULL;
}

static void vsync_patch(void *object, int slot, void *hook) {
    void **table = *(void ***)object;
    EnterCriticalSection(&vsync_lock);
    int i = 0;
    while (i < VSYNC_TABLES && vsync_tables[i].table && vsync_tables[i].table != table) i++;
    if (i < VSYNC_TABLES && !vsync_tables[i].saved[slot] && table[slot] != hook) {
        DWORD old;
        if (VirtualProtect(&table[slot], sizeof(void *), PAGE_EXECUTE_READWRITE, &old)) {
            vsync_tables[i].table = table;
            vsync_tables[i].saved[slot] = table[slot];
            table[slot] = hook;
            VirtualProtect(&table[slot], sizeof(void *), old, &old);
        } else {
            vsync_note("couldn't patch a function table");
        }
    }
    LeaveCriticalSection(&vsync_lock);
}

static void *vsync_query(void *object, const GUID *iid) {
    void *out = NULL;
    if (!object) return NULL;
    if (FAILED(((vsync_QueryFn)(*(void ***)object)[VSYNC_QUERY])(object, (REFIID)iid, &out))) return NULL;
    return out;
}

static void vsync_release(void *object) {
    if (object) ((vsync_ReleaseFn)(*(void ***)object)[VSYNC_RELEASE])(object);
}

static void vsync_wait(UINT *interval, UINT *flags) {
    if (*flags & 0x1 ) return;
    if (vsync_sync && !*interval) {
        *interval = 1;
        *flags &= ~0x200u;
        if (InterlockedIncrement(&vsync_waits) == 1) vsync_note("the game presents without VSync; turning it on");
    }
    vsync_pace();
}

static volatile DWORD vsync_presenting;

static HRESULT STDMETHODCALLTYPE vsync_present(void *chain, UINT interval, UINT flags) {
    vsync_PresentFn fn = (vsync_PresentFn)vsync_saved(chain, VSYNC_PRESENT);
    if (!fn) return E_FAIL;
    DWORD me = GetCurrentThreadId();
    if (vsync_presenting == me) return fn(chain, interval, flags);
    vsync_wait(&interval, &flags);
    vsync_presenting = me;
    HRESULT hr = fn(chain, interval, flags);
    vsync_presenting = 0;
    return hr;
}

static HRESULT STDMETHODCALLTYPE vsync_present1(void *chain, UINT interval, UINT flags, const void *params) {
    vsync_Present1Fn fn = (vsync_Present1Fn)vsync_saved(chain, VSYNC_PRESENT1);
    if (!fn) return E_FAIL;
    DWORD me = GetCurrentThreadId();
    if (vsync_presenting == me) return fn(chain, interval, flags, params);
    vsync_wait(&interval, &flags);
    vsync_presenting = me;
    HRESULT hr = fn(chain, interval, flags, params);
    vsync_presenting = 0;
    return hr;
}

static void vsync_hookChain(void *object) {
    vsync_init();
    void *chain = vsync_query(object, &vsync_IID_IDXGISwapChain);
    if (chain) { vsync_patch(chain, VSYNC_PRESENT, (void *)vsync_present); vsync_release(chain); }
    void *chain1 = vsync_query(object, &vsync_IID_IDXGISwapChain1);
    if (chain1) {
        vsync_patch(chain1, VSYNC_PRESENT, (void *)vsync_present);
        vsync_patch(chain1, VSYNC_PRESENT1, (void *)vsync_present1);
        vsync_release(chain1);
    }
}

static HRESULT STDMETHODCALLTYPE vsync_create(void *f, void *device, void *desc, void **out) {
    vsync_CreateFn fn = (vsync_CreateFn)vsync_saved(f, VSYNC_CREATE);
    if (!fn) return E_FAIL;
    HRESULT hr = fn(f, device, desc, out);
    if (SUCCEEDED(hr) && out) vsync_hookChain(*out);
    return hr;
}

static HRESULT STDMETHODCALLTYPE vsync_createHwnd(void *f, void *device, HWND window, const void *desc, const void *full,
                                                  void *output, void **out) {
    vsync_CreateHwndFn fn = (vsync_CreateHwndFn)vsync_saved(f, VSYNC_CREATE_HWND);
    if (!fn) return E_FAIL;
    HRESULT hr = fn(f, device, window, desc, full, output, out);
    if (SUCCEEDED(hr) && out) vsync_hookChain(*out);
    return hr;
}

static HRESULT STDMETHODCALLTYPE vsync_createCore(void *f, void *device, void *window, const void *desc, void *output,
                                                  void **out) {
    vsync_CreateCoreFn fn = (vsync_CreateCoreFn)vsync_saved(f, VSYNC_CREATE_CORE);
    if (!fn) return E_FAIL;
    HRESULT hr = fn(f, device, window, desc, output, out);
    if (SUCCEEDED(hr) && out) vsync_hookChain(*out);
    return hr;
}

static HRESULT STDMETHODCALLTYPE vsync_createComposition(void *f, void *device, const void *desc, void *output, void **out) {
    vsync_CreateCompositionFn fn = (vsync_CreateCompositionFn)vsync_saved(f, VSYNC_CREATE_COMPOSITION);
    if (!fn) return E_FAIL;
    HRESULT hr = fn(f, device, desc, output, out);
    if (SUCCEEDED(hr) && out) vsync_hookChain(*out);
    return hr;
}

static void vsync_hookFactory(void *object) {
    vsync_init();
    void *f = vsync_query(object, &vsync_IID_IDXGIFactory);
    if (f) { vsync_patch(f, VSYNC_CREATE, (void *)vsync_create); vsync_release(f); }
    void *f2 = vsync_query(object, &vsync_IID_IDXGIFactory2);
    if (f2) {
        vsync_patch(f2, VSYNC_CREATE, (void *)vsync_create);
        vsync_patch(f2, VSYNC_CREATE_HWND, (void *)vsync_createHwnd);
        vsync_patch(f2, VSYNC_CREATE_CORE, (void *)vsync_createCore);
        vsync_patch(f2, VSYNC_CREATE_COMPOSITION, (void *)vsync_createComposition);
        vsync_release(f2);
    }
}

static int vsync_hookDeviceFactory(void *device) {
    void *dxgiDevice = vsync_query(device, &vsync_IID_IDXGIDevice);
    if (!dxgiDevice) return 0;
    void *adapter = NULL, *factory = NULL;
    if (SUCCEEDED(((vsync_GetAdapterFn)(*(void ***)dxgiDevice)[VSYNC_GET_ADAPTER])(dxgiDevice, &adapter)) && adapter) {
        ((vsync_GetFn)(*(void ***)adapter)[VSYNC_GET_PARENT])(adapter, (REFIID)&vsync_IID_IDXGIFactory, &factory);
        vsync_release(adapter);
    }
    vsync_release(dxgiDevice);
    if (!factory) return 0;
    vsync_hookFactory(factory);
    vsync_release(factory);
    return 1;
}

static void vsync_hookSystemFactory(void) {
    typedef HRESULT (WINAPI *CreateFactoryFn)(REFIID, void **);
    HMODULE dxgi = LoadLibraryW(L"dxgi.dll");
    CreateFactoryFn create = dxgi ? (CreateFactoryFn)GetProcAddress(dxgi, "CreateDXGIFactory1") : NULL;
    void *factory = NULL;
    if (create && SUCCEEDED(create((REFIID)&vsync_IID_IDXGIFactory, &factory)) && factory) {
        vsync_hookFactory(factory);
        vsync_release(factory);
    } else {
        vsync_note("couldn't make a DXGI factory to watch");
    }
}
