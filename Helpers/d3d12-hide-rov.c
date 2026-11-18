
#define WIN32_LEAN_AND_MEAN
#define COBJMACROS
#define INITGUID
#include <windows.h>
#include <d3d12.h>
#include <stdio.h>

static HMODULE real;
static int hideROV = 1;
static int watchROV = 1;
static int vsync;
static volatile LONG reported;

static void note(const char *text) {
    char flag[8];
    if (!GetEnvironmentVariableA("FERRY_HIDE_ROV_LOG", flag, sizeof flag)) return;
    char path[MAX_PATH];
    DWORD n = GetModuleFileNameA(NULL, path, MAX_PATH);
    while (n > 0 && path[n - 1] != '\\') n--;
    lstrcpyA(path + n, "d3d12-hide-rov.log");
    FILE *f = fopen(path, "a");
    if (f) { fprintf(f, "%s\n", text); fclose(f); }
}

static void vsync_note(const char *text) { note(text); }
#include "dxgi-vsync-hooks.h"

static FARPROC original(const char *name) {
    static char seen[512];
    if (!strstr(seen, name) && strlen(seen) + strlen(name) + 2 < sizeof seen) {
        lstrcatA(seen, name); lstrcatA(seen, ";");
        char line[160]; wsprintfA(line, "game called %s", name); note(line);
    }
    if (!real) {
        WCHAR path[MAX_PATH];
        UINT n = GetSystemDirectoryW(path, MAX_PATH);
        lstrcpyW(path + n, L"\\d3d12.dll");
        real = LoadLibraryW(path);
        note(real ? "loaded the real d3d12.dll from system32" : "could not load the real d3d12.dll");
    }
    return real ? GetProcAddress(real, name) : NULL;
}

static void reportROV(const char *where) {
    if (InterlockedExchange(&reported, 1)) return;
    char line[160]; wsprintfA(line, "the game uses ROV (%s)", where); note(line);
    WCHAR path[1024];
    if (!GetEnvironmentVariableW(L"FERRY_ROV_REPORT", path, 1024)) return;
    HANDLE f = CreateFileW(path, GENERIC_WRITE, 0, NULL, CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, NULL);
    if (f != INVALID_HANDLE_VALUE) { DWORD n; WriteFile(f, "rov\n", 4, &n, NULL); CloseHandle(f); }
}

static int usesROV(const void *code, SIZE_T size) {
    if (!code || size < 32 || size > (64u << 20) || IsBadReadPtr(code, size)) return 0;
    const unsigned char *b = code;
    if (memcmp(b, "DXBC", 4)) return 0;
    UINT chunks = *(const UINT *)(b + 28);
    if (chunks > 64 || 32 + chunks * 4 > size) return 0;
    for (UINT i = 0; i < chunks; i++) {
        UINT at = *(const UINT *)(b + 32 + 4 * i);
        if (at + 8 > size) continue;
        UINT len = *(const UINT *)(b + at + 4);
        if (at + 8 + len > size) continue;
        const unsigned char *data = b + at + 8;
        if (!memcmp(b + at, "SFI0", 4) && len >= 4) {
            unsigned long long flags = len >= 8 ? *(const unsigned long long *)data : *(const UINT *)data;
            if (flags & 0x1000) return 1;
        } else if ((!memcmp(b + at, "SHEX", 4) || !memcmp(b + at, "SHDR", 4)) && len >= 8) {
            const UINT *t = (const UINT *)data, *end = (const UINT *)(data + len);
            t += 2;
            while (t < end) {
                UINT op = *t & 0x7ff, n = (op == 0x35) ? (t + 1 < end ? t[1] : 0) : ((*t >> 24) & 0x7f);
                if (op >= 156 && op <= 158 && (*t & 0x20000)) return 1;
                if (n == 0) break;
                t += n;
            }
        }
    }
    return 0;
}

static void checkShader(const D3D12_SHADER_BYTECODE *ps, const char *where) {
    if (!reported && ps && !IsBadReadPtr(ps, sizeof *ps) && usesROV(ps->pShaderBytecode, ps->BytecodeLength)) reportROV(where);
}

