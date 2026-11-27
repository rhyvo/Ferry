---
title: The game crashes or closes right after starting
tags: crashes, closes immediately, won't start, doesn't open, black screen, try another engine, engine, graphics couldn't start
---
## Symptoms
The game closes within seconds of starting, or shows a black screen and quits.

## Why
Each engine translates Windows and its graphics in a different way, so one engine may fail where another works. The log usually says which: a missing file, graphics that couldn't start, or a crash.

## Fix in Ferry
- When a game closes right after starting, Ferry shows why and offers the next engine to try. Whichever works becomes that game's setting. If you closed it yourself, ignore the message.
- Troubleshoot (right-click the game) reads the log. "This engine's graphics couldn't start" and "It crashed" both offer another engine. A missing library offers to install it.
- For a DirectX 10 or 11 game, Use DirectX 9 avoids the newer graphics translation if the game has a DirectX 9 renderer.
- Show Log, in the game's settings: the last lines usually say what went wrong.
- Unreal Engine and Unity DirectX 12 games that crash on start: add the launch argument -dx11 (Unreal) or -force-d3d11 (Unity) so they use DirectX 11.

## What Ferry can't fix
A program that shares another entry's environment, such as a game inside Steam's, can't switch engine on its own; change the engine on the entry that owns the environment. Some games don't run on any engine; anti-cheat is the most common reason.
