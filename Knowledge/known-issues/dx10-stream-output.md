---
title: DirectX 10 or 11 games crash at the same spot
tags: crash, crashes, closes, dx10, dx11, stream output, directx 9, dx9, mach9, dxmt, d3d11, d3d10
---
## Symptoms
A DirectX 10 or 11 game runs, then crashes at the same place every time. The log may say it crashed inside d3d10, d3d11 or dxgi, and Troubleshoot can show "It crashed inside DirectX 10/11".

## Why
The crash happens in the engine's translation of DirectX 10 or 11, not in the game. One known cause: DirectX 10 has a feature called stream output that Metal doesn't have, and DXMT (used by Mach9 for DirectX 10 and 11) doesn't provide it either. Some DirectX 10 games crash where they use it.

## Fix in Ferry
- Use DirectX 9 (Graphics in the game's settings). Many DirectX 10 and 11 games from around 2006 to 2010 also have a DirectX 9 renderer but no in-game switch for it. Ferry hides DirectX 10 and 11 from the game and starts it with -dx9. If the game has its own DirectX 9 option, that works too. Turn it off again if the game won't start: not every game still has a DirectX 9 renderer.
- DirectX 10/11 via DXMT (beta), from Troubleshoot: the newest official DXMT on Wine Staging, which can work where an engine's own DXMT crashes. It runs through Rosetta. Experimental, and it doesn't fix every crash.
- Switch engine.

## What Ferry can't fix
Stream output can't be added from Ferry's side. With Use DirectX 9 you lose the DirectX 10 and 11 effects.

Example: BioShock's DirectX 10 mode crashes at the first fire fight on Mach9; its DirectX 9 mode avoids the crash.
