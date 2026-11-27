---
title: Black shards or spikes on walls in DirectX 11 games
tags: black shards, spikes, triangles, stretched polygons, fps drop, tessellation, dx11, mach9, dxmt, hbao
---
## Symptoms
With Tessellation detail capping a DirectX 11 game on Mach9, some walls or surfaces show black spikes or shards, and the frame rate drops sharply when you look at them. It happens at every level DXMT accepts (4 to 28 in testing). Without a cap, the same walls vanish instead.

## Why
It's a drawing bug in DXMT, Mach9's DirectX 11 translator: with tessellation capped, some surfaces come out as large stray triangles. The black shards are those triangles, and drawing them is what costs the frame rate.

## Fix in Ferry
No Ferry setting fixes this one. What works:
- Use DirectX 9 (Graphics in the game's settings), if the game also has a DirectX 9 renderer. It has no tessellation, so the shards and vanishing walls both go. You lose the DirectX 10 and 11 extras.
- Some games' own launcher or settings tie other effects to tessellation. In Batman: Arkham City's launcher, HBAO and MVSS go together with tessellation, so turning tessellation off there also turns those off.

## What Ferry can't fix
The shards themselves need a fix in DXMT. DXMT's plan for its 1.0 release includes tessellation work; Mach9 and Mullion pick up DXMT changes through their own engine updates, which Ferry installs from Settings ▸ Engines.

Example: Batman: Arkham City in DirectX 11 on Mach9.
