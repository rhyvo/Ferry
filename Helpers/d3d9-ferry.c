
#define WIN32_LEAN_AND_MEAN
#define COBJMACROS
#define CINTERFACE
#define INITGUID
#include <windows.h>
#include <d3d9.h>
#include <stdarg.h>
#include <stdio.h>
#include "vsync-pace.h"

static HMODULE self, real;
static int logging, enabled = 1, vsync;
static volatile LONG converted, passed;

static void note(const char *format, ...) {
    if (!logging) return;
    char path[MAX_PATH];
    DWORD n = GetModuleFileNameA(self, path, MAX_PATH);
    while (n > 0 && path[n - 1] != '\\') n--;
    lstrcpyA(path + n, "d3d9-ferry.log");
    FILE *f = fopen(path, "a");
    if (!f) return;
    va_list args;
    va_start(args, format);
    vfprintf(f, format, args);
    va_end(args);
    fputc('\n', f);
    fclose(f);
}

static FARPROC original(const char *name) {
    if (!real) {
        WCHAR path[MAX_PATH];
        DWORD n = GetModuleFileNameW(self, path, MAX_PATH);
        while (n > 0 && path[n - 1] != L'\\') n--;
        lstrcpyW(path + n, L"d3d9-dxvk.dll");
        if (GetFileAttributesW(path) != INVALID_FILE_ATTRIBUTES) real = LoadLibraryW(path);
        if (real) note("loaded DXVK's d3d9 (d3d9-dxvk.dll)");
        if (!real && GetEnvironmentVariableW(L"FERRY_D3D9_NEXT", path, MAX_PATH) > 0) {
            real = LoadLibraryW(path);
            note(real ? "loaded the d3d9 FERRY_D3D9_NEXT names" : "could not load the d3d9 FERRY_D3D9_NEXT names");
        }
        if (!real) {
            UINT m = GetSystemDirectoryW(path, MAX_PATH);
            lstrcpyW(path + m, L"\\d3d9.dll");
            real = LoadLibraryW(path);
            note(real ? "loaded the engine's d3d9.dll from system32" : "could not load a real d3d9.dll");
        }
    }
    return real ? GetProcAddress(real, name) : NULL;
}

typedef HRESULT (WINAPI *StretchRectFn)(IDirect3DDevice9 *, IDirect3DSurface9 *, const RECT *, IDirect3DSurface9 *,
                                        const RECT *, D3DTEXTUREFILTERTYPE);
typedef HRESULT (WINAPI *ResetFn)(IDirect3DDevice9 *, D3DPRESENT_PARAMETERS *);
typedef HRESULT (WINAPI *PresentFn)(IDirect3DDevice9 *, const RECT *, const RECT *, HWND, const RGNDATA *);
typedef HRESULT (WINAPI *PresentExFn)(IDirect3DDevice9Ex *, const RECT *, const RECT *, HWND, const RGNDATA *, DWORD);
typedef HRESULT (WINAPI *ResetExFn)(IDirect3DDevice9Ex *, D3DPRESENT_PARAMETERS *, D3DDISPLAYMODEEX *);
typedef HRESULT (WINAPI *CreateDeviceFn)(IDirect3D9 *, UINT, D3DDEVTYPE, HWND, DWORD, D3DPRESENT_PARAMETERS *,
                                         IDirect3DDevice9 **);
typedef HRESULT (WINAPI *CreateDeviceExFn)(IDirect3D9Ex *, UINT, D3DDEVTYPE, HWND, DWORD, D3DPRESENT_PARAMETERS *,
                                           D3DDISPLAYMODEEX *, IDirect3DDevice9Ex **);

#define TABLES 8
static struct {
    void *table; StretchRectFn stretchRect; ResetFn reset; ResetExFn resetEx; PresentFn present; PresentExFn presentEx;
} devices[TABLES];
static struct { void *table; CreateDeviceFn createDevice; CreateDeviceExFn createDeviceEx; } factories[TABLES];

