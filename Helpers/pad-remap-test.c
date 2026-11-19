#include <assert.h>
#include <stdio.h>
#include "pad-remap.h"

static void check(const char *map, unsigned short in, unsigned char l, unsigned char r,
                  unsigned short want, unsigned char wantL, unsigned char wantR) {
    pad_parse(map);
    pad_remap(&in, &l, &r);
    if (in != want || l != wantL || r != wantR) {
        printf("map \"%s\": got %04x %d %d, wanted %04x %d %d\n", map, in, l, r, want, wantL, wantR);
        assert(0);
    }
}

int main(void) {
    assert(!pad_parse(""));
    assert(!pad_parse("a:a,junk,zz:b"));
    assert(pad_parse("a:b"));
    check("", 0x1000 | 0x0400, 40, 0, 0x1000 | 0x0400, 40, 0);
    check("a:b,b:a", 0x1000, 0, 0, 0x2000, 0, 0);
    check("a:b,b:a", 0x3000, 0, 0, 0x3000, 0, 0);
    check("a:none", 0x1000 | 0x0001, 0, 0, 0x0001, 0, 0);
    check("lt:a", 0, 200, 0, 0x1000, 0, 0);
    check("lt:a", 0, 20, 0, 0, 0, 0);
    check("a:rt", 0x1000, 0, 0, 0, 0, 255);
    check("lt:rt,rt:lt", 0, 100, 7, 0, 7, 100);
    check("x:a,y:a", 0x4000 | 0x8000, 0, 0, 0x1000, 0, 0);
    puts("pad-remap: all checks passed");
    return 0;
}
