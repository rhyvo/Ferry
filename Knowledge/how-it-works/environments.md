---
title: Windows environments, saves and shared programs
tags: environment, bottle, prefix, c drive, saves, storage, shared environment, steam
---
A Windows environment is a folder that looks like a small Windows install to the game: its own C: drive, Windows settings and installed libraries. Other apps call it a bottle or prefix. Ferry makes and manages them for you; you never have to create one.

How Ferry arranges them:
- Each game gets its own. Each engine's Wine also gets its own environment for that game, so switching engines can't damage one.
- Saves are shared between engines. Ferry points every engine's save folders for the game at one shared folder, so switching between engines never hides a save. If a save folder already had files, they're merged in and the old folder is kept beside it, named "(before sharing)". Nothing is deleted.
- Some programs share another entry's environment, such as a game added inside Steam's environment. Their Windows settings (Windows version, Retina, ⌘ as Ctrl and others) are set on the entry that owns the environment, and their engine can't be switched on its own.
- Windows libraries (Visual C++, DirectX, .NET, XNA, PhysX, OpenAL, video codecs) are downloaded once and reused for every game.

Where things are: Ferry's engines and environments are in ~/Library/Application Support/Ferry. Games themselves run from wherever you keep them.

Useful buttons in a game's settings (Tools & Saves):
- Open C: Drive: the game's Windows environment in Finder.
- Back Up Saves: zips the game's saves into Documents ▸ Ferry Backups. Some programs keep saves next to their own files instead; back those up from the game's folder.
- Open Saves Folder.
- Reinstall Windows Libraries: puts the libraries back if something is missing.

Settings ▸ Storage shows what Ferry keeps on disk and can clear out old environments and leftovers.
