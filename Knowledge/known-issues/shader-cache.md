---
title: Stutter, black objects or glitches from the shader cache
tags: stutter, hitches, black objects, effects missing, shader cache, flicker after update, glitches, first time slow
---
## Symptoms
The first minutes of play stutter, or objects and effects are black or take a while to appear the first time you see them. Or, after an engine update, a game that looked right now flickers or has glitches.

## Why
The first time a game needs a material or effect, its shader has to be translated for Metal and built. Until it's ready, many games draw nothing there, and building it causes a hitch. Built shaders are saved in a cache, so it gets better every session. After an engine update, an old cache can cause glitches.

## Fix in Ferry
- Keep playing: it gets faster each session. Quit from the game's own menu so the built shaders are saved.
- A 30 frames per second limit leaves the processor and graphics room to build shaders.
- For 64-bit DirectX 11 and 12 games on Mach9, D3DMetal builds shaders much faster, with Apple's own converter. Troubleshoot offers the switch when Rosetta is installed.
- Clear Shader Cache, in the game's settings (Tools & Saves), deletes the caches Ferry knows about. Use it for flicker or glitches after an engine update. Expect some stutter for the first few minutes while it rebuilds.
- On D3DMetal, black screens or black objects in some DirectX 12 games come from a drawing method called ROV: try Hide ROV support.

## What Ferry can't fix
Every Windows game's shaders must be built for Metal the first time; that can't be skipped.
