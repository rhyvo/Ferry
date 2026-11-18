
#include <windows.h>
#include <stdlib.h>

static int vsync_sync;
static int vsync_rate;
static LONGLONG vsync_period, vsync_next, vsync_freq;

static int vsync_read_settings(void) {
    char value[8];
    vsync_sync = GetEnvironmentVariableA("FERRY_VSYNC", value, sizeof value) > 0 && !lstrcmpA(value, "1");
    int rate = GetEnvironmentVariableA("FERRY_FPS", value, sizeof value) > 0 ? atoi(value) : 0;
    vsync_rate = rate >= 10 && rate <= 500 ? rate : 0;
    return vsync_sync || vsync_rate;
}

static void vsync_pace(void) {
    if (!vsync_rate) return;
    LARGE_INTEGER now, freq;
    QueryPerformanceCounter(&now);
    if (!vsync_period) {
        QueryPerformanceFrequency(&freq);
        vsync_freq = freq.QuadPart;
        vsync_period = freq.QuadPart / vsync_rate;
    }
    if (!vsync_next || now.QuadPart - vsync_next > vsync_period) vsync_next = now.QuadPart;
    while (now.QuadPart < vsync_next) {
        LONGLONG left = vsync_next - now.QuadPart;
        LONGLONG ms = left * 1000 / vsync_freq;
        Sleep(ms >= 2 ? (DWORD)(ms - 1) : 1);
        QueryPerformanceCounter(&now);
    }
    vsync_next += vsync_period;
}
