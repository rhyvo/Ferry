---
title: Black screen with sound on DirectX 9 via DXVK
tags: black screen, sound but no picture, menu black, dx9, directx 9, dxvk, moltenvk, models lag, arms lag behind, csmt
---
## Symptoms
A DirectX 9 game with DirectX 9 via DXVK turned on starts, plays sound and reacts to the mouse, but the screen stays black. The log shows shaders that failed to build ("Failed to compile pipeline").

## Why
For 32-bit games, DirectX 9 via DXVK uses DXVK 1.10.3, the newest 32-bit build for macOS, which draws through MoltenVK to Metal. Some of the shaders it makes for DirectX 9 don't build in MoltenVK, so whatever they draw (in one game, the whole menu) never appears. It happened the same way on more than one Wine build.

## Fix in Ferry
- Turn off DirectX 9 via DXVK (Graphics ▸ Advanced in the game's settings). The game goes back to WineD3D.
- Or use Mach9, Auto's choice for DirectX 9 games where it's available: it draws DirectX 9 straight to Metal with mtld3d.
- If parts of models lag a frame behind on WineD3D (arms behind a weapon, a hat behind a head), turn on Single-threaded rendering (Graphics ▸ Advanced in the game's settings). It's slightly slower.

## What Ferry can't fix
The shader problem is in DXVK 1.10.3 and MoltenVK, not in Ferry or the game.

Example: Call of Duty 4: Modern Warfare (DirectX 9, 32-bit).