static void patch(void **slot, void *hook, void **saved) {
    if (*slot == hook) return;
    DWORD old;
    if (!VirtualProtect(slot, sizeof *slot, PAGE_EXECUTE_READWRITE, &old)) { note("couldn't patch a function table"); return; }
    *saved = *slot;
    *slot = hook;
    VirtualProtect(slot, sizeof *slot, old, &old);
}

#define FIND(list, object) \
    for (int i = 0; i < TABLES; i++) if (list[i].table == *(void **)(object)) return i; \
    return -1

static int deviceTable(void *device) { FIND(devices, device); }
static int factoryTable(void *factory) { FIND(factories, factory); }

static int newSlot(void *object, int isDevice) {
    for (int i = 0; i < TABLES; i++) {
        void **table = isDevice ? &devices[i].table : &factories[i].table;
        if (!*table) { *table = *(void **)object; return i; }
    }
    return -1;
}

static struct { IDirect3DDevice9 *device; IDirect3DStateBlock9 *saved; IDirect3DVertexDeclaration9 *layout; } kept[4];

static const D3DRENDERSTATETYPE renderStates[] = {
    D3DRS_ZENABLE, D3DRS_ZWRITEENABLE, D3DRS_ALPHATESTENABLE, D3DRS_ALPHABLENDENABLE, D3DRS_CULLMODE,
    D3DRS_STENCILENABLE, D3DRS_SCISSORTESTENABLE, D3DRS_COLORWRITEENABLE, D3DRS_FOGENABLE, D3DRS_SRGBWRITEENABLE,
    D3DRS_CLIPPLANEENABLE, D3DRS_FILLMODE, D3DRS_SPECULARENABLE, D3DRS_DITHERENABLE,
};
static const DWORD renderValues[] = {
    D3DZB_FALSE, FALSE, FALSE, FALSE, D3DCULL_NONE, FALSE, FALSE, 0xF, FALSE, FALSE, 0, D3DFILL_SOLID, FALSE, FALSE,
};
#define COUNT(a) (sizeof(a) / sizeof *(a))

static void setDrawState(IDirect3DDevice9 *d, IDirect3DBaseTexture9 *texture, DWORD filter, const D3DVIEWPORT9 *view,
                         IDirect3DVertexDeclaration9 *layout) {
    for (unsigned i = 0; i < COUNT(renderStates); i++) IDirect3DDevice9_SetRenderState(d, renderStates[i], renderValues[i]);
    IDirect3DDevice9_SetTextureStageState(d, 0, D3DTSS_COLOROP, D3DTOP_SELECTARG1);
    IDirect3DDevice9_SetTextureStageState(d, 0, D3DTSS_COLORARG1, D3DTA_TEXTURE);
    IDirect3DDevice9_SetTextureStageState(d, 0, D3DTSS_ALPHAOP, D3DTOP_SELECTARG1);
    IDirect3DDevice9_SetTextureStageState(d, 0, D3DTSS_ALPHAARG1, D3DTA_TEXTURE);
    IDirect3DDevice9_SetTextureStageState(d, 0, D3DTSS_TEXCOORDINDEX, 0);
    IDirect3DDevice9_SetTextureStageState(d, 0, D3DTSS_TEXTURETRANSFORMFLAGS, D3DTTFF_DISABLE);
    IDirect3DDevice9_SetTextureStageState(d, 1, D3DTSS_COLOROP, D3DTOP_DISABLE);
    IDirect3DDevice9_SetTextureStageState(d, 1, D3DTSS_ALPHAOP, D3DTOP_DISABLE);
    IDirect3DDevice9_SetSamplerState(d, 0, D3DSAMP_MINFILTER, filter);
    IDirect3DDevice9_SetSamplerState(d, 0, D3DSAMP_MAGFILTER, filter);
    IDirect3DDevice9_SetSamplerState(d, 0, D3DSAMP_MIPFILTER, D3DTEXF_NONE);
    IDirect3DDevice9_SetSamplerState(d, 0, D3DSAMP_ADDRESSU, D3DTADDRESS_CLAMP);
    IDirect3DDevice9_SetSamplerState(d, 0, D3DSAMP_ADDRESSV, D3DTADDRESS_CLAMP);
    IDirect3DDevice9_SetSamplerState(d, 0, D3DSAMP_SRGBTEXTURE, FALSE);
    IDirect3DDevice9_SetSamplerState(d, 0, D3DSAMP_MAXMIPLEVEL, 0);
    IDirect3DDevice9_SetSamplerState(d, 0, D3DSAMP_MIPMAPLODBIAS, 0);
    IDirect3DDevice9_SetTexture(d, 0, texture);
    IDirect3DDevice9_SetVertexShader(d, NULL);
    IDirect3DDevice9_SetPixelShader(d, NULL);
    IDirect3DDevice9_SetVertexDeclaration(d, layout);
    IDirect3DDevice9_SetStreamSource(d, 0, NULL, 0, 0);
    IDirect3DDevice9_SetViewport(d, view);
}

