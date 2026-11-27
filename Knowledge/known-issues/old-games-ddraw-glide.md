---
title: Old games from the 1990s draw wrong, flicker or won't start
tags: old games, 90s, retro, directdraw, ddraw, glide, 3dfx, directx 7, flicker, slow, cnc-ddraw, dgvoodoo
---
## Symptoms
A game from the 1990s or early 2000s is slow, flickers, draws garbage or black, crashes, or won't start.

## Why
Old 2D games drew with DirectDraw, and late-1990s 3D games with 3dfx Glide or DirectX 1 to 7. Wine's own DirectDraw and DirectX 1 to 7 work for many games, but not all. Wine has no Glide of its own, so Glide games need the old 3D game fix.

## Fix in Ferry
- DirectDraw compatibility (cnc-ddraw), for 2D DirectDraw games. Ferry turns it on by itself for 32-bit games that draw only with DirectDraw. Games that also use newer Direct3D or OpenGL often load DirectDraw just to ask about video memory, so Ferry leaves it off for them.
- Old 3D game fix (dgVoodoo2), for Glide games (which need it) and DirectX 1 to 7 games: an optional download in Settings ▸ Components, then a switch in the game's settings. It draws them through DirectX 11. Ferry sets it up without its on-screen watermarks. DirectX 8 and 9 are left to the engine. Experimental under Wine: turn it off if the game gets worse.
- Both are a ddraw.dll placed next to the game, so turning one on turns the other off.
- Older DirectX 8-era games are set to report Windows 7, which they accept more readily than Windows 10. You can change the Windows version in Compatibility settings.
- Troubleshoot offers the old 3D game fix for black screens and crashes in old 32-bit games.

## What Ferry can't fix
These fixes only apply to 32-bit games. 16-bit DOS and Windows 3.x games can't run in Wine at all; DOSBox can run them.
