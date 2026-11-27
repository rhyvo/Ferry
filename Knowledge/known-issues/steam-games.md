---
title: The game wants Steam running
tags: steam, steam_api, steamapi_init, must be running, steam game won't start, drm
---
## Symptoms
A game bought on Steam closes at once or says Steam must be running. Troubleshoot may show "The game wants Steam running", or "The game's Steam file is missing".

## Why
Many Steam games check for Steam when they start. Started on their own, outside Steam, they can't find it and quit. The steam_api file the check uses normally comes with the game.

## Fix in Ferry
- Add Steam to Ferry: it installs Steam for Windows in one click.
- Then add the game inside Steam's environment and start it from there, so Steam is running when the game checks. A game added this way uses Steam's Windows environment, so some of its settings are set on Steam's entry.
- If the steam_api file itself is missing, check the whole game folder was copied or extracted.

## What Ferry can't fix
Steam games with anti-cheat still can't play online. See the doc on anti-cheat and programs that can't run.
