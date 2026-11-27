---
title: A launcher's window or login page is blank
tags: launcher blank, white window, login page, launcher won't open, webview2, sign in, empty window
---
## Symptoms
A launcher opens but its window, or its login page, stays blank or white.

## Why
Many newer launchers draw their window or login page as a web page, using Microsoft's WebView2 browser engine. Without it, or when it can't start, the page is empty.

## Fix in Ferry
- Install WebView2 once (about 215 MB) from Settings ▸ Components or from Troubleshoot. It's shared between games and apps.
- Turn on WebView2 for launchers in the game's Compatibility settings.
- If the log shows WebView2 failing, Troubleshoot offers this as a one-click fix.
- Electron and NW.js apps are built on a browser engine too; if their window stays blank, add --disable-gpu as a launch argument.

## What Ferry can't fix
WebView2 doesn't work for every launcher under Wine. If it stays blank, look for the launcher's offline mode, or add the game's own .exe to Ferry to start it without the launcher.
