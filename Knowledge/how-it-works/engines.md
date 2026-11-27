---
title: Ferry's four engines and which games each runs
tags: engine, d3dmetal, wine staging, dxvk, wined3d, mullion, mach9, metalsharp, which engine, auto
---
Ferry has four engines. Auto picks one for each game from its graphics and whether it's 32- or 64-bit, and you can choose another in the game's settings. If a game closes right after starting, Ferry offers the next engine to try.

D3DMetal
- Apple's own DirectX 11 and 12 to Metal translator, from its Game Porting Toolkit. Closed source; the only engine made by Apple.
- Runs on the Game Porting Toolkit's Wine (Wine 7.7 with CrossOver's changes), or on MetalSharp's Wine 11 when the optional D3DMetal 4 (beta) is installed from Settings ▸ Components.
- 64-bit programs only. Uses Rosetta 2. Auto's choice for 64-bit DirectX 11 and 12 games.

Wine Staging (WineD3D or DXVK)
- WineHQ's Wine with extra patches. Runs 32- and 64-bit programs, and installers.
- WineD3D draws DirectX 9 and older through OpenGL (Apple's OpenGL stops at 4.1) or Vulkan. DXVK draws DirectX 10 and 11 through Vulkan, then MoltenVK, then Metal.
- Uses Rosetta 2. Auto's choice for installers and many older 32-bit games.

Mullion (MetalSharp Wine)
- A Wine built for Apple silicon. Runs game code with FEX instead of Rosetta (or through Rosetta with MetalSharp's Intel build).
- Draws DirectX 10, 11 and 12 with Mullion, its own version of DXMT, and OpenGL up to 4.6 on Metal. Vulkan through MoltenVK or KosmicKrisp.
- Auto's choice for OpenGL and Clickteam games.

Mach9
- A Wine built for Apple silicon and made for launchers. Uses FEX, not Rosetta. Needs macOS 26.4 or later.
- Draws DirectX 9 with mtld3d, DirectX 10 and 11 with DXMT, DirectX 12 with vkd3d-proton, and Vulkan 1.4 with KosmicKrisp, all on Metal.
- Auto's choice for DirectX 9, DirectX 10, 32-bit DirectX 11 and Vulkan games.

Only D3DMetal (and Rosetta 2) come from Apple. The other engines and their graphics layers are open source, made by independent developers and volunteers, and update from their own projects.
