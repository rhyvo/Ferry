---
title: Limits of the Mac's graphics that Ferry can't change
tags: apple limits, metal, tessellation, 32 kb, opengl 4.1, stream output, anti-cheat, memory, 8 gb
---
Some problems come from the Mac itself, not from Ferry or a game. No setting removes these; Ferry works around them where it can.

Tessellation size. Metal refuses a tessellated draw (extra shape detail added by DirectX 11) whose result is bigger than 32 KB. Every Apple graphics chip has the same 32 KB limit, so a newer Mac doesn't help. When a draw is refused, that object blinks or vanishes from some angles. Ferry's Tessellation detail setting keeps draws under the limit on Mach9.

OpenGL. Apple's OpenGL stops at version 4.1. Games needing newer OpenGL run on Mullion, which has its own OpenGL up to 4.6 on Metal.

Stream output. Metal has no stream output, a DirectX 10 feature. Some DirectX 10 games crash where they use it; their DirectX 9 mode usually avoids it.

DirectX 12. There's no open-source DirectX 12 to Metal translator. D3DMetal is Apple's; the open engines go through vkd3d-proton and Vulkan first.

Anti-cheat. Kernel-level anti-cheat doesn't run under Wine at all, on any engine.

Memory. On a Mac with 8 GB of memory, games can run short: macOS then moves data to disk and games stutter. Close other apps while playing. Ferry also tells DirectX 9 games drawn with DXVK they have 1 GB of video memory on these Macs, and turns full Retina resolution off for DirectX 11 and 12 games, where it costs far more frame rate than it's worth.

Low Power Mode slows the processor and graphics, and the Mac's window tiling can fight with games' windows. Those are Mac settings you can change; see the doc on Mac settings that affect games.
