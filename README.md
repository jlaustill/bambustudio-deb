# BambuStudio .deb Package Builder

Build installable .deb packages for BambuStudio on Ubuntu, because AppImages are annoying.

## Requirements

- Ubuntu 22.04 or 24.04
- `curl` and `dpkg-deb` (usually pre-installed)

## Usage

```bash
# Build for Ubuntu 24.04 (default) with latest version
./build.sh

# Build for Ubuntu 22.04
./build.sh 22.04

# Build specific version for Ubuntu 24.04
./build.sh 24.04 v02.04.00.70

# Build specific version for Ubuntu 22.04
./build.sh 22.04 v02.04.00.70
```

## Installation

After building:

```bash
sudo dpkg -i bambustudio_*.deb

# If you get dependency errors:
sudo apt-get install -f
```

## Uninstallation

```bash
sudo apt remove bambustudio
```

## What This Does

1. Downloads the official BambuStudio AppImage from GitHub releases
2. Extracts it and repackages into a proper .deb structure
3. Installs to `/opt/bambustudio` with proper desktop integration
4. Registers MIME types for .stl, .3mf, .amf files

## Credits

BambuStudio is developed by [Bambu Lab](https://bambulab.com/). This repo just repackages their official releases.