static SIZE_T subobjectSize(UINT type) {
    switch (type) {
    case 0: return 16;
    case 1: case 2: case 3: case 4: case 5: case 6: case 24: case 25: return 24;
    case 7: return 40;  case 8: return 336; case 9: return 8;   case 10: return 48;
    case 11: return 56; case 12: return 24; case 13: return 8;  case 14: return 8;
    case 15: return 40; case 16: return 8;  case 17: return 16; case 18: return 8;
    case 19: return 24; case 20: return 8;  case 21: return 64; case 22: return 32;
    case 26: return 64; case 27: return 48; case 28: return 48;
    default: return 0;
    }
}

static void checkStream(const D3D12_PIPELINE_STATE_STREAM_DESC *desc, const char *where) {
    if (reported || !desc || IsBadReadPtr(desc, sizeof *desc)) return;
    const unsigned char *p = desc->pPipelineStateSubobjectStream, *end = p + desc->SizeInBytes;
    if (!p || desc->SizeInBytes > (1u << 20) || IsBadReadPtr(p, desc->SizeInBytes)) return;
    while (p + 8 <= end) {
        UINT type = *(const UINT *)p;
        SIZE_T size = subobjectSize(type);
        if (!size || p + size > end) break;
        if (type == 2) checkShader((const D3D12_SHADER_BYTECODE *)(p + 8), where);
        p += size;
    }
}

typedef HRESULT (STDMETHODCALLTYPE *QueryInterfaceFn)(void *, REFIID, void **);
typedef ULONG (STDMETHODCALLTYPE *ReleaseFn)(void *);
typedef HRESULT (STDMETHODCALLTYPE *CheckFeatureSupportFn)(void *, D3D12_FEATURE, void *, UINT);
typedef HRESULT (STDMETHODCALLTYPE *CreateGraphicsFn)(void *, const D3D12_GRAPHICS_PIPELINE_STATE_DESC *, REFIID, void **);
typedef HRESULT (STDMETHODCALLTYPE *CreateStreamFn)(void *, const D3D12_PIPELINE_STATE_STREAM_DESC *, REFIID, void **);
typedef HRESULT (STDMETHODCALLTYPE *FactoryCreateDeviceFn)(void *, IUnknown *, D3D_FEATURE_LEVEL, REFIID, void **);

static CRITICAL_SECTION lock;

static long long unlockPage(void *address) {
    unsigned long long page = (unsigned long long)address & ~4095ull;
    long long result = 0x2000000 + 74, length = 4096 * 2, protection = 3;
    unsigned char failed;
    __asm__ volatile("syscall; setc %1"
                     : "+a"(result), "=r"(failed), "+D"(page), "+S"(length), "+d"(protection)
                     : : "rcx", "r11", "memory");
    return failed ? (result ? result : -1) : 0;
}

static void *replace(void **table, int slot, void *hook) {
    void *old = table[slot];
    if (old == hook) return NULL;
    DWORD was;
    if (!VirtualProtect(&table[slot], sizeof(void *), PAGE_READWRITE, &was) && unlockPage(&table[slot])) {
        note("could not unlock D3DMetal's function table");
        return NULL;
    }
    table[slot] = hook;
    return old;
}

#define MAX_TABLES 16
static struct {
    void **table; CheckFeatureSupportFn check; CreateGraphicsFn graphics; CreateStreamFn stream;
} devices[MAX_TABLES];
static int deviceCount;

static int findDevice(void *self) {
    void **table = *(void ***)self;
    for (int i = 0; i < deviceCount; i++) if (devices[i].table == table) return i;
    return -1;
}

static HRESULT STDMETHODCALLTYPE checkFeatureSupport(void *self, D3D12_FEATURE feature, void *data, UINT size) {
    int i = findDevice(self);
    if (i < 0 || !devices[i].check) return E_FAIL;
    HRESULT hr = devices[i].check(self, feature, data, size);
    if (SUCCEEDED(hr) && feature == D3D12_FEATURE_D3D12_OPTIONS && data &&
        size >= sizeof(D3D12_FEATURE_DATA_D3D12_OPTIONS)) {
        D3D12_FEATURE_DATA_D3D12_OPTIONS *options = data;
        if (options->ROVsSupported) {
            options->ROVsSupported = FALSE;
            note("answered the ROV question: not supported");
        }
    }
    return hr;
}

