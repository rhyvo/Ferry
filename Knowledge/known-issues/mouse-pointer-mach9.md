---
title: The Mac's mouse pointer shows while playing
tags: mouse pointer, cursor visible, cursor stuck in middle, pointer shows, mouse, full screen, mach9, exclusive full screen
---
## Symptoms
In a full-screen game, the Mac's mouse pointer stays drawn in the middle of the picture while the game should hide it, for example while aiming. Moving the mouse moves it briefly before it jumps back. The game's mouse control itself still works.

## Why
Mach9 normally shows full-screen games at a scaled, virtual resolution, so the Mac's display doesn't switch modes. In that mode, Mach9 keeps the mouse inside the game, but can leave the Mac's pointer on screen when the game hides it. This was seen in Mach9 0.4.0.

## Fix in Ferry
- Exclusive full-screen mode, in the game's Compatibility settings. The game switches the display's real resolution while it runs, and hides the pointer properly. The screen switches resolution when the game starts and quits.
- Troubleshoot ▸ "The Mac's mouse pointer shows while I play" turns it on in one click for Mach9 games.
- On other engines, or if it still shows: click once inside the game's window so it's the active app. macOS only lets the app in front hide the pointer. If the game's own menus use the mouse, the pointer comes back while they're open. Switching engine is another option.

## What Ferry can't fix
The pointer in Mach9's scaled full screen needs a fix in Mach9 itself. Until then, the scaled mode and the hidden pointer don't go together.

Example: Call of Duty: Modern Warfare 2 (2009) on Mach9.
