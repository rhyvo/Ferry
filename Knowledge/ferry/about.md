---
title: What Ferry is and what it needs
tags: ferry, about, what is ferry, requirements, install, uninstall, free, open anyway, support, report a bug
---
Ferry is a free, native Mac app that runs Windows games and programs on Apple silicon Macs. You drop in a game and press Play: Ferry reads the game, picks the best way to run it, installs what it needs, and gets out of the way. There are no bottles, prefixes or config files to set up.

What it does:
- Four engines (D3DMetal, Wine Staging with DXVK, Mullion and Mach9), each used for the games it runs best. Mullion and Mach9 don't need Rosetta.
- Windows libraries games need (Visual C++, DirectX, .NET, XNA, PhysX, OpenAL, video codecs) are installed once and shared.
- Adds .exe, .msi and .bat files, game folders, and .zip, .rar and .7z archives (archives are unpacked for you).
- Compatibility Check: shows a game's engine, graphics, what it needs and what might block it, without running it.
- One-click Steam, mods that can be removed cleanly, a Task Manager, a Storage page, per-game settings, controller support and Discord status.
- Troubleshoot (right-click a game): reads the game's log, suggests fixes and can try another engine. Report a Bug… in it opens a bug report with the details filled in, without file paths or your user name.

Needs: a Mac with Apple silicon (M1 or later) and macOS 14 or later. Mach9 needs macOS 26.4 or later. D3DMetal 4 needs macOS 27; on older macOS that download uses D3DMetal 3.

Installing: download the .dmg from Ferry's GitHub releases and drag Ferry into Applications. The first time, macOS blocks it because it isn't from the App Store or a registered developer: open System Settings ▸ Privacy & Security and click Open Anyway next to Ferry. Then Ferry's setup screen lists what it will install; the first time takes a while, mostly for .NET.

Updating: Ferry tells you when a new version is out. Updating keeps your games, settings and engines, which live outside Ferry.app.

Where things are: games run from wherever you keep them. Engines and Windows environments are in ~/Library/Application Support/Ferry. To uninstall, delete Ferry.app, and that folder too if you want everything gone.

What can't run: games with kernel anti-cheat, Windows drivers, 16-bit programs and Microsoft Store packages.

Ferry costs nothing, and so do the engines and libraries it downloads. It isn't affiliated with Apple, Microsoft, Valve or CodeWeavers. Tips on Ko-fi (Ferry ▸ Support Ferry…) help keep it going. Only run games you own.
