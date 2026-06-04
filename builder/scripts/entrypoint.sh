#!/bin/bash
# Copyright 2024 Michael Smith <m@hacktheplanet.be>
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License version 3 as published
# by the Free Software Foundation.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston,
# MA 02110-1301, USA.

set -euo pipefail

if [[ -z "${MISTER_RELEASE:-}" ]]; then
  echo "Please set MISTER_RELEASE environment variable to a valid release, e.g. 'release_20231108.7z'"
  echo "See https://github.com/MiSTer-devel/SD-Installer-Win64_MiSTer/tree/master for a list of available releases."
  exit 1
fi

echo "Building MC-Fusion SD card image with ${MISTER_RELEASE}..."

IMG="/files/images/mc-fusion.img"
ZIP="/files/images/mc-fusion-$(date +"%Y-%m-%d").img.zip"

SECTOR_SIZE=512

P1_START=10240
P2_START=2048

P1_OFFSET=$((P1_START * SECTOR_SIZE))

MOUNT_DIR="/mnt/data"

cleanup() {
  sync || true

  if mountpoint -q "$MOUNT_DIR"; then
    umount "$MOUNT_DIR" || true
  fi
}

trap cleanup EXIT

mkdir -p /files/images
rm -f /files/images/mc-fusion.img
rm -f /files/images/mc-fusion-*.img.zip
mkdir -p "$MOUNT_DIR"

# Create the SD card image container
dd if=/dev/zero of="$IMG" bs=12M count=10

# Partition the SD card image
sfdisk --force "$IMG" << EOF
start=10240, type=0b
start=2048, size=8192, type=a2
EOF

# Install the bootloader into partition 2 by offset.
# This avoids relying on /dev/loop0p2, which can fail under Docker/WSL.
dd if="/files/vendor/bootloader.img" of="$IMG" bs="$SECTOR_SIZE" seek="$P2_START" conv=notrunc
sync

# Create the data partition by offset.
# Use the MC-Fusion label so Windows shows the flashed card as MCFUSION.
mkfs.vfat -n "MCFUSION" --offset="$P1_START" "$IMG"

# Mount the FAT data partition by offset.
mount -o loop,offset="$P1_OFFSET" "$IMG" "$MOUNT_DIR"

# Copy support files
cp -r /files/vendor/support/* "$MOUNT_DIR/"

# Copy kernel and initramfs
cp /home/mr-fusion/linux-socfpga/arch/arm/boot/zImage "$MOUNT_DIR/"

# Download and copy MiSTer release.
curl -fLsS -o "$MOUNT_DIR/release.7z" \
  "https://github.com/MiSTer-devel/SD-Installer-Win64_MiSTer/raw/master/${MISTER_RELEASE}"

# Support MiSTer Scripts
mkdir -p "$MOUNT_DIR/Scripts"

# MC-Fusion support files
mkdir -p "$MOUNT_DIR/mc-fusion"

# Bundle MiSTer Companion Remote script with MC-Fusion
curl -fLsS -o "$MOUNT_DIR/Scripts/companion_remote.sh" \
  "https://raw.githubusercontent.com/Anime0t4ku/mister-companion/main/mister-companion/assets/companion_remote.sh"

chmod +x "$MOUNT_DIR/Scripts/companion_remote.sh" 2>/dev/null || true

# Bundle Update All script with MC-Fusion
curl -fLsS -o "$MOUNT_DIR/Scripts/update_all.sh" \
  "https://raw.githubusercontent.com/theypsilon/Update_All_MiSTer/master/update_all.sh"

chmod +x "$MOUNT_DIR/Scripts/update_all.sh" 2>/dev/null || true

if [[ -f /files/mc-fusion/menu.png ]]; then
  cp /files/mc-fusion/menu.png "$MOUNT_DIR/mc-fusion/menu.png"
else
  echo "WARNING: /files/mc-fusion/menu.png was not found."
fi

cat > "$MOUNT_DIR/mc-fusion/mc-fusion.txt" <<'EOF'
MC-Fusion
mister_companion_ready=true
includes_companion_remote=true
includes_update_all=true
includes_custom_menu_wallpaper=true
first_boot_remote_setup=true
EOF

# Bundle WiFi setup script with MC-Fusion
curl -fLsS -o "$MOUNT_DIR/Scripts/wifi.sh" \
  "https://raw.githubusercontent.com/MiSTer-devel/Scripts_MiSTer/master/other_authors/wifi.sh"

chmod +x "$MOUNT_DIR/Scripts/wifi.sh" 2>/dev/null || true

# Bundle SDL Game Controller database with MC-Fusion
curl -fLsS -o "$MOUNT_DIR/gamecontrollerdb.txt" \
  "https://raw.githubusercontent.com/MiSTer-devel/Distribution_MiSTer/main/linux/gamecontrollerdb/gamecontrollerdb.txt"

# Support custom MiSTer config
mkdir -p "$MOUNT_DIR/config"

# Clean up mounted FAT partition before compressing
sync
umount "$MOUNT_DIR"
trap - EXIT

# Compress the SD card image
cd /files/images
zip -m "$(basename "$ZIP")" mc-fusion.img

echo "Done."
echo "Created: $ZIP"