
#include <stdlib.h>
#include "pad-remap.h"

enum { PK_CONTROLS = PAD_CONTROLS };
enum { PK_NONE = 0, PK_LEFT, PK_RIGHT, PK_MIDDLE, PK_WHEEL_UP, PK_WHEEL_DOWN, PK_KEY = 0x10000 };
enum { PK_OFF = 0, PK_WASD, PK_ARROWS, PK_MOUSE };

static int pk_bind[PK_CONTROLS];
static int pk_stick[2];
static int pk_speed = 8;

static const int pk_wasd_codes[4] = { 0x11, 0x1F, 0x1E, 0x20 };
static const int pk_arrow_codes[4] = { 0xE048, 0xE050, 0xE04B, 0xE04D };

static int pk_value(const char *v, size_t len) {
    if (len >= 2 && v[0] == 'k') {
        char hex[8] = {0};
        if (len - 1 >= sizeof hex) return PK_NONE;
        memcpy(hex, v + 1, len - 1);
        char *end;
        long code = strtol(hex, &end, 16);
        return *end || code <= 0 || code > 0xE0FF ? PK_NONE : PK_KEY + (int)code;
    }
    const char *names[] = { "m1", "m2", "m3", "wu", "wd" };
    for (int i = 0; i < 5; i++) if (len == 2 && !strncmp(v, names[i], 2)) return PK_LEFT + i;
    return PK_NONE;
}

static int pk_mode(const char *v, size_t len) {
    if (len == 4 && !strncmp(v, "wasd", 4)) return PK_WASD;
    if (len == 6 && !strncmp(v, "arrows", 6)) return PK_ARROWS;
    if (len == 5 && !strncmp(v, "mouse", 5)) return PK_MOUSE;
    return PK_OFF;
}

static int pk_parse(const char *text) {
    memset(pk_bind, 0, sizeof pk_bind);
    pk_stick[0] = pk_stick[1] = PK_OFF;
    pk_speed = 8;
    while (text && *text) {
        const char *end = strchr(text, ','), *colon = strchr(text, ':');
        if (!end) end = text + strlen(text);
        if (colon && colon < end) {
            size_t klen = (size_t)(colon - text), vlen = (size_t)(end - colon - 1);
            const char *v = colon + 1;
            if (klen == 6 && !strncmp(text, "lstick", 6)) pk_stick[0] = pk_mode(v, vlen);
            else if (klen == 6 && !strncmp(text, "rstick", 6)) pk_stick[1] = pk_mode(v, vlen);
            else if (klen == 5 && !strncmp(text, "speed", 5)) {
                int s = atoi(v);
                pk_speed = s < 1 ? 1 : s > 20 ? 20 : s;
            } else {
                int i = pad_index(text, klen);
                if (i >= 0) pk_bind[i] = pk_value(v, vlen);
            }
        }
        text = *end ? end + 1 : end;
    }
    int any = pk_stick[0] || pk_stick[1];
    for (int i = 0; i < PK_CONTROLS; i++) any |= pk_bind[i] != PK_NONE;
    return any;
}

static void pk_held(unsigned short buttons, unsigned char lt, unsigned char rt, int held[PK_CONTROLS]) {
    for (int i = 0; i < PAD_LT; i++) held[i] = (buttons & pad_bits[i]) != 0;
    held[PAD_LT] = lt > 30;
    held[PAD_RT] = rt > 30;
}

static void pk_stick_keys(int x, int y, int dirs[4]) {
    const int edge = 12000;
    dirs[0] = y > edge;
    dirs[1] = y < -edge;
    dirs[2] = x < -edge;
    dirs[3] = x > edge;
}

static void pk_mouse_step(int x, int y, int speed, float *dx, float *dy) {
    const float dead = 8689, full = 32767;
    float mx = (float)x, my = (float)y;
    float mag = mx * mx + my * my;
    *dx = *dy = 0;
    if (mag <= dead * dead) return;
    float len = 0;
    for (float g = full; g > 0.5f; g /= 2) while ((len + g) * (len + g) <= mag) len += g;
    float t = (len - dead) / (full - dead);
    if (t > 1) t = 1;
    float step = t * t * 1.5f * (float)speed;
    *dx = mx / len * step;
    *dy = -my / len * step;
}
