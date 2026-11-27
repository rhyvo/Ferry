---
title: Mac settings that slow games or trap the mouse
tags: low power mode, slow, battery, mouse stuck, window tiling, snap, desktop and dock, game mode, incoming connections, firewall
---
## Symptoms
A game is much slower than usual, the sound crackles, or the mouse gets stuck inside a window after dragging it.

## Why
Some Mac settings affect every app, games included:
- Low Power Mode slows the processor and graphics a lot.
- Window tiling: when you drag a window to a screen edge, the Mac snaps it into place. Windows keeps the mouse inside a window while you drag it, and if the Mac snaps it mid-drag, Wine can miss the button being released.

## Fix in Ferry
- Troubleshoot offers to open Battery settings when Low Power Mode is on, for slow games and crackling sound.
- To free the mouse now: press Esc, or click once. Troubleshoot ▸ "The mouse is stuck inside the window" opens Desktop & Dock settings to turn off window tiling. It affects every app; you can still tile from the green button's menu.
- Exclusive full-screen mode holds the mouse whenever a window covers the screen, which suits games but traps the mouse in apps. Turn it off for apps.
- On D3DMetal, macOS Game Mode gives a game more of the processor and graphics and lowers controller and AirPods latency. Automatic turns it on for games.
- If the Mac asks whether a game may accept incoming connections, click Allow, or other players can't reach it.
- Close other apps while playing, especially on a Mac with 8 GB of memory.

## What Ferry can't fix
Ferry can't change Mac settings itself. It opens the right System Settings page, and you make the change there.