static int keptFor(IDirect3DDevice9 *d) {
    int free = -1;
    for (int i = 0; i < 4; i++) {
        if (kept[i].device == d) return i;
        if (!kept[i].device && free < 0) free = i;
    }
    if (free < 0) return -1;
    static const D3DVERTEXELEMENT9 elements[] = {
        {0, 0, D3DDECLTYPE_FLOAT4, D3DDECLMETHOD_DEFAULT, D3DDECLUSAGE_POSITIONT, 0},
        {0, 16, D3DDECLTYPE_FLOAT2, D3DDECLMETHOD_DEFAULT, D3DDECLUSAGE_TEXCOORD, 0},
        D3DDECL_END(),
    };
    if (FAILED(IDirect3DDevice9_CreateVertexDeclaration(d, elements, &kept[free].layout))) return -1;
    kept[free].device = d;
    return free;
}

static IDirect3DStateBlock9 *savedState(IDirect3DDevice9 *d, int k) {
    if (kept[k].saved) return kept[k].saved;
    D3DVIEWPORT9 view = {0, 0, 1, 1, 0, 1};
    if (FAILED(IDirect3DDevice9_BeginStateBlock(d))) return NULL;
    setDrawState(d, NULL, D3DTEXF_POINT, &view, kept[k].layout);
    if (FAILED(IDirect3DDevice9_EndStateBlock(d, &kept[k].saved))) kept[k].saved = NULL;
    return kept[k].saved;
}

static volatile LONG why[10];
#define PASS(n) do { InterlockedIncrement(&why[n]); return E_FAIL; } while (0)
#define PASS_DONE(n) do { InterlockedIncrement(&why[n]); goto done; } while (0)

#define REFUSED ((HRESULT)0xA0F30001)

static int plainColour(D3DFORMAT f) {
    switch (f) {
    case D3DFMT_A8R8G8B8: case D3DFMT_X8R8G8B8: case D3DFMT_A8B8G8R8: case D3DFMT_X8B8G8R8: case D3DFMT_R5G6B5:
    case D3DFMT_X1R5G5B5: case D3DFMT_A1R5G5B5: case D3DFMT_A2R10G10B10: case D3DFMT_A2B10G10R10: return 1;
    default: return 0;
    }
}

static int inside(RECT r, const D3DSURFACE_DESC *d) {
    return r.left >= 0 && r.top >= 0 && r.right <= (LONG)d->Width && r.bottom <= (LONG)d->Height;
}

static void noteKind(const D3DSURFACE_DESC *from, const D3DSURFACE_DESC *to, RECT s, RECT t, DWORD filter, int levels,
                     int depthUnbound, const char *outcome) {
    static struct { UINT sw, sh, dw, dh; D3DFORMAT sf, df; DWORD filter; int one, depth; const char *outcome; } seen[64];
    static int count;
    if (!logging) return;
    int one = s.bottom - s.top == 1;
    for (int i = 0; i < count; i++)
        if (seen[i].sw == from->Width && seen[i].sh == from->Height && seen[i].dw == to->Width && seen[i].dh == to->Height &&
            seen[i].sf == from->Format && seen[i].df == to->Format && seen[i].filter == filter && seen[i].one == one &&
            seen[i].depth == depthUnbound && seen[i].outcome == outcome) return;
    if (count == 64) return;
    seen[count].sw = from->Width; seen[count].sh = from->Height; seen[count].dw = to->Width; seen[count].dh = to->Height;
    seen[count].sf = from->Format; seen[count].df = to->Format; seen[count].filter = filter; seen[count].one = one;
    seen[count].depth = depthUnbound; seen[count].outcome = outcome;
    count++;
    note("kind %d: %s; from %ux%u format %d usage %lx levels %d (%ld,%ld)-(%ld,%ld) -> %ux%u format %d (%ld,%ld)-(%ld,%ld), "
         "filter %lu%s", count, outcome, from->Width, from->Height, from->Format, from->Usage, levels, s.left, s.top, s.right,
         s.bottom, to->Width, to->Height, to->Format, t.left, t.top, t.right, t.bottom, filter,
         depthUnbound ? ", smaller depth buffer set aside" : "");
}

