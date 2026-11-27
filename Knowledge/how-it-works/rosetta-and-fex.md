---
title: Rosetta 2 and FEX
tags: rosetta, fex, intel, apple silicon, arm, cpu translation, avx
---
Windows games are built for Intel and AMD processors. Apple silicon Macs use a different kind of processor, so the game's code has to be translated as well as its graphics.

Rosetta 2 is Apple's translator for Intel code. D3DMetal and Wine Staging run games through it.

FEX is an open-source translator that Mullion and Mach9 use instead. Because of it, those two engines work on a Mac without Rosetta, and Ferry switches to them automatically when Rosetta isn't installed. Running 32-bit programs without Rosetta needs macOS 26.4 or later.

On Mullion you can choose with CPU translation, under Graphics ▸ Advanced in the game's settings. FEX works without Rosetta; Rosetta 2 is usually faster but needs MetalSharp's Intel build, which comes with D3DMetal 4 (beta) in Settings ▸ Components. Some Mullion options, such as the KosmicKrisp Vulkan driver, only work with FEX.

Advertise AVX (Rosetta), in a game's Compatibility settings, tells programs that require AVX that the processor has it. It applies to the engines that run through Rosetta.
