
#include <windows.h>
#include <stdlib.h>

static LONGLONG vsync_period, vsync_next, vsync_freq;

static void vsync_pace(void) {
    LARGE_INTEGER now, freq;
    QueryPerformanceCounter(&now);
    if (!vsync_period) {
        char hz[8];
        int rate = GetEnvironmentVariableA("FERRY_VSYNC_HZ", hz, sizeof hz) ? atoi(hz) : 0;
        QueryPerformanceFrequency(&freq);
        vsync_freq = freq.QuadPart;
        vsync_period = freq.QuadPart / (rate >= 24 && rate <= 500 ? rate : 60);
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
