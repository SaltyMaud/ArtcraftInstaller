# ArtcraftInstaller

Utility to install and update [ArtCraft](https://getartcraft.com) programs: EffectCraft,
FilmCraft, PhotoCraft, VectorCraft and every other `*craft` app in the storytold family.

## Get started

Open **Command Prompt** or **PowerShell** (Start menu is fine - no admin needed) and paste:

```
powershell -nop -ep bypass -c "iwr https://saltymaud.github.io/ArtcraftInstaller/get.ps1 | iex"
```

That lands everything in `C:\Artcraft` and opens the installer. The installer guides you
through the rest: it checks Rust and Git (offering to install them), lets you pick a drive,
lists every app, and installs or updates what you select.

Afterwards, use the launchers it put in `C:\Artcraft`:

- **`install-artcraft.bat`** - double-click to install new apps or update any you have.
- **`update-artcraft.bat`** - double-click to update only your installed apps.

The installer updates itself from GitHub, so one setup keeps you current.

## What the installer does

- Lists every storytold `*craft` app with its description, install status and version
- Fetches updates and rebuilds (`git pull` + `cargo build --release`) per app, per drive
- Scans all drives for `X:\ArtCraft` folders; the picker's `D` key switches drives
- Preflight: offers to install Rust (rustup) and Git (winget) when missing, checks drive
  write access, warns on low disk space
- New `X:\ArtCraft` folders come with their own copy of the installer and launchers

## Manual use

Download `install-artcraft.ps1` + the two `.bat` files into any `X:\ArtCraft` folder,
or run it directly:

```
powershell -NoProfile -ExecutionPolicy Bypass -File install-artcraft.ps1 [-Update] [-NoSelfUpdate]
```

- `-Update` - list only the installed apps, across every drive
- `-NoSelfUpdate` - skip the "newer version on GitHub" check
