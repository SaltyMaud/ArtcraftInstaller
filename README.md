# ArtcraftInstaller

Windows utility to build and update [ArtCraft](https://github.com/storytold) programs from their GitHub repos: EffectCraft,
FilmCraft, PhotoCraft, VectorCraft and every other `*craft` app in the Storytold ArtCraft family.

> **Disclaimer:** This is an unofficial, community-made project. It is not affiliated with,
> endorsed by, or sponsored by ArtCraft or Storytold. All names and trademarks belong to
> their respective owners.

## Get started

Open **Command Prompt** or **PowerShell** and paste:

```
powershell -ep bypass -c "iwr -UseBasicParsing https://saltymaud.github.io/ArtcraftInstaller/get.ps1 -OutFile $env:TEMP\get.ps1; & $env:TEMP\get.ps1"
```

That one line runs a tiny bootstrap script: it downloads the installer and its launchers
into your temp folder, and the installer handles the rest - including installing everything
needed to build the apps (Rust, Git, MSVC C++ Build Tools) when they're missing. One stop,
no prerequisites. **Nothing is created on your drives until you confirm an install.**
The install target defaults to `C:\Artcraft_dev`; press `D` in the installer to pick a different drive.

Afterwards, use the launchers the installer places in your `X:\Artcraft_dev` folder:

- **`install-artcraft.bat`** - double-click to install new apps or update any you have.
- **`update-artcraft.bat`** - double-click to update only your installed apps.

The installer also keeps itself current from GitHub.

## What the installer does

- Lists every storytold `*craft` app with its description, install status and version
- Installs new apps, updates existing ones (`git pull` + `cargo build --release`) and removes
  them - each run starts from a plain-language summary of exactly what will happen
- Force-rebuilds any up-to-date app from scratch when you want a guaranteed clean compile
- Creates Start Menu shortcuts automatically and asks about desktop icons; copies on
  multiple drives get clearly distinguished shortcuts
- Works across every drive: finds all `X:\Artcraft_dev` folders, installs where you choose and
  updates each copy where it lives
- Preflight: installs Rust (rustup), Git (winget) and the MSVC C++ Build Tools when missing,
  checks drive write access, warns on low disk space
- New `X:\Artcraft_dev` folders come with their own copy of the installer and launchers

## Manual use

Download `install-artcraft.ps1` + the two `.bat` files into any `X:\Artcraft_dev` folder,
or run it directly:

```
powershell -NoProfile -ExecutionPolicy Bypass -File install-artcraft.ps1 [-Update] [-NoSelfUpdate]
```

- `-Update` - list only the installed apps, across every drive
- `-NoSelfUpdate` - skip the "newer version on GitHub" check
