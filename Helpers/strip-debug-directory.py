#!/usr/bin/env python3
"""Removes the debug directory from a Windows .exe or .dll built with zig cc.

zig's linker adds an empty "reproducible build" debug entry (type 16, no data). Windows ignores it, but
Wine's dbghelp reads it as CodeView debug information and crashes, and some games call dbghelp on every
loaded module (the Gears of War 2 recomp crashed this way with Ferry's d3d12 helper loaded).

Usage: python3 Helpers/strip-debug-directory.py Resources/d3d12-hide-rov.dll Resources/ferry-winbuttons.exe
"""
import struct
import sys

for path in sys.argv[1:]:
    data = bytearray(open(path, "rb").read())
    pe = struct.unpack_from("<I", data, 0x3C)[0]
    assert data[pe:pe + 4] == b"PE\0\0", f"{path} is not a Windows program"
    optional = pe + 24
    is64 = struct.unpack_from("<H", data, optional)[0] == 0x20B
    debug_entry = optional + (112 if is64 else 96) + 6 * 8
    rva, size = struct.unpack_from("<II", data, debug_entry)
    if rva or size:
        struct.pack_into("<II", data, debug_entry, 0, 0)
        open(path, "wb").write(data)
        print(f"{path}: removed the debug directory")
    else:
        print(f"{path}: no debug directory")
