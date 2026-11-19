#include <assert.h>
#include <math.h>
#include <stdio.h>
#include "pad-keys.h"

int main(void) {
    assert(!pk_parse(""));
    assert(!pk_parse("zz:k39,a:kZZ,lstick:sideways"));
    assert(pk_parse("a:k39,rt:m1,lt:m2,up:wu,down:wd,b:kE048,lstick:wasd,rstick:mouse,speed:30"));
    assert(pk_bind[0] == PK_KEY + 0x39);
    assert(pk_bind[1] == PK_KEY + 0xE048);
    assert(pk_bind[PAD_RT] == PK_LEFT && pk_bind[PAD_LT] == PK_RIGHT);
    assert(pk_bind[10] == PK_WHEEL_UP && pk_bind[11] == PK_WHEEL_DOWN);
    assert(pk_stick[0] == PK_WASD && pk_stick[1] == PK_MOUSE && pk_speed == 20);
    assert(pk_parse("lstick:arrows") && pk_stick[0] == PK_ARROWS && pk_bind[0] == PK_NONE);

    int held[PK_CONTROLS];
    pk_held(0x1000 | 0x0001, 31, 30, held);
    assert(held[0] && held[10] && held[PAD_LT] && !held[PAD_RT] && !held[1]);

    int dirs[4];
    pk_stick_keys(20000, -20000, dirs);
    assert(!dirs[0] && dirs[1] && !dirs[2] && dirs[3]);
    pk_stick_keys(5000, 5000, dirs);
    assert(!dirs[0] && !dirs[1] && !dirs[2] && !dirs[3]);

    float dx, dy;
    pk_mouse_step(5000, 0, 10, &dx, &dy);
    assert(dx == 0 && dy == 0);
    pk_mouse_step(32767, 0, 10, &dx, &dy);
    assert(fabsf(dx - 15) < 0.1f && fabsf(dy) < 0.01f);
    pk_mouse_step(0, 32767, 10, &dx, &dy);
    assert(fabsf(dy + 15) < 0.1f);
    pk_mouse_step(16000, 0, 10, &dx, &dy);
    assert(dx > 0 && dx < 4);
    puts("pad-keys: all checks passed");
    return 0;
}
