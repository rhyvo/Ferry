# Ferry

Drag a Windows game or program (`.exe`) onto the window and it runs. Ferry is a small native Mac app (about 2 MB) that sets up the free translation layers for you and gets out of the way.

## Build it (about a minute)

1. Unzip this folder, e.g. into Downloads.
2. Open **Terminal** and run:

   ```
   bash ~/Downloads/Ferry/build.sh
   ```

   If the folder is somewhere else, type `bash ` (with a space), drag `build.sh` from the Ferry folder into the Terminal window, and press Return.

Ferry is compiled, copied to `/Applications`, and opened. You need Xcode or the Xcode Command Line Tools installed. To build a newer version, delete the old Ferry folder before unzipping the new one (otherwise your Mac names it "Ferry 2"), then run the same command.

Running the script through `bash` like this doesn't need your password. Double-clicking a script you downloaded does, because macOS makes you approve each downloaded script in Privacy & Security.

## First launch: Install

Ferry opens on a setup screen listing everything it can install, grouped as **Required** (locked on, because Ferry can't run Windows software without them), **Recommended** (ticked; untick any you don't want, and Ferry shows in orange what you'd lose) and **Optional** (unticked). The Install button shows the download size for what's ticked. The same list is in Settings ▸ Components; changes there apply the next time you click Run Setup Again. What it can install:

- Rosetta 2 (macOS asks for your password if it's missing)
- GStreamer, the official video runtime that plays cutscenes in Wine Staging games (macOS asks for your password once)
- All four engines: Game Porting Toolkit (D3DMetal), Wine Staging, DXVK, and MetalSharp Wine (native Apple silicon, no Rosetta)
- Windows libraries: Visual C++ 2005, 2008, 2010, 2012, 2013 and 2015–2022 (32- and 64-bit), DirectX June 2010 and Microsoft's DirectX shader compiler, .NET Framework 4.8, .NET 6 and 8 desktop runtimes, XNA Framework 4.0, OpenAL, PhysX (for 2008–2013 games) and LAV Filters (video codecs for older cutscenes). WebView2 is optional (Settings ▸ Defaults). Every Microsoft installer is itself a 32-bit program, so environments whose Wine can't run 32-bit programs (D3DMetal) get the 64-bit Visual C++ files copied in from the Wine Staging environment instead. Wine is told to use Microsoft's Visual C++ files over its own simplified copies.
- 7-Zip (the official command-line version, under 1 MB), for unpacking games that come as archives
- Common Windows fonts linked from the ones macOS already has (Arial, Times New Roman, Verdana…), plus Japanese, Chinese and Korean font mappings so text doesn't show as boxes
- One ready-made Windows environment per engine with all of that already installed

GStreamer and MetalSharp Wine are optional: if either fails, setup carries on and lists what to retry.

Setup takes a while, mostly because .NET installs slowly under Wine. To save time, everything is downloaded once, and the Wine Staging and Mullion environments are built at the same time (the D3DMetal one follows Wine Staging's, since it copies Visual C++ from it). Libraries install separately into each environment because each is its own Windows C: drive. If a library can't be downloaded, setup skips it, finishes the rest, and tells you which to retry. You can't drop games in until it finishes. After that, each new game gets an instant copy of the ready-made environment, so its first launch skips the installers. **Settings ▸ System ▸ Run Setup Again** repairs things without touching your games or saves, and **Settings ▸ Engines ▸ Update** rebuilds the ready-made environment for that engine automatically.

## Updates

Ferry checks GitHub once a day for new releases of its three engines. When one is out, a pop-up lists what changed (e.g. `Wine Staging: 11.15 → 11.17`) with **Update Now** and **Later**. After **Later**, a banner stays at the top of the library until you update, and the pop-up doesn't come back for those same versions.

- **Settings ▸ Engines** shows each engine's version, highlights ones with an update, and has **Check for Updates** and **Update All**. You can turn the daily check off there.
- **Ferry ▸ Check for Updates…** in the menu bar checks right away.
- Updating rebuilds the ready-made Windows environment for that engine. Existing games keep their saves and switch to the new version the next time they start.
- Quit running games before updating; Ferry won't update Wine underneath a running game.
- When Ferry gets new Windows libraries (after you rebuild it from new source), a banner offers to install them. New games get them automatically; games already in Ferry can use Reinstall Windows Libraries.
- Visual C++ and DirectX aren't part of the update check. Games are built against fixed versions of those, so newer releases rarely matter.
- Ferry itself is built on your Mac, so it doesn't update itself. Rebuild with the command above when you get a new version of the source.

## Using it

- **Drop** a game's `.exe` (or an `.msi`/`.bat`) on the window, on the Dock icon, or click the box to browse. The **+** menu also has Install Steam.
- The game runs from its own folder, so games that come as a folder of files work as-is. Windows sees your whole Mac as drive `Z:`.
- **Play / Stop** per game. The slider button opens that game's settings.
- **Make Mac Shortcut** puts a double-clickable app in `~/Applications/Ferry Games`.
- **Installers:** drop the setup `.exe`, install as normal, then use **Change Executable…** in the game's settings to point at the installed game inside its C: drive.

## Steam and other launchers

**Install Steam** (the **+** menu, or the button in an empty library) downloads Steam, installs it into a D3DMetal environment (falling back to Wine Staging if its installer won't run there), points the entry at `steam.exe`, sets launch arguments that stop Steam's built-in browser from going black under Wine (`-cef-disable-gpu -cef-disable-gpu-compositing -no-cef-sandbox`), and starts it. If it fails partway, click Install Steam again to retry in the same entry.

Games you start from Steam run inside Steam's Windows environment and open in their own window, the same as on a PC. Steam and the game talk to each other normally (DRM checks, achievements, cloud saves).

**Add Program to This Environment…** (right-click any entry, or in its settings) adds a program from inside that entry's environment as its own entry, e.g. a game Steam installed under `Program Files (x86)/Steam/steamapps/common`. It then gets its own Play button and can have a Mac shortcut, while still running inside Steam's environment, so Steam's checks pass.

Rules for programs that share an environment:
- They use the owner's Wine build. A game inside a D3DMetal Steam always uses D3DMetal.
- Windows version and Retina are set on the owner, since they apply to the whole environment.
- Stopping the game leaves Steam running; stopping Steam closes everything in its environment.
- Removing the game only removes the Ferry entry. Removing Steam also removes the programs added to its environment.
- Steam's store and login pages can still glitch under Wine, and the in-game overlay usually doesn't work. Epic, EA, Ubisoft and Battle.net work the same way but vary in how well they run.

## Compatibility Check

**⌘K**, the stethoscope button in the toolbar, or **File ▸ Check Compatibility…** opens a window where you can drop a program, a game folder, or a `.zip`/`.rar`/`.7z` archive. Dropping a folder or archive on the main window opens it here too. Ferry reads the files without running anything and shows:

- **What it is:** game engine (Unity, Unreal, GameMaker, RPG Maker, XNA, Godot, Ren'Py, Clickteam, Electron and others), or whether it's an installer; 32-bit, 64-bit or ARM64; DirectX version.
- **What it needs:** read from the DLLs the program actually loads: Visual C++ versions, DirectX extras, .NET, XNA, OpenAL, PhysX, Steam.
- **What would block it:** anti-cheat, 16-bit programs, Microsoft Store packages, Java wrappers.
- **A verdict** (Should work / Might work / Won't run) and **recommended settings** with the reason for each.

The recommendations use everything Ferry has learned in testing: Clickteam games (most FNaF fan games) and OpenGL games go to Mullion, DirectDraw games get the old 2D game fix, and other 32-bit DirectX games keep the most tested route with Mullion suggested as the next thing to try. It also reads .NET apps' config files to see which .NET version they need, and spots WebView2 launchers and older video formats. Dropping a game straight on the main window uses the same checker, so a game gets the same settings either way, and programs it knows can't run are refused with the reason.

For folders and archives, Ferry picks the most likely main program and lets you switch to another. **Add to Ferry** or **Add and Play** uses the recommended settings.

### Games from archives

- **Multi-part archives** work: drop any part (`.part1.rar`, `.part02.rar`, `.rar` + `.r00`, `.7z.001`, `.zip.001`, `.zip` + `.z01`) and Ferry finds the rest in the same folder. If one is missing, it says which before unpacking anything.
- **7-Zip** does the unpacking: it reads the archive in one pass, opens every part itself, and reports its own progress, so Ferry doesn't have to keep measuring the folder. If 7-Zip can't read a single archive, macOS's built-in unpacker is tried instead. Without 7-Zip, single archives use macOS's unpacker and 7-Zip is downloaded the first time you drop a multi-part one.
- **Free space is checked first**, so it doesn't fail at 90%.
- **Where games go:** Settings ▸ Defaults ▸ Games from archives: your Games folder (default), next to the archive (e.g. on a big external drive), or a folder you choose. Ferry unpacks into a hidden working folder on that same drive (named `.noindex`, so Spotlight doesn't index it mid-unpack), so adding the game is an instant rename rather than a second copy.
- **Move the archive to the Trash after adding** (a tick box in the check window, or in Settings): only after the game is in place, and every part goes.
- **Not done on purpose:** unpacking one .zip with several tar processes at once. tar treats file names as patterns, so two of them could write the same file at the same time and corrupt it. The speed gain wasn't worth that risk.
- Password-protected archives aren't supported yet; unpack those with an app that asks for the password, then drop the folder in.

## Discord status

While a game runs, Ferry sets your Discord status through the Discord app on your Mac (it has to be open). Ferry checks the game against Discord's public list of about 25,000 games it recognizes:

- **Known games** (e.g. Call of Duty: Black Ops II, Hollow Knight, the original FNaF) show with their real name and icon, with "Playing through Ferry on Mac" underneath.
- **Other games** (most fan games), and **Ferry itself while it's open**, need one-time setup: create a free application named "Ferry" at discord.com/developers/applications and paste its Application ID into Settings ▸ Defaults ▸ Discord. Click **Save Ferry's Icon for Discord…**, then upload that image as the application's App Icon and as a Rich Presence art asset named exactly `ferry`. Unknown games then show as "Playing Ferry" with the game's name, and with no game running you show as "Playing Ferry: Browsing the library". Discord doesn't allow "Using" as a verb, so "Playing" is the closest.

Matching uses the game's folder and program name together, or a program name only one game uses, or the title. A program name shared by many games (195 games use `game.exe`) is never trusted on its own. Turn it off in Settings ▸ Defaults, or per game in its settings.

## How it picks a translation engine

Ferry reads the `.exe` (without running it) to see if it's 32/64-bit and which DirectX it uses:

| Game | Engine | Built on |
|---|---|---|
| 64-bit DirectX 11 / 12 (most modern games) | **D3DMetal** → Metal | Gcenx's build of Apple's Game Porting Toolkit |
| DirectX 10, or 32-bit DirectX 11 | **DXVK** → Vulkan → Metal | Wine Staging + DXVK-macOS |
| DirectX 9 and older, OpenGL, most 32-bit games | **WineD3D** | Wine Staging |
| Any game when Rosetta isn't available, or 32-bit games that crash on Wine Staging | **Mullion** (a DXMT fork) → Metal, plus an OpenGL-on-Metal layer for older games | MetalSharp Wine, which runs game code through FEX instead of Rosetta (32-bit needs macOS 26.4+) |

**If a game closes within a few seconds,** Ferry shows the end of its log and offers to retry with the next engine (D3DMetal → Mullion → DXVK → WineD3D for 64-bit games, DXVK → WineD3D → Mullion for 32-bit). The one that works becomes that game's setting.

**Rosetta:** Apple has said macOS 27 is the last version with full Rosetta. Wine Staging (WineD3D and DXVK) and D3DMetal need it; Mach9 and Mullion don't. If it's missing, Auto sends every program, installers and 32-bit games included, to Mach9 (Mullion for OpenGL and Clickteam games). 32-bit programs need macOS 26.4 or later there.

You can override this per game. All of it is downloaded from the projects' GitHub releases, so **Settings ▸ Engines ▸ Update** always gets the latest.

**Newer D3DMetal:** download Apple's *Evaluation environment for Windows games* (free Apple developer account) from developer.apple.com/games, then **Settings ▸ Engines ▸ Import newer D3DMetal…** and pick the `.dmg`. **Restore Bundled Version** undoes it.

## Per-game settings

- DLSS → MetalFX upscaling (D3DMetal), Retina resolution, Metal FPS HUD
- Windows version, Fast synchronization (MSync), AVX reporting for Rosetta
- ⌘ Command as Ctrl, ⌥ Option as Alt, exclusive full-screen mode
- For Mullion games: which graphics route MetalSharp uses (Mullion, DXVK for 64-bit games, WineD3D, or VKD3D-Proton for DirectX 12), and which OpenGL it uses (WineMetalGL or Apple's). 32-bit DirectX 9 games always go through WineD3D and that OpenGL, so the OpenGL choice is the one that matters for them.
- For DirectX 9 games: draw with DXVK (Vulkan → Metal) instead of WineD3D. Ferry puts DXVK's d3d9.dll next to the game and removes it again when turned off; it never replaces a d3d9.dll the game came with
- For DirectX 9 games: **Faster screen copies** (on automatically). Apple GPUs draw in on-chip tiles, so a game that copies into the frame it's drawing makes the GPU write the whole frame out and read it back each time; effects like panoramas, blur or glow can do that hundreds of times a frame. Ferry's stand-in d3d9.dll does those copies as draws instead (about 3.5× faster; FNaF: Sister Location went from 10–13 fps to 27–30), and passes everything else to DXVK or the engine's own DirectX 9. Turn it off if a game draws incorrectly
- For DXVK's DirectX 9: **Video memory** (1 GB automatically on Macs with 8 GB or less, so games don't fill memory with textures until macOS swaps)
- For 32-bit games: the old 2D game fix (cnc-ddraw), which Ferry places next to the game and removes again when turned off; it never replaces a ddraw.dll the game came with
- For WineD3D/DXVK games: OpenGL or Vulkan drawing, drawing on one thread (fixes parts of models lagging a frame behind, like arms trailing the gun, at some cost in speed), and a fix for frozen or blank windows
- Back Up Saves (zips to Documents ▸ Ferry Backups), Open Saves Folder, Clear Shader Cache
- Launch arguments and extra environment variables
- Wine Configuration, Controllers panel, Open C: Drive, Reinstall Windows Libraries, logs

Xbox and PlayStation controllers are passed through automatically.

## What can't work

- **Kernel anti-cheat games** (Valorant, Fortnite, most competitive shooters) won't run under any Mac translation layer.
- Windows **drivers** can't load on macOS; the translation layers stand in for them.
- **32-bit games without Rosetta:** MetalSharp Wine (Mullion) runs 32-bit games through FEX on macOS 26.4 and later, so they keep working when Rosetta is limited.

## Where things live

- Engines, 7-Zip, Windows environments and logs: `~/Library/Application Support/Ferry`
- Games unpacked from archives: `~/Games` unless you chose another place
- Each game gets its own Windows environment per Wine build (D3DMetal, Wine Staging, MetalSharp). Their save folders (AppData, Saved Games) all point at one shared `saves` folder, so switching engines never hides a save. Anything that was already there is merged in, and the original is kept beside it as "(before sharing)".
- Uninstall: delete `/Applications/Ferry.app` and the folder above.
