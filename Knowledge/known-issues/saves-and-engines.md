---
title: My saves are gone after switching engine
tags: saves, save games, lost saves, progress gone, switching engine, back up saves, before sharing
---
## Symptoms
After switching a game to another engine, its saves seem to be gone, or you find a folder named "(before sharing)".

## Why
Each engine's Wine has its own Windows environment for the game. Ferry points every engine's save folders (AppData and Saved Games) at one shared folder, so switching engine shouldn't hide a save.

## Fix in Ferry
- When Ferry first shares the save folders, anything already in them is merged into the shared folder, and the original is kept beside it as "… (before sharing)". Nothing is deleted. If a save is missing, look in that folder.
- Open Saves Folder and Back Up Saves are in the game's settings (Tools & Saves). Back Up Saves zips them into Documents ▸ Ferry Backups.

## What Ferry can't fix
Some programs keep saves next to their own files, or in their own folder, instead of the Windows save folders. Those stay in the game's folder; back them up from there.
