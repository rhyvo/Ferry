---
title: What changed in each Ferry version
tags: release notes, changelog, what's new, update, version, new features, fixed
---
Newest first. Every version includes the changes before it.

1.3.1: Open and Save dialogs: programs that use Windows' newer file dialog get Wine's Explorer-style one, with large icons, list and details views, sortable columns and a Desktop/Documents bar, starting in your Mac's Downloads folder. Per game in Compatibility, on by default.

1.3.0: An AI assistant built into Ferry, at the bottom of the main window: type a question about a game, and open the bar into a chat or collapse it back to one line. Apple's model on your Mac chats for free, and offers Ferry's own fixes from Troubleshoot and the log check as buttons you press. With your own Claude, ChatGPT or Gemini key it can read logs and settings, change settings (each with Undo) and start games, and MCP servers can add more tools. Other AI apps can use Ferry too (Settings ▸ AI). Large address aware is offered for crashes of older 32-bit games.

1.2.5: .NET programs start: Ferry adds Microsoft's .NET loader and the settings Windows normally sets, and runs programs made for .NET 2.0–3.5 on 4.8. Adds Managed DirectX for older .NET launchers. Auto picks the engine for the game a launcher starts. New Tessellation detail setting for DirectX 11 games on Mach9, and a Troubleshoot page for objects that flicker or vanish.

1.2.4: Windows language per game. Visual Basic 6 runtime in every engine. Optional Microsoft DirectMusic and DirectPlay, old 3D game fix (dgVoodoo2), and DirectX 10/11 via DXMT (beta). Troubleshoot pages for missing music, garbled text and multiplayer. Settings that wait on another setting are greyed out with what they need. Files Ferry puts next to a game are only replaced or removed while they're still Ferry's copy.

1.2.3: Use DirectX 9 for DirectX 10/11 games with a DirectX 9 renderer. Ferry spots a game stuck waiting on itself and offers to turn off Fast Sync. Troubleshoot page for blurry textures; the log check recognises crashes inside DirectX 10/11.

1.2.2: Clearer Storage page with sorting, search always shown (⌘F), more toolbar buttons.

1.2.1: Faster downloads in four parts at once, downloads that resume, progress amounts, and a question before quitting during a download.

1.2.0: A cleaner Ferry: slimmer drop bar, real game names, last played and play time, a ⋯ menu per game, keyboard shortcuts, sorting, game settings in four pages with Advanced options and ⓘ explanations.

1.1.1: Report a Bug… from Troubleshoot, with the details filled in.

1.1.0: Ferry checks for its own updates, daily or when it opens.

1.0.9: Controller window: live drawing of the controller, button rebinding, and a Keyboard & Mouse mode.

1.0.8: PlayStation controllers show up as Xbox controllers in every game. Controllers work on D3DMetal 4 and Mullion on Rosetta 2.

1.0.7: Frame rate limit on every engine, and VSync and a limit together.

1.0.6: VSync on every engine, on by default. Leftover Wine programs are cleaned up after crashes. DXVK settings apply on every DXVK version.

1.0.5: Text says "game" or "app" to match the program. Troubleshoot greys out what's already on.

1.0.4: Troubleshoot page for the Mac's mouse pointer showing in Mach9 games.

1.0.3: Clearer Mullion settings on Rosetta 2.

1.0.2: Mullion on Rosetta 2 uses DXVK 1.10.3 for DirectX 9, fixing black screens and crashes.

1.0.1: Ferry ▸ Support Ferry… menu item.

1.0: First release.