static HRESULT STDMETHODCALLTYPE createGraphics(void *self, const D3D12_GRAPHICS_PIPELINE_STATE_DESC *desc, REFIID riid, void **out) {
    int i = findDevice(self);
    if (i < 0 || !devices[i].graphics) return E_FAIL;
    if (desc && !IsBadReadPtr(desc, sizeof *desc)) checkShader(&desc->PS, "graphics pipeline");
    return devices[i].graphics(self, desc, riid, out);
}

static HRESULT STDMETHODCALLTYPE createStream(void *self, const D3D12_PIPELINE_STATE_STREAM_DESC *desc, REFIID riid, void **out) {
    int i = findDevice(self);
    if (i < 0 || !devices[i].stream) return E_FAIL;
    checkStream(desc, "pipeline stream");
    return devices[i].stream(self, desc, riid, out);
}

static void hookTable(void **table, int newest) {
    for (int i = 0; i < deviceCount; i++) if (devices[i].table == table) return;
    if (deviceCount == MAX_TABLES) return;
    int i = deviceCount;
    devices[i].table = table;
    if (hideROV) {
        devices[i].check = replace(table, 13, (void *)checkFeatureSupport);
    } else if (watchROV) {
        devices[i].graphics = replace(table, 10, (void *)createGraphics);
        if (newest >= 2) devices[i].stream = replace(table, 47, (void *)createStream);
    }
    deviceCount++;
    note(devices[i].check || devices[i].graphics ? "hooked a device function table" : "left a device function table alone");
}

static void hookDevice(void *device) {
    static const IID *ids[] = {&IID_ID3D12Device, &IID_ID3D12Device1, &IID_ID3D12Device2, &IID_ID3D12Device3,
                               &IID_ID3D12Device4, &IID_ID3D12Device5, &IID_ID3D12Device6, &IID_ID3D12Device7,
                               &IID_ID3D12Device8, &IID_ID3D12Device9, &IID_ID3D12Device10};
    EnterCriticalSection(&lock);
    void **table = *(void ***)device;
    int newest = 0;
    for (int n = 0; n < (int)(sizeof ids / sizeof ids[0]); n++) {
        void *other = NULL;
        if (FAILED(((QueryInterfaceFn)table[0])(device, ids[n], &other)) || !other) continue;
        newest = n;
        if (*(void ***)other != table) hookTable(*(void ***)other, n);
        ((ReleaseFn)(*(void ***)other)[2])(other);
    }
    hookTable(table, newest);
    LeaveCriticalSection(&lock);
    static volatile LONG vsyncHooked;
    if (vsync && !InterlockedExchange(&vsyncHooked, 1)) vsync_hookSystemFactory();
}

static void **factoryTable;
static FactoryCreateDeviceFn factoryCreate;

static HRESULT STDMETHODCALLTYPE factoryCreateDevice(void *self, IUnknown *adapter, D3D_FEATURE_LEVEL level, REFIID riid, void **device) {
    if (!factoryCreate) return E_FAIL;
    HRESULT hr = factoryCreate(self, adapter, level, riid, device);
    if (SUCCEEDED(hr) && device && *device) hookDevice(*device);
    return hr;
}

static void hookFactory(void *factory) {
    EnterCriticalSection(&lock);
    void **table = *(void ***)factory;
    if (!factoryTable) {
        FactoryCreateDeviceFn old = replace(table, 9, (void *)factoryCreateDevice);
        if (old) { factoryCreate = old; factoryTable = table; note("hooked the device factory"); }
    }
    LeaveCriticalSection(&lock);
}

__declspec(dllexport) HRESULT WINAPI D3D12CreateDevice(IUnknown *adapter, D3D_FEATURE_LEVEL level, REFIID riid, void **device) {
    typedef HRESULT (WINAPI *Fn)(IUnknown *, D3D_FEATURE_LEVEL, REFIID, void **);
    Fn fn = (Fn)original("D3D12CreateDevice");
    if (!fn) return E_FAIL;
    HRESULT hr = fn(adapter, level, riid, device);
    if (SUCCEEDED(hr) && device && *device) hookDevice(*device);
    return hr;
}

