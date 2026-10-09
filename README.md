# ArtcraftInstaller

Utility to install and update [ArtCraft](https://getartcraft.com) programs: EffectCraft,
FilmCraft, PhotoCraft, VectorCraft and every other `*craft` app in the storytold family.

> **Disclaimer:** This is an unofficial, community-made project. It is not affiliated with,
> endorsed by, or sponsored by ArtCraft or storytold. All names and trademarks belong to
> their respective owners.

## Get started

Open **Command Prompt** or **PowerShell** (Start menu is fine - no admin needed) and paste:

```
powershell -ep bypass -c "iwr -UseBasicParsing https://saltymaud.github.io/ArtcraftInstaller/get.ps1 -OutFile $env:TEMP\get.ps1; & $env:TEMP\get.ps1"
```

That downloads the tiny setup script to your temp folder, runs it, and opens the installer -
**nothing is created on your drives until you confirm an install**. The install target defaults
to `C:\Artcraft`; press `D` in the installer to pick a different drive.

Afterwards, use the launchers the installer places in your `X:\ArtCraft` folder:

- **`install-artcraft.bat`** - double-click to install new apps or update any you have.
- **`update-artcraft.bat`** - double-click to update only your installed apps.

The installer updates itself from GitHub.

## What the installer does

- Lists every storytold `*craft` app with its description, install status and version
- Fetches updates and rebuilds (`git pull` + `cargo build --release`) per app, per drive
- Scans all drives for `X:\ArtCraft` folders; the picker's `D` key switches drives
- Preflight: offers to install Rust (rustup), Git (winget) and the MSVC C++ Build Tools when missing, checks drive write access, warns on low disk space
- New `X:\ArtCraft` folders come with their own copy of the installer and launchers

## Manual use

Download `install-artcraft.ps1` + the two `.bat` files into any `X:\ArtCraft` folder,
or run it directly:

```
powershell -NoProfile -ExecutionPolicy Bypass -File install-artcraft.ps1 [-Update] [-NoSelfUpdate]
```

- `-Update` - list only the installed apps, across every drive
- `-NoSelfUpdate` - skip the "newer version on GitHub" check
