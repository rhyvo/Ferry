---
title: No music, or old multiplayer doesn't work
tags: no music, silent music, missing sound, crash when music starts, multiplayer, lan, online, directmusic, directplay, old games
---
## Symptoms
A game from around 1998 to 2005 has no music, or crashes when music starts. Or its LAN or online multiplayer menu fails, crashes or finds no games.

## Why
Many games of that time play music with Microsoft's DirectMusic and run multiplayer with DirectPlay. Wine's versions of both are incomplete.

## Fix in Ferry
- Install DirectMusic and DirectPlay in Settings ▸ Components (Microsoft's own files, from its DirectX package; about 105 MB to download, and only the few files needed are kept).
- Then turn on Microsoft's DirectMusic or Microsoft's DirectPlay in the game's Compatibility settings. Troubleshoot offers them under missing music and multiplayer.
- If things get worse, turn it off again: the game goes back to Wine's own version.
- For multiplayer, if the Mac asks whether to allow incoming connections, click Allow, or other players can't reach your game.
- Also check the game's own sound settings: some games turn music off, or pick a sound device that isn't there, after their first start.

## What Ferry can't fix
Both are for 32-bit games only. Online games that need anti-cheat don't run under Wine at all.