static HRESULT copyAsDraw(IDirect3DDevice9 *d, IDirect3DSurface9 *src, const RECT *srcRect, IDirect3DSurface9 *dst,
                          const RECT *dstRect, D3DTEXTUREFILTERTYPE filter) {
    if (!enabled || !src || !dst || src == dst) PASS(0);

    IDirect3DSurface9 *target = NULL;
    if (FAILED(IDirect3DDevice9_GetRenderTarget(d, 0, &target)) || !target) PASS(2);
    IDirect3DSurface9_Release(target);
    if (target != dst) PASS(2);
    for (DWORD i = 1; i < 4; i++) {
        IDirect3DSurface9 *more = NULL;
        if (SUCCEEDED(IDirect3DDevice9_GetRenderTarget(d, i, &more)) && more) {
            IDirect3DSurface9_Release(more);
            PASS(3);
        }
    }

    IDirect3DTexture9 *texture = NULL;
    if (FAILED(IDirect3DSurface9_GetContainer(src, &IID_IDirect3DTexture9, (void **)&texture)) || !texture) PASS(4);
    HRESULT hr = E_FAIL;
    IDirect3DSurface9 *top = NULL;
    D3DSURFACE_DESC from, to;
    if (FAILED(IDirect3DTexture9_GetSurfaceLevel(texture, 0, &top))) PASS_DONE(5);
    IDirect3DSurface9_Release(top);
    if (top != src || FAILED(IDirect3DSurface9_GetDesc(src, &from)) || FAILED(IDirect3DSurface9_GetDesc(dst, &to))) PASS_DONE(5);
    if (from.MultiSampleType != D3DMULTISAMPLE_NONE) PASS_DONE(6);

    RECT s = srcRect ? *srcRect : (RECT){0, 0, (LONG)from.Width, (LONG)from.Height};
    RECT t = dstRect ? *dstRect : (RECT){0, 0, (LONG)to.Width, (LONG)to.Height};
    int levels = (int)IDirect3DTexture9_GetLevelCount(texture);
    if (!plainColour(from.Format) || !plainColour(to.Format)) {
        noteKind(&from, &to, s, t, filter, levels, 0, "passed on: format");
        PASS_DONE(1);
    }
    if (s.right <= s.left || s.bottom <= s.top || t.right <= t.left || t.bottom <= t.top || !inside(s, &from) || !inside(t, &to)) {
        noteKind(&from, &to, s, t, filter, levels, 0, "refused: rectangle outside the picture");
        InterlockedIncrement(&why[7]);
        hr = REFUSED;
        goto done;
    }

    int k = keptFor(d);
    IDirect3DStateBlock9 *saved = k < 0 ? NULL : savedState(d, k);
    if (!saved) PASS_DONE(8);

    IDirect3DSurface9 *depth = NULL;
    int unbind = 0;
    if (SUCCEEDED(IDirect3DDevice9_GetDepthStencilSurface(d, &depth)) && depth) {
        D3DSURFACE_DESC dd;
        unbind = SUCCEEDED(IDirect3DSurface9_GetDesc(depth, &dd)) && (t.right > (LONG)dd.Width || t.bottom > (LONG)dd.Height);
    }
    noteKind(&from, &to, s, t, filter, levels, unbind, "drawn");

    float w = (float)from.Width, h = (float)from.Height;
    float x0 = t.left - 0.5f, x1 = t.right - 0.5f, y0 = t.top - 0.5f, y1 = t.bottom - 0.5f;
    float u0 = s.left / w, u1 = s.right / w, v0 = s.top / h, v1 = s.bottom / h;
    const float quad[4][6] = {
        {x0, y0, 0, 1, u0, v0}, {x1, y0, 0, 1, u1, v0}, {x0, y1, 0, 1, u0, v1}, {x1, y1, 0, 1, u1, v1},
    };
    D3DVIEWPORT9 view = {0, 0, to.Width, to.Height, 0, 1};

    IDirect3DStateBlock9_Capture(saved);
    setDrawState(d, (IDirect3DBaseTexture9 *)texture, filter <= D3DTEXF_POINT ? D3DTEXF_POINT : D3DTEXF_LINEAR, &view,
                 kept[k].layout);
    if (unbind) IDirect3DDevice9_SetDepthStencilSurface(d, NULL);
    hr = IDirect3DDevice9_DrawPrimitiveUP(d, D3DPT_TRIANGLESTRIP, 2, quad, sizeof quad[0]);
    if (unbind) IDirect3DDevice9_SetDepthStencilSurface(d, depth);
    if (depth) IDirect3DSurface9_Release(depth);
    IDirect3DStateBlock9_Apply(saved);
    if (FAILED(hr)) InterlockedIncrement(&why[9]);
done:
    IDirect3DTexture9_Release(texture);
    return hr;
}

