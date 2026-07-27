#!/bin/bash
set -e

# Configuration
UBUNTU_VERSION="${1:-24.04}"  # Default to 24.04, pass 22.04 for older systems
VERSION="${2:-$(curl -s https://api.github.com/repos/bambulab/BambuStudio/releases/latest | grep -Po '"tag_name": "\K[^"]+')}"
ARCH="amd64"
PKG_NAME="bambustudio"

# Parse version for package (convert v02.04.00.70 to 2.4.0.70)
PKG_VERSION=$(echo "$VERSION" | sed 's/^v//' | sed 's/^0*//' | sed 's/\.0*/./g' | sed 's/\.\././g')
PKG_DIR="${PKG_NAME}_${PKG_VERSION}_${ARCH}"

echo "Building BambuStudio ${VERSION} (Ubuntu ${UBUNTU_VERSION}) .deb package..."

# Determine AppImage filename pattern. Upstream has used both "ubuntu-24.04"
# (through v02.04.00.70) and "ubuntu24.04" (v02.07.01.62 onward), so match either.
if [[ "$UBUNTU_VERSION" == "22.04" ]]; then
    APPIMAGE_PATTERN="ubuntu-?22\\.04"
elif [[ "$UBUNTU_VERSION" == "24.04" ]]; then
    APPIMAGE_PATTERN="ubuntu-?24\\.04"
else
    echo "Unsupported Ubuntu version. Use 22.04 or 24.04"
    exit 1
fi

# Find the exact AppImage filename from release
echo "Finding AppImage for Ubuntu ${UBUNTU_VERSION}..."
APPIMAGE_URL=$(curl -s "https://api.github.com/repos/bambulab/BambuStudio/releases/tags/${VERSION}" | \
    jq -r --arg pattern "$APPIMAGE_PATTERN" \
        '.assets[] | select((.name | test($pattern)) and (.name | endswith(".AppImage"))) | .browser_download_url' | \
    head -1)

if [[ -z "$APPIMAGE_URL" || "$APPIMAGE_URL" == "null" ]]; then
    echo "Error: Could not find AppImage for Ubuntu ${UBUNTU_VERSION} in release ${VERSION}"
    exit 1
fi

APPIMAGE_FILE=$(basename "$APPIMAGE_URL")
echo "Found: ${APPIMAGE_FILE}"

# Clean previous builds
rm -rf "$PKG_DIR" squashfs-root *.deb *.AppImage

# Download
echo "Downloading..."
curl -L -o "$APPIMAGE_FILE" "$APPIMAGE_URL"
chmod +x "$APPIMAGE_FILE"

# Extract AppImage
echo "Extracting AppImage..."
./"$APPIMAGE_FILE" --appimage-extract > /dev/null 2>&1

# Create package structure
echo "Creating package structure..."
mkdir -p "${PKG_DIR}/opt/bambustudio"
mkdir -p "${PKG_DIR}/usr/bin"
mkdir -p "${PKG_DIR}/usr/share/applications"
mkdir -p "${PKG_DIR}/usr/share/icons/hicolor/256x256/apps"
mkdir -p "${PKG_DIR}/usr/share/mime/packages"
mkdir -p "${PKG_DIR}/DEBIAN"

# Move application files
mv squashfs-root/bin "${PKG_DIR}/opt/bambustudio/"
mv squashfs-root/resources "${PKG_DIR}/opt/bambustudio/"

# Copy icon
cp squashfs-root/BambuStudio.png "${PKG_DIR}/usr/share/icons/hicolor/256x256/apps/bambustudio.png"

# Create launcher script
cat > "${PKG_DIR}/usr/bin/bambustudio" << 'EOF'
#!/bin/bash
export LD_LIBRARY_PATH="/opt/bambustudio/bin:$LD_LIBRARY_PATH"
export LC_ALL=C
exec /opt/bambustudio/bin/bambu-studio "$@"
EOF
chmod +x "${PKG_DIR}/usr/bin/bambustudio"

# Create desktop entry
cat > "${PKG_DIR}/usr/share/applications/bambustudio.desktop" << EOF
[Desktop Entry]
Name=BambuStudio
GenericName=3D Printing Software
Comment=A cutting-edge, feature-rich slicing software for Bambu Lab printers
Exec=/usr/bin/bambustudio %U
Icon=bambustudio
Terminal=false
Type=Application
Categories=Graphics;3DGraphics;Engineering;
MimeType=model/stl;model/3mf;application/vnd.ms-3mfdocument;application/prs.wavefront-obj;application/x-amf;x-scheme-handler/bambustudio;x-scheme-handler/bambustudioopen;
Keywords=3D;Printing;Slicer;slice;3D;printer;convert;gcode;stl;obj;amf;SLA;Bambu;
StartupNotify=false
StartupWMClass=bambu-studio
EOF

# Create MIME type definitions for 3D file associations
cat > "${PKG_DIR}/usr/share/mime/packages/bambustudio.xml" << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<mime-info xmlns="http://www.freedesktop.org/standards/shared-mime-info">
  <mime-type type="model/3mf">
    <comment>3D Manufacturing Format</comment>
    <glob pattern="*.3mf"/>
  </mime-type>
  <mime-type type="application/x-amf">
    <comment>Additive Manufacturing File</comment>
    <glob pattern="*.amf"/>
  </mime-type>
</mime-info>
EOF

# Create control file
INSTALLED_SIZE=$(du -sk "${PKG_DIR}" | cut -f1)
cat > "${PKG_DIR}/DEBIAN/control" << EOF
Package: ${PKG_NAME}
Version: ${PKG_VERSION}
Section: graphics
Priority: optional
Architecture: ${ARCH}
Installed-Size: ${INSTALLED_SIZE}
Depends: libgtk-3-0, libglu1-mesa, libgl1, libegl1, libdbus-1-3, libsecret-1-0, libwebkit2gtk-4.1-0 | libwebkit2gtk-4.0-37, gstreamer1.0-plugins-base, gstreamer1.0-plugins-good
Maintainer: Local Build <local@localhost>
Homepage: https://bambulab.com/en/download/studio
Description: BambuStudio - Slicer for Bambu Lab 3D Printers
 BambuStudio is a cutting-edge, feature-rich slicing software
 designed for Bambu Lab's 3D printers. Based on PrusaSlicer and
 SuperSlicer, it offers seamless integration with Bambu Lab
 printers and supports advanced features like multi-color printing,
 automatic calibration, and remote monitoring.
EOF

# Create postinst to update desktop database and icon cache
cat > "${PKG_DIR}/DEBIAN/postinst" << 'EOF'
#!/bin/bash
set -e
if command -v update-desktop-database > /dev/null; then
    update-desktop-database -q /usr/share/applications || true
fi
if command -v update-mime-database > /dev/null; then
    update-mime-database /usr/share/mime || true
fi
if command -v gtk-update-icon-cache > /dev/null; then
    gtk-update-icon-cache -q /usr/share/icons/hicolor || true
fi
EOF
chmod +x "${PKG_DIR}/DEBIAN/postinst"

# Create postrm to clean up on removal
cat > "${PKG_DIR}/DEBIAN/postrm" << 'EOF'
#!/bin/bash
set -e
if [ "$1" = "remove" ] || [ "$1" = "purge" ]; then
    if command -v update-desktop-database > /dev/null; then
        update-desktop-database -q /usr/share/applications || true
    fi
    if command -v update-mime-database > /dev/null; then
        update-mime-database /usr/share/mime || true
    fi
fi
EOF
chmod +x "${PKG_DIR}/DEBIAN/postrm"

# Build the .deb
echo "Building .deb..."
dpkg-deb --build --root-owner-group "$PKG_DIR"

# Cleanup
rm -rf "$PKG_DIR" squashfs-root "$APPIMAGE_FILE"

echo ""
echo "Done! Built: ${PKG_DIR}.deb"
echo "Install with: sudo dpkg -i ${PKG_DIR}.deb"
echo ""
echo "If you encounter dependency issues, run:"
echo "  sudo apt-get install -f"
