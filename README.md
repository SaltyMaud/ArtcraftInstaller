# ArtcraftInstaller

Utility to install and update [ArtCraft](https://getartcraft.com) programs: EffectCraft,
FilmCraft, PhotoCraft, VectorCraft and every other `*craft` app in the storytold family.

## Get started

Open **Command Prompt** or **PowerShell** (Start menu is fine - no admin needed) and paste:

```
powershell -c "iwr -UseBasicParsing https://saltymaud.github.io/ArtcraftInstaller/get.ps1 -OutFile $env:TEMP\get.ps1; & $env:TEMP\get.ps1"
```

That downloads the tiny setup script to your temp folder, runs it, lands everything in `C:\Artcraft` and opens the installer.

If you see **"running of scripts is disabled on this system"**, add `-ep bypass` right after
`powershell`: `powershell -ep bypass -c "..."` (same line, one extra flag). The installer guides you
through the rest: it checks Rust and Git (offering to install them), lets you pick a drive,
lists every app, and installs or updates what you select.

Afterwards, use the launchers it put in `C:\Artcraft`:

- **`install-artcraft.bat`** - double-click to install new apps or update any you have.
- **`update-artcraft.bat`** - double-click to update only your installed apps.

The installer updates itself from GitHub, so one setup keeps you current.

## If Windows Defender blocks the setup line

The setup line above is deliberately shaped to stay clean: it *downloads a file*, then *runs
that file* - two ordinary steps. Defender's `Trojan:Win32/Commando.A!ml` heuristic fires on the
other shape (`iwr` piped straight into `iex`), which this repo no longer uses, and the family
itself is a *pattern* detection, not your computer being infected. If you still get blocked,
use the manual path - it has no download-and-execute step for Defender to flag:

1. On this repo page: **Code ▸ Download ZIP**, extract it to `C:\Artcraft`.
2. Right-click `install-artcraft.ps1` (and the two `.bat` files) → **Properties** → tick
   **Unblock** → OK. This removes the web-download mark that triggers SmartScreen.
3. Double-click **`install-artcraft.bat`**. Everything from here is the same guided flow.

If a Defender toast appears with a **Run anyway** option, that's the reputation system
getting to know a brand-new tool; the unblock step above is the official way to tell
Windows you trust these files.

## What the installer does

- Lists every storytold `*craft` app with its description, install status and version
- Fetches updates and rebuilds (`git pull` + `cargo build --release`) per app, per drive
- Scans all drives for `X:\ArtCraft` folders; the picker's `D` key switches drives
- Preflight: offers to install Rust (rustup), Git (winget) and the MSVC C++ Build Tools
  (the Rust linker) when missing, checks drive write access, warns on low disk space
- New `X:\ArtCraft` folders come with their own copy of the installer and launchers

## Manual use

Download `install-artcraft.ps1` + the two `.bat` files into any `X:\ArtCraft` folder,
or run it directly:

```
powershell -NoProfile -ExecutionPolicy Bypass -File install-artcraft.ps1 [-Update] [-NoSelfUpdate]
```

- `-Update` - list only the installed apps, across every drive
- `-NoSelfUpdate` - skip the "newer version on GitHub" check