static HRESULT WINAPI hookStretchRect(IDirect3DDevice9 *d, IDirect3DSurface9 *src, const RECT *srcRect,
                                      IDirect3DSurface9 *dst, const RECT *dstRect, D3DTEXTUREFILTERTYPE filter) {
    int i = deviceTable(d);
    if (i < 0) return D3DERR_INVALIDCALL;
    HRESULT hr = copyAsDraw(d, src, srcRect, dst, dstRect, filter);
    if (SUCCEEDED(hr)) {
        LONG n = InterlockedIncrement(&converted);
        if (n == 1 || n % 20000 == 0) note("drew %ld copies, passed %ld on, refused %ld", n, passed, why[7]);
        return D3D_OK;
    }
    if (hr == REFUSED) return D3DERR_INVALIDCALL;
    LONG n = InterlockedIncrement(&passed);
    if (n <= 5 || n % 20000 == 0) {
        note("passed %ld on (drew %ld); why: off %ld, format %ld, not the picture %ld, several %ld, not a texture %ld, "
             "not top level %ld, multisampled %ld, refused %ld, no state %ld, draw failed %ld", n, converted, why[0], why[1],
             why[2], why[3], why[4], why[5], why[6], why[7], why[8], why[9]);
        if (n <= 5) note("  copy %dx%d -> %dx%d, filter %d", srcRect ? (int)(srcRect->right - srcRect->left) : -1,
                         srcRect ? (int)(srcRect->bottom - srcRect->top) : -1, dstRect ? (int)(dstRect->right - dstRect->left) : -1,
                         dstRect ? (int)(dstRect->bottom - dstRect->top) : -1, (int)filter);
    }
    return devices[i].stretchRect(d, src, srcRect, dst, dstRect, filter);
}

static void forget(IDirect3DDevice9 *d) {
    for (int k = 0; k < 4; k++) {
        if (kept[k].device == d && kept[k].saved) {
            IDirect3DStateBlock9_Release(kept[k].saved);
            kept[k].saved = NULL;
        }
    }
}

static void syncToDisplay(D3DPRESENT_PARAMETERS *params) {
    if (!vsync || !params || params->PresentationInterval != D3DPRESENT_INTERVAL_IMMEDIATE) return;
    params->PresentationInterval = D3DPRESENT_INTERVAL_ONE;
    note("the game presents without VSync; turning it on");
}

static HRESULT WINAPI hookPresent(IDirect3DDevice9 *d, const RECT *from, const RECT *to, HWND window, const RGNDATA *dirty) {
    int i = deviceTable(d);
    if (i < 0) return D3DERR_INVALIDCALL;
    vsync_pace();
    return devices[i].present(d, from, to, window, dirty);
}

