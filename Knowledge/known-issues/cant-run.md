---
title: Anti-cheat and programs that can't run
tags: anti-cheat, easyanticheat, battleye, vanguard, online, multiplayer, kernel, 16-bit, dos, microsoft store, drivers, java, denuvo
---
## Symptoms
An online game won't connect or closes, or the Compatibility Check says something will block it.

## Why
- Kernel-level anti-cheat (for example Easy Anti-Cheat, BattlEye, Riot Vanguard) doesn't run under Wine at all. Online games that require it usually can't be played.
- 16-bit DOS and Windows 3.x programs can't run on modern Wine.
- Microsoft Store packages need the Store and Xbox services, which don't exist outside Windows.
- Windows drivers, and programs that need them, can't run.

## Fix in Ferry
- The Compatibility Check warns about these before you add a game, and Troubleshoot can spot anti-cheat in the log.
- Single-player or offline modes of anti-cheat games may still work.
- 16-bit programs: DOSBox can run them.
- An .exe that wraps a Java program needs Java for Windows inside its environment; or run its .jar with Java for Mac.
- Denuvo copy protection often works under Wine but can be slow to start the first time.
- On some engines (D3DMetal and WineD3D with DirectX 10 to 12), Ferry's VSync and frame rate limit work through helper files next to the game. Ferry leaves those out for games with anti-cheat; use the game's own settings there. Engines' own frame rate limits still apply. Controller remapping isn't used for anti-cheat games either.

## What Ferry can't fix
Anti-cheat, drivers and Store packages are limits of Wine on a Mac. No engine or setting changes them.