__declspec(dllexport) HRESULT WINAPI D3D12GetDebugInterface(REFIID riid, void **debug) {
    typedef HRESULT (WINAPI *Fn)(REFIID, void **);
    Fn fn = (Fn)original("D3D12GetDebugInterface");
    return fn ? fn(riid, debug) : E_NOINTERFACE;
}

__declspec(dllexport) HRESULT WINAPI D3D12GetInterface(REFCLSID clsid, REFIID riid, void **out) {
    typedef HRESULT (WINAPI *Fn)(REFCLSID, REFIID, void **);
    Fn fn = (Fn)original("D3D12GetInterface");
    if (!fn) return E_NOINTERFACE;
    HRESULT hr = fn(clsid, riid, out);
    if (SUCCEEDED(hr) && out && *out && clsid->Data1 == 0x114863bf) hookFactory(*out);
    return hr;
}

__declspec(dllexport) HRESULT WINAPI D3D12EnableExperimentalFeatures(UINT count, const IID *iids, void *structs, UINT *sizes) {
    typedef HRESULT (WINAPI *Fn)(UINT, const IID *, void *, UINT *);
    Fn fn = (Fn)original("D3D12EnableExperimentalFeatures");
    return fn ? fn(count, iids, structs, sizes) : E_NOINTERFACE;
}

__declspec(dllexport) HRESULT WINAPI D3D12SerializeRootSignature(const D3D12_ROOT_SIGNATURE_DESC *desc, D3D_ROOT_SIGNATURE_VERSION version, ID3DBlob **blob, ID3DBlob **error) {
    typedef HRESULT (WINAPI *Fn)(const D3D12_ROOT_SIGNATURE_DESC *, D3D_ROOT_SIGNATURE_VERSION, ID3DBlob **, ID3DBlob **);
    Fn fn = (Fn)original("D3D12SerializeRootSignature");
    return fn ? fn(desc, version, blob, error) : E_FAIL;
}

__declspec(dllexport) HRESULT WINAPI D3D12SerializeVersionedRootSignature(const D3D12_VERSIONED_ROOT_SIGNATURE_DESC *desc, ID3DBlob **blob, ID3DBlob **error) {
    typedef HRESULT (WINAPI *Fn)(const D3D12_VERSIONED_ROOT_SIGNATURE_DESC *, ID3DBlob **, ID3DBlob **);
    Fn fn = (Fn)original("D3D12SerializeVersionedRootSignature");
    return fn ? fn(desc, blob, error) : E_FAIL;
}

__declspec(dllexport) HRESULT WINAPI D3D12CreateRootSignatureDeserializer(const void *data, SIZE_T size, REFIID riid, void **out) {
    typedef HRESULT (WINAPI *Fn)(const void *, SIZE_T, REFIID, void **);
    Fn fn = (Fn)original("D3D12CreateRootSignatureDeserializer");
    return fn ? fn(data, size, riid, out) : E_FAIL;
}

__declspec(dllexport) HRESULT WINAPI D3D12CreateVersionedRootSignatureDeserializer(const void *data, SIZE_T size, REFIID riid, void **out) {
    typedef HRESULT (WINAPI *Fn)(const void *, SIZE_T, REFIID, void **);
    Fn fn = (Fn)original("D3D12CreateVersionedRootSignatureDeserializer");
    return fn ? fn(data, size, riid, out) : E_FAIL;
}

BOOL WINAPI DllMain(HINSTANCE instance, DWORD reason, LPVOID reserved) {
    (void)instance; (void)reserved;
    if (reason == DLL_PROCESS_ATTACH) {
        InitializeCriticalSection(&lock);
        char mode[16];
        if (GetEnvironmentVariableA("FERRY_ROV_MODE", mode, sizeof mode)) {
            if (!lstrcmpiA(mode, "watch")) hideROV = 0;
            if (!lstrcmpiA(mode, "off")) hideROV = watchROV = 0;
        }
        vsync = vsync_read_settings();
        vsync_init();
    }
    return TRUE;
}
