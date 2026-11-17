#define COBJMACROS
#define CINTERFACE
#define INITGUID
#include <windows.h>
#include <d3d9.h>
#include <stdio.h>

int main(int argc, char **argv) {
    FILE *out = fopen(argc > 1 ? argv[1] : "pixels.txt", "w");
    HWND w = CreateWindowA("STATIC", "copytest", WS_OVERLAPPEDWINDOW, 0, 0, 200, 200, 0, 0, 0, 0);
    ShowWindow(w, SW_SHOW);
    IDirect3D9 *d3d = Direct3DCreate9(D3D_SDK_VERSION);
    if (!d3d) { fprintf(out, "no d3d9\n"); fclose(out); return 1; }
    D3DPRESENT_PARAMETERS pp = {0};
    pp.Windowed = TRUE; pp.SwapEffect = D3DSWAPEFFECT_DISCARD; pp.BackBufferFormat = D3DFMT_X8R8G8B8;
    pp.BackBufferWidth = 64; pp.BackBufferHeight = 64; pp.hDeviceWindow = w;
    IDirect3DDevice9 *dev = NULL;
    HRESULT hr = IDirect3D9_CreateDevice(d3d, 0, D3DDEVTYPE_HAL, w, D3DCREATE_HARDWARE_VERTEXPROCESSING, &pp, &dev);
    if (FAILED(hr)) { fprintf(out, "CreateDevice %08lx\n", hr); fclose(out); return 1; }
    IDirect3DTexture9 *a, *b;
    IDirect3DDevice9_CreateTexture(dev, 64, 64, 1, D3DUSAGE_RENDERTARGET, D3DFMT_A8R8G8B8, D3DPOOL_DEFAULT, &a, NULL);
    IDirect3DDevice9_CreateTexture(dev, 64, 64, 1, D3DUSAGE_RENDERTARGET, D3DFMT_A8R8G8B8, D3DPOOL_DEFAULT, &b, NULL);
    IDirect3DSurface9 *sa, *sb;
    IDirect3DTexture9_GetSurfaceLevel(a, 0, &sa);
    IDirect3DTexture9_GetSurfaceLevel(b, 0, &sb);
    for (int y = 0; y < 8; y++)
        for (int x = 0; x < 8; x++) {
            RECT r = {x * 8, y * 8, x * 8 + 8, y * 8 + 8};
            IDirect3DDevice9_ColorFill(dev, sa, &r, D3DCOLOR_ARGB(255, x * 32, y * 32, (x ^ y) * 32));
        }
    IDirect3DDevice9_SetRenderTarget(dev, 0, sb);
    IDirect3DDevice9_SetRenderState(dev, D3DRS_ALPHABLENDENABLE, TRUE);
    D3DVIEWPORT9 vp = {4, 4, 20, 20, 0, 1};
    IDirect3DDevice9_SetViewport(dev, &vp);
    IDirect3DDevice9_Clear(dev, 0, NULL, D3DCLEAR_TARGET, 0xff000000, 1, 0);
    IDirect3DDevice9_BeginScene(dev);
    for (int y = 0; y < 64; y++) {
        RECT s = {8 + y / 8, y, 56 - y / 16, y + 1}, t = {0, y, 64, y + 1};
        hr = IDirect3DDevice9_StretchRect(dev, sa, &s, sb, &t, y < 32 ? D3DTEXF_LINEAR : D3DTEXF_POINT);
        if (FAILED(hr)) fprintf(out, "StretchRect row %d %08lx\n", y, hr);
    }
    IDirect3DDevice9_EndScene(dev);
    DWORD blend = 0; D3DVIEWPORT9 now;
    IDirect3DDevice9_GetRenderState(dev, D3DRS_ALPHABLENDENABLE, &blend);
    IDirect3DDevice9_GetViewport(dev, &now);
    fprintf(out, "state blend=%lu viewport=%lu,%lu,%lu,%lu\n", blend, now.X, now.Y, now.Width, now.Height);
    IDirect3DSurface9 *sys;
    IDirect3DDevice9_CreateOffscreenPlainSurface(dev, 64, 64, D3DFMT_A8R8G8B8, D3DPOOL_SYSTEMMEM, &sys, NULL);
    hr = IDirect3DDevice9_GetRenderTargetData(dev, sb, sys);
    D3DLOCKED_RECT lr;
    if (SUCCEEDED(hr) && SUCCEEDED(IDirect3DSurface9_LockRect(sys, &lr, NULL, D3DLOCK_READONLY))) {
        for (int y = 0; y < 64; y++) {
            DWORD *row = (DWORD *)((BYTE *)lr.pBits + y * lr.Pitch);
            for (int x = 0; x < 64; x++) fprintf(out, "%06lx ", row[x] & 0xffffff);
            fputc('\n', out);
        }
        IDirect3DSurface9_UnlockRect(sys);
    } else fprintf(out, "readback %08lx\n", hr);
    fclose(out);
    return 0;
}
