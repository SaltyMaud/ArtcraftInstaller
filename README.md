# ArtcraftInstaller

Utility to install and update [ArtCraft](https://getartcraft.com) programs: EffectCraft,
FilmCraft, PhotoCraft, VectorCraft and every other `*craft` app in the storytold family.

## Get started

Open **Command Prompt** or **PowerShell** (Start menu is fine - no admin needed) and paste:

```
powershell -c "iex ([Text.Encoding]::UTF8.GetString((iwr -UseBasicParsing https://saltymaud.github.io/ArtcraftInstaller/get.ps1).Content))"
```

That lands everything in `C:\Artcraft` and opens the installer. The installer guides you
through the rest: it checks Rust and Git (offering to install them), lets you pick a drive,
lists every app, and installs or updates what you select.

Afterwards, use the launchers it put in `C:\Artcraft`:

- **`install-artcraft.bat`** - double-click to install new apps or update any you have.
- **`update-artcraft.bat`** - double-click to update only your installed apps.

The installer updates itself from GitHub, so one setup keeps you current.

## If Windows Defender blocks the setup line

Defender's heuristics can flag any "download-and-run" command line (the family it reports,
`Trojan:Win32/Commando.A!ml`, is a *pattern* detection for `powershell … iwr … iex`, not your
computer being infected - the command only downloads this repo's own script, which you can read
here before running). If it blocks, use the manual path - it has no download-and-execute step
for Defender to flag:

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
