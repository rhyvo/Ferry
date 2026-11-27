---
title: .NET launchers and tools close at once or won't open
tags: launcher won't open, .net, dotnet, net framework, mscoree, managed directx, settings tool, closes immediately, net 6, net 8
---
## Symptoms
A launcher, settings tool or game built with Microsoft's .NET closes at once with an error, or never shows its window. Often it's the small launcher many games use for graphics settings.

## Why
.NET programs start through a small Microsoft loader called mscoree.dll. Windows has its own, so the .NET Framework 4.8 package doesn't include it, and under Wine the environment kept Wine's stand-in, which can't start the real .NET. Older programs made for .NET 2.0 to 3.5 also need Windows' settings that run them on 4.8, and older launchers use Managed DirectX for their graphics settings screen.

## Fix in Ferry
- When a .NET program starts in an environment with .NET 4.8 (Settings ▸ Components ▸ .NET Framework 2.0–4.8), Ferry adds Microsoft's loader from its .NET 4.0 package (about 50 MB, downloaded once), sets the registry values Windows normally sets (InstallRoot and OnlyUseLatestCLR), and adds Managed DirectX. Existing environments are fixed the next time a .NET program starts; nothing needs reinstalling.
- If the log shows a .NET program with no .NET Framework, Troubleshoot offers to install it.
- Programs built on Microsoft's newer .NET need .NET 6 or 8, which Ferry can install. For other versions, install Microsoft's Windows x64 Desktop Runtime inside the game's environment.
- Auto picks the engine for the game a launcher starts, not for the launcher.

## What Ferry can't fix
Not every .NET program runs under Wine. If a launcher still won't open, add the game's own .exe to Ferry and start it directly.
