---
title: DirectX, OpenGL and Vulkan on a Mac
tags: directx, dx9, dx10, dx11, dx12, opengl, vulkan, metal, graphics, renderer, glide, directdraw
---
Windows games draw with DirectX, OpenGL or Vulkan. Macs only have Metal (plus an old OpenGL), so every Windows game's drawing has to be translated to Metal while it plays. Ferry's Compatibility Check reads a game's files to see which one it uses, without running it.

How each kind is translated:
- DirectX 11 and 12 (64-bit): D3DMetal, Apple's translator, straight to Metal. Mach9 and Mullion can also draw them. DirectX 12 on the open-source engines goes through vkd3d-proton and Vulkan; there's no open-source DirectX 12 to Metal translator.
- DirectX 10 and 11 (32-bit, or as a backup): DXMT in Mach9, Mullion's own version of DXMT, or DXVK (through Vulkan and MoltenVK) on Wine Staging.
- DirectX 9: mtld3d in Mach9, straight to Metal. Otherwise WineD3D, through OpenGL or Vulkan. DXVK can also draw DirectX 9.
- DirectX 8 and older: WineD3D.
- 3dfx Glide (late-1990s 3D games): Wine has no Glide of its own, so these need the optional old 3D game fix (dgVoodoo2), which draws them through DirectX 11.
- DirectX 1 to 7: WineD3D, or the old 3D game fix (dgVoodoo2).
- DirectDraw (old 2D games): the old 2D game fix, cnc-ddraw.
- OpenGL: Mullion draws up to OpenGL 4.6 on Metal. The other engines use Apple's OpenGL, which stops at 4.1.
- Vulkan: KosmicKrisp (Vulkan 1.4 on Metal) in Mach9, or MoltenVK.

Many DirectX 10 and 11 games from around 2006 to 2010 also have a DirectX 9 renderer. Use DirectX 9 in a game's settings makes them use it, which avoids problems some DirectX 10 and 11 translators have, at the cost of DirectX 10 and 11 effects.

A launcher can use different graphics from the game it starts. Ferry's Auto looks at the game the launcher starts, not the launcher.