static HRESULT WINAPI hookPresentEx(IDirect3DDevice9Ex *d, const RECT *from, const RECT *to, HWND window,
                                    const RGNDATA *dirty, DWORD flags) {
    int i = deviceTable(d);
    if (i < 0) return D3DERR_INVALIDCALL;
    if (!(flags & D3DPRESENT_DONOTWAIT)) vsync_pace();
    return devices[i].presentEx(d, from, to, window, dirty, flags);
}

static HRESULT WINAPI hookReset(IDirect3DDevice9 *d, D3DPRESENT_PARAMETERS *params) {
    int i = deviceTable(d);
    if (i < 0) return D3DERR_INVALIDCALL;
    forget(d);
    syncToDisplay(params);
    return devices[i].reset(d, params);
}

static HRESULT WINAPI hookResetEx(IDirect3DDevice9Ex *d, D3DPRESENT_PARAMETERS *params, D3DDISPLAYMODEEX *mode) {
    int i = deviceTable(d);
    if (i < 0) return D3DERR_INVALIDCALL;
    forget((IDirect3DDevice9 *)d);
    syncToDisplay(params);
    return devices[i].resetEx(d, params, mode);
}

static void hookDevice(IDirect3DDevice9 *d) {
    if (deviceTable(d) >= 0) return;
    int i = newSlot(d, 1);
    if (i < 0) return;
    if (enabled) patch((void **)&d->lpVtbl->StretchRect, hookStretchRect, (void **)&devices[i].stretchRect);
    patch((void **)&d->lpVtbl->Reset, hookReset, (void **)&devices[i].reset);
    if (vsync) patch((void **)&d->lpVtbl->Present, hookPresent, (void **)&devices[i].present);
    IDirect3DDevice9Ex *ex = NULL;
    if (SUCCEEDED(IDirect3DDevice9_QueryInterface(d, &IID_IDirect3DDevice9Ex, (void **)&ex)) && ex) {
        patch((void **)&ex->lpVtbl->ResetEx, hookResetEx, (void **)&devices[i].resetEx);
        if (vsync) patch((void **)&ex->lpVtbl->PresentEx, hookPresentEx, (void **)&devices[i].presentEx);
        IDirect3DDevice9Ex_Release(ex);
    }
    note(enabled ? "watching the game's DirectX 9 device for copies" : "watching the game's DirectX 9 device");
}

static HRESULT WINAPI hookCreateDevice(IDirect3D9 *f, UINT adapter, D3DDEVTYPE type, HWND window, DWORD flags,
                                       D3DPRESENT_PARAMETERS *params, IDirect3DDevice9 **out) {
    int i = factoryTable(f);
    if (i < 0) return D3DERR_INVALIDCALL;
    syncToDisplay(params);
    HRESULT hr = factories[i].createDevice(f, adapter, type, window, flags, params, out);
    if (SUCCEEDED(hr) && out && *out) hookDevice(*out);
    return hr;
}

static HRESULT WINAPI hookCreateDeviceEx(IDirect3D9Ex *f, UINT adapter, D3DDEVTYPE type, HWND window, DWORD flags,
                                         D3DPRESENT_PARAMETERS *params, D3DDISPLAYMODEEX *mode, IDirect3DDevice9Ex **out) {
    int i = factoryTable(f);
    if (i < 0) return D3DERR_INVALIDCALL;
    syncToDisplay(params);
    HRESULT hr = factories[i].createDeviceEx(f, adapter, type, window, flags, params, mode, out);
    if (SUCCEEDED(hr) && out && *out) hookDevice((IDirect3DDevice9 *)*out);
    return hr;
}

static void hookFactory(IDirect3D9 *f, int isEx) {
    if (!f || !(enabled || vsync)) return;
    int i = factoryTable(f);
    if (i < 0 && (i = newSlot(f, 0)) < 0) return;
    patch((void **)&f->lpVtbl->CreateDevice, hookCreateDevice, (void **)&factories[i].createDevice);
    note("watching for the game's DirectX 9 device");
    if (isEx) patch((void **)&((IDirect3D9Ex *)f)->lpVtbl->CreateDeviceEx, hookCreateDeviceEx,
                    (void **)&factories[i].createDeviceEx);
}

