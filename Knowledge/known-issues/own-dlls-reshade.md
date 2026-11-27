---
title: ReShade, mods or the game's own DLLs and Ferry's fixes
tags: reshade, mods, own dll, d3d11.dll, dxgi.dll, ddraw.dll, dxmt, vsync, overwritten, files next to game
---
## Symptoms
A Ferry fix doesn't seem to apply to a game that has ReShade or a mod installed. Or Ferry says the game "has its own" DLL, so it starts without DXMT (beta).

## Why
Several of Ferry's fixes work by putting small files next to the game's .exe: VSync helpers for D3DMetal and WineD3D, DXMT (beta), the old 2D and 3D game fixes, DirectX 9 via DXVK and Hide ROV support. ReShade and many mods use the same file names, such as d3d11.dll or dxgi.dll.

## Fix in Ferry
- Ferry never overwrites or removes a file the game or a mod brought, or one changed since Ferry put it there. So your own config or ReShade is kept, and Ferry's fix steps aside for that game.
- DXMT (beta) needs all four of its files next to the game. If the game's folder already has one that isn't Ferry's, DXMT stays off for that game, and Ferry says which file. Turn DXMT off in its settings to stop the message.
- VSync helper files are skipped for games with their own dxgi.dll or d3d11.dll; use the game's own VSync setting.
- Ferry's Mods window installs mods and removes them cleanly, putting the original files back.

## What Ferry can't fix
A game can't use ReShade's copy and Ferry's copy of the same file at once. To use Ferry's fix, remove the other file from the game's folder (back it up first).
