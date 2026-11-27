---
title: Launchers run on the game's engine
tags: launcher, launcher works but game doesn't, wrong engine, game won't start from launcher, auto
---
## Symptoms
A game's launcher opens fine, but the game it starts crashes or draws wrong. Or the Compatibility Check shows graphics for the launcher that don't match the game.

## Why
Many games start through a launcher: a small window for settings or news, which then starts the real game. The launcher runs in the same Windows session as its game, so the game runs on the launcher's engine. The launcher itself usually draws a plain 2D window and can use different graphics from its game.

## Fix in Ferry
- Auto picks the engine for the game the launcher starts (its graphics and whether it's 32- or 64-bit), not for the launcher. The Compatibility Check says when it did this.
- For games with several programs, Ferry looks for the real game, and can add single-player and multiplayer as separate entries.
- If the launcher itself is the trouble, add the game's own .exe to Ferry and start it without the launcher.

## What Ferry can't fix
If a launcher and its game need different engines, they can't both get their best one, since they share one session. Starting the game's .exe directly avoids that when the game allows it.