IDirect3D9 *WINAPI ferry_Direct3DCreate9(UINT sdk) {
    typedef IDirect3D9 *(WINAPI *Fn)(UINT);
    Fn fn = (Fn)original("Direct3DCreate9");
    IDirect3D9 *f = fn ? fn(sdk) : NULL;
    hookFactory(f, 0);
    return f;
}

HRESULT WINAPI ferry_Direct3DCreate9Ex(UINT sdk, IDirect3D9Ex **out) {
    typedef HRESULT (WINAPI *Fn)(UINT, IDirect3D9Ex **);
    Fn fn = (Fn)original("Direct3DCreate9Ex");
    HRESULT hr = fn ? fn(sdk, out) : D3DERR_NOTAVAILABLE;
    if (SUCCEEDED(hr) && out) hookFactory((IDirect3D9 *)*out, 1);
    return hr;
}

int WINAPI ferry_D3DPERF_BeginEvent(D3DCOLOR color, LPCWSTR name) {
    typedef int (WINAPI *Fn)(D3DCOLOR, LPCWSTR);
    Fn fn = (Fn)original("D3DPERF_BeginEvent");
    return fn ? fn(color, name) : 0;
}

int WINAPI ferry_D3DPERF_EndEvent(void) {
    typedef int (WINAPI *Fn)(void);
    Fn fn = (Fn)original("D3DPERF_EndEvent");
    return fn ? fn() : 0;
}

void WINAPI ferry_D3DPERF_SetMarker(D3DCOLOR color, LPCWSTR name) {
    typedef void (WINAPI *Fn)(D3DCOLOR, LPCWSTR);
    Fn fn = (Fn)original("D3DPERF_SetMarker");
    if (fn) fn(color, name);
}

void WINAPI ferry_D3DPERF_SetRegion(D3DCOLOR color, LPCWSTR name) {
    typedef void (WINAPI *Fn)(D3DCOLOR, LPCWSTR);
    Fn fn = (Fn)original("D3DPERF_SetRegion");
    if (fn) fn(color, name);
}

BOOL WINAPI ferry_D3DPERF_QueryRepeatFrame(void) {
    typedef BOOL (WINAPI *Fn)(void);
    Fn fn = (Fn)original("D3DPERF_QueryRepeatFrame");
    return fn ? fn() : FALSE;
}

void WINAPI ferry_D3DPERF_SetOptions(DWORD options) {
    typedef void (WINAPI *Fn)(DWORD);
    Fn fn = (Fn)original("D3DPERF_SetOptions");
    if (fn) fn(options);
}

DWORD WINAPI ferry_D3DPERF_GetStatus(void) {
    typedef DWORD (WINAPI *Fn)(void);
    Fn fn = (Fn)original("D3DPERF_GetStatus");
    return fn ? fn() : 0;
}

void *WINAPI ferry_Direct3DShaderValidatorCreate9(void) {
    typedef void *(WINAPI *Fn)(void);
    Fn fn = (Fn)original("Direct3DShaderValidatorCreate9");
    return fn ? fn() : NULL;
}

void WINAPI ferry_DebugSetMute(void) {
    typedef void (WINAPI *Fn)(void);
    Fn fn = (Fn)original("DebugSetMute");
    if (fn) fn();
}

BOOL WINAPI DllMain(HINSTANCE instance, DWORD reason, LPVOID reserved) {
    (void)reserved;
    if (reason == DLL_PROCESS_ATTACH) {
        self = instance;
        char value[16];
        logging = GetEnvironmentVariableA("FERRY_D3D9_LOG", value, sizeof value) > 0;
        if (GetEnvironmentVariableA("FERRY_D3D9_COPIES", value, sizeof value) > 0 && !lstrcmpiA(value, "off")) enabled = 0;
        vsync = GetEnvironmentVariableA("FERRY_VSYNC", value, sizeof value) > 0 && !lstrcmpA(value, "1");
        DisableThreadLibraryCalls(instance);
    } else if (reason == DLL_PROCESS_DETACH && (converted || passed)) {
        note("finished: drew %ld copies, passed %ld on", converted, passed);
    }
    return TRUE;
}
