---
title: Objects blink or vanish on DirectX 11 games
tags: objects vanish, blink, flicker, disappear, missing walls, invisible floors, tessellation, dx11, mach9, dxmt
---
## Symptoms
In a DirectX 11 game on Mach9, objects, walls, floors or characters blink, disappear, or only show from some angles or spots. The rest of the game draws fine.

## Why
Tessellation is a DirectX 11 feature that adds extra shape detail to objects. Apple's graphics chips refuse a tessellated draw whose result is bigger than 32 KB, and DXMT (Mach9's DirectX 11 translator) then skips that object. The limit is the same on every Apple graphics chip, so a newer Mac doesn't help.

## Fix in Ferry
- Tessellation detail (Graphics ▸ Advanced in the game's settings; Mach9 engine, DirectX 11 games, Mach9 renderer set to Metal) caps how much detail the game gets, so draws fit under the limit.
- Automatic starts at 28. After a run where draws were still refused, it uses 4 less the next time.
- You can pick a level yourself. DXMT only accepts levels from 4 to 64: anything outside that range is ignored, so 4 is the lowest level that has an effect. 64 is the game's own maximum and can make objects vanish.
- Use DirectX 9, for games that also have a DirectX 9 renderer: it has no tessellation, so nothing is refused, but you lose the DirectX 10 and 11 effects.
- Turning tessellation, geometry or detail down or off in the game's own graphics settings also helps.
- Troubleshoot ▸ "Objects, walls or floors flicker or vanish from some angles" offers these in one place.

## What Ferry can't fix
The 32 KB limit is part of the Mac's graphics. Some games show black spikes or shards with the cap on instead of vanishing objects; see the doc on black shards on tessellated walls.

Example: Batman: Arkham City in DirectX 11 on Mach9.
