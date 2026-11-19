
#include <string.h>

enum { PAD_CONTROLS = 16, PAD_LT = 14, PAD_RT = 15, PAD_NONE = -1 };

static const char *const pad_names[PAD_CONTROLS] = {
    "a", "b", "x", "y", "lb", "rb", "back", "start", "ls", "rs", "up", "down", "left", "right", "lt", "rt",
};
static const unsigned short pad_bits[PAD_LT] = {
    0x1000, 0x2000, 0x4000, 0x8000, 0x0100, 0x0200, 0x0020, 0x0010, 0x0040, 0x0080, 0x0001, 0x0002, 0x0004, 0x0008,
};

static int pad_target[PAD_CONTROLS];

static int pad_index(const char *name, size_t len) {
    for (int i = 0; i < PAD_CONTROLS; i++)
        if (strlen(pad_names[i]) == len && !strncmp(pad_names[i], name, len)) return i;
    return len == 4 && !strncmp(name, "none", 4) ? PAD_NONE : -2;
}

static int pad_parse(const char *map) {
    int changed = 0;
    for (int i = 0; i < PAD_CONTROLS; i++) pad_target[i] = i;
    while (map && *map) {
        const char *end = strchr(map, ','), *colon = strchr(map, ':');
        if (!end) end = map + strlen(map);
        if (colon && colon < end) {
            int from = pad_index(map, (size_t)(colon - map)), to = pad_index(colon + 1, (size_t)(end - colon - 1));
            if (from >= 0 && to >= PAD_NONE && to != from) { pad_target[from] = to; changed = 1; }
        }
        map = *end ? end + 1 : end;
    }
    return changed;
}

static void pad_remap(unsigned short *buttons, unsigned char *lt, unsigned char *rt) {
    unsigned short out = *buttons & 0x0400;
    unsigned char outL = 0, outR = 0;
    for (int i = 0; i < PAD_CONTROLS; i++) {
        int value = i == PAD_LT ? *lt : i == PAD_RT ? *rt : (*buttons & pad_bits[i]) ? 255 : 0;
        int to = pad_target[i];
        if (!value || to == PAD_NONE) continue;
        if (to == PAD_LT) { if (value > outL) outL = (unsigned char)value; }
        else if (to == PAD_RT) { if (value > outR) outR = (unsigned char)value; }
        else if (value > 30) out |= pad_bits[to];
    }
    *buttons = out;
    *lt = outL;
    *rt = outR;
}
