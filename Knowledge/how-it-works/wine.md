---
title: What Wine is and how Ferry uses it
tags: wine, windows, how it works, translation layer, emulator, compatibility
---
Windows games are made for Windows, not macOS. Wine is a free, open-source program that lets a Windows program run on a Mac by answering its requests to Windows with Mac equivalents, as they happen. It isn't an emulator and doesn't run a copy of Windows: the game's own code runs, and Wine stands in for Windows around it.

Every engine in Ferry is a build of Wine, each with a different way of drawing graphics and running the game's code. Ferry picks one for each game, sets up a Windows environment for it, installs the Windows libraries it needs, and starts it. You don't need to know anything about Wine to use Ferry, but every engine and setting is there if you want to change it.

What Wine can't do:
- Run games with kernel-level anti-cheat (for example, many competitive online shooters). These don't run under Wine at all.
- Run Windows drivers, or programs that need them.
- Run 16-bit DOS or Windows 3.x programs (DOSBox can), or Microsoft Store packages.

Some parts of Windows are only partly done in Wine (for example its DirectMusic and DirectPlay), so Ferry can add Microsoft's own copies of those for games that need them.

Wine is made by volunteers and independent developers. Ferry downloads each engine from its own project's releases.
