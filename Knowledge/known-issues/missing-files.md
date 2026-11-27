---
title: The game says a DLL is missing or won't start
tags: missing dll, dll not found, won't start, visual c++, msvcp, d3dx9, xinput, physx, openal, xna, wrong dll, c000007b
---
## Symptoms
The game won't start, or shows an error naming a .dll file. Troubleshoot may show "It needs Visual C++" (or DirectX, PhysX, OpenAL, XNA and so on), "It's missing …", or "… is the wrong kind for this program".

## Why
Windows programs rely on extra libraries: Visual C++, DirectX's extras, .NET, XNA, PhysX, OpenAL, the Visual Basic 6 runtime. If one isn't in the game's Windows environment, the game stops before anything else happens. Sometimes the file belongs to the game itself and didn't get copied. And a 32-bit DLL next to a 64-bit program (or the other way round) also stops it; that's usually a file someone copied in by hand.

## Fix in Ferry
- Ferry reads the game's log after each run. When it names a missing file that comes with a library Ferry installs, Troubleshoot offers to install it. That reinstalls the game's Windows libraries and can take a few minutes.
- Reinstall Windows Libraries (Tools & Saves in the game's settings) puts back everything Ferry installs.
- If the missing file isn't part of Windows or of a library Ferry installs, it normally comes with the game: check the whole game folder was copied or extracted.
- For a "wrong kind" DLL: remove that file from the game's folder, or replace it with the right version.
- If the game called a Windows function the engine's Wine doesn't have, Troubleshoot offers another engine, whose Wine may have it.

## What Ferry can't fix
Ferry doesn't install Visual C++ 2003 (many games ship its file themselves), or .NET versions other than the .NET Framework, .NET 6 and .NET 8. For those, install Microsoft's installer inside the game's environment.
