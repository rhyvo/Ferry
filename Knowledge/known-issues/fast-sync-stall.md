---
title: Textures stay blurry, loading hangs or sounds go missing
tags: blurry textures, low detail, grey textures, loading screen stuck, hangs, missing sounds, fast sync, msync, stall
---
## Symptoms
Textures stay blurry, grey or low-detail and never sharpen. A loading screen hangs. Some sounds go missing. Troubleshoot may show "Part of it was stuck waiting for over a minute".

## Why
Ferry's Fast Sync (MSync) handles how a game's parts take turns, and is faster than Wine's usual way. But with it on, a busy part of a game can keep a shared lock to itself, so a waiting part never gets its turn. If that part loads sharp textures or sounds, they never arrive. Wine writes a line in the log for each minute a part waits.

## Fix in Ferry
- After a run where the log shows that wait, Ferry offers once, when you quit, to turn off Fast Sync for that game. Troubleshoot keeps offering it after that.
- Or turn off Fast synchronization (MSync) yourself in the game's Compatibility settings. Turning it off can cost a little speed, and Mach9 is built around it, so turn it back on if it doesn't help.
- Blurry textures can also mean the game thinks it has too little video memory. For DirectX 9 via DXVK, Troubleshoot can tell it there's 2 GB. Check the game's own texture setting too: changing its DirectX version or graphics card can reset it to low.

## What Ferry can't fix
If the log shows a crash, waits in the log come from the crash, not from Fast Sync, and turning Fast Sync off won't help.
