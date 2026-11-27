---
title: Videos and cutscenes are solid pink
tags: pink video, pink screen, cutscenes pink, intro video, bink, movies wrong colour, mullion, winemetalgl, opengl
---
## Symptoms
Pre-rendered videos (intros, cutscenes, loading or mission videos) play as a solid pink picture while their sound plays normally. The game itself draws correctly.

## Why
It was seen in a DirectX 9 game on Mullion, which draws DirectX 9 through WineD3D and OpenGL. Mullion's default OpenGL, WineMetalGL, shows these videos pink; with Apple's OpenGL the same videos play with the right colours. The colour suggests the video's picture data is read wrongly, but the exact cause isn't confirmed.

## Fix in Ferry
- OpenGL implementation, in the game's settings (Graphics ▸ Advanced, Mullion engine): choose Apple's OpenGL. It stops at OpenGL 4.1 but is long-tested.
- Or use Mach9 for DirectX 9 games: it draws them straight to Metal with mtld3d, with no OpenGL in between, and videos hold up much better than on WineD3D. It's Auto's choice for DirectX 9 games where Mach9 is available.

## What Ferry can't fix
The pink videos come from WineMetalGL and need a fix in MetalSharp Wine.

Example: Call of Duty 4: Modern Warfare's videos on Mullion with WineMetalGL.
