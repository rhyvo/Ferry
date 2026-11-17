#define COBJMACROS
#define CINTERFACE
#define INITGUID
#include <windows.h>
#include <d3d9.h>
#include <stdio.h>

int main(int argc, char **argv) {
    FILE *out = fopen(argc > 1 ? argv[1] : "bench.txt", "w");
    HWND w = CreateWindowA("STATIC", "bench", WS_OVERLAPPEDWINDOW, 0, 0, 1280, 720, 0, 0, 0, 0);
    ShowWindow(w, SW_SHOW);
    IDirect3D9 *d3d = Direct3DCreate9(D3D_SDK_VERSION);
    D3DPRESENT_PARAMETERS pp = {0};
    pp.Windowed = TRUE; pp.SwapEffect = D3DSWAPEFFECT_DISCARD; pp.BackBufferFormat = D3DFMT_X8R8G8B8;
    pp.BackBufferWidth = 1280; pp.BackBufferHeight = 720; pp.hDeviceWindow = w;
    pp.PresentationInterval = D3DPRESENT_INTERVAL_IMMEDIATE;
    IDirect3DDevice9 *dev = NULL;
    HRESULT hr = IDirect3D9_CreateDevice(d3d, 0, D3DDEVTYPE_HAL, w, D3DCREATE_HARDWARE_VERTEXPROCESSING, &pp, &dev);
    if (FAILED(hr)) { fprintf(out, "CreateDevice %08lx\n", hr); fclose(out); return 1; }
    IDirect3DTexture9 *a, *b;
    IDirect3DDevice9_CreateTexture(dev, 1280, 720, 1, D3DUSAGE_RENDERTARGET, D3DFMT_A8R8G8B8, D3DPOOL_DEFAULT, &a, NULL);
    IDirect3DDevice9_CreateTexture(dev, 1280, 720, 1, D3DUSAGE_RENDERTARGET, D3DFMT_A8R8G8B8, D3DPOOL_DEFAULT, &b, NULL);
    IDirect3DSurface9 *sa, *sb, *back;
    IDirect3DTexture9_GetSurfaceLevel(a, 0, &sa);
    IDirect3DTexture9_GetSurfaceLevel(b, 0, &sb);
    IDirect3DDevice9_GetRenderTarget(dev, 0, &back);
    IDirect3DDevice9_ColorFill(dev, sa, NULL, 0xff336699);
    IDirect3DDevice9_SetFVF(dev, D3DFVF_XYZRHW | D3DFVF_DIFFUSE);
    struct { float x, y, z, rhw; DWORD c; } q[4];
    LARGE_INTEGER f, t0, t1;
    QueryPerformanceFrequency(&f);
    int frames = 300;
    for (int frame = -5; frame < frames; frame++) {
        if (frame == 0) QueryPerformanceCounter(&t0);
        IDirect3DDevice9_SetRenderTarget(dev, 0, sb);
        IDirect3DDevice9_BeginScene(dev);
        for (int y = 0; y < 400; y++) {
            float x0 = (float)(y * 3 % 1200), y0 = (float)y;
            float v[4][2] = {{x0, y0}, {x0 + 40, y0}, {x0, y0 + 40}, {x0 + 40, y0 + 40}};
            for (int i = 0; i < 4; i++) { q[i].x = v[i][0]; q[i].y = v[i][1]; q[i].z = 0; q[i].rhw = 1; q[i].c = 0xffff0000 + y; }
            IDirect3DDevice9_DrawPrimitiveUP(dev, D3DPT_TRIANGLESTRIP, 2, q, sizeof q[0]);
            RECT s = {40 + y % 20, 300 + y, 1240 - y % 20, 301 + y}, t = {0, 300 + y, 1280, 301 + y};
            if (t.bottom > 720) { s.top -= 400; s.bottom -= 400; t.top -= 400; t.bottom -= 400; }
            IDirect3DDevice9_StretchRect(dev, sa, &s, sb, &t, D3DTEXF_LINEAR);
        }
        IDirect3DDevice9_EndScene(dev);
        IDirect3DDevice9_StretchRect(dev, sb, NULL, back, NULL, D3DTEXF_NONE);
        IDirect3DDevice9_SetRenderTarget(dev, 0, back);
        IDirect3DDevice9_Present(dev, NULL, NULL, NULL, NULL);
    }
    QueryPerformanceCounter(&t1);
    double ms = (double)(t1.QuadPart - t0.QuadPart) * 1000.0 / f.QuadPart / frames;
    fprintf(out, "%.1f ms per frame (%.0f fps)\n", ms, 1000.0 / ms);
    fclose(out);
    return 0;
}
