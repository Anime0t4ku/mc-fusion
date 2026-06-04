#!/bin/sh
# Copyright 2024 Michael Smith <m@hacktheplanet.be> and contributors

# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License version 3 as published
# by the Free Software Foundation.

# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.

# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston,
# MA 02110-1301, USA.

# This script is used as an init script and should only
# run on startup, not on shutdown.
if [ ! "$1" = "start" ]; then
  exit 0
fi

# Backup the MiSTer release files to memory.
mkdir -p /mnt/release /tmp/release
mount -r /dev/mmcblk0p1 /mnt/release

## Show splash screen
fbv -fr /mnt/release/splash.png &
cd /tmp/release
7zr x /mnt/release/release.7z

## Custom scripts support
mkdir -p /tmp/release/files/Scripts
if [ -d /mnt/release/Scripts ]; then
  cp -a /mnt/release/Scripts/. /tmp/release/files/Scripts/
  chmod +x /tmp/release/files/Scripts/*.sh 2>/dev/null || true
fi

## MC-Fusion marker support
if [ -f /mnt/release/mc-fusion/mc-fusion.txt ]; then
  cp /mnt/release/mc-fusion/mc-fusion.txt /tmp/release/files/mc-fusion.txt
fi

## MC-Fusion menu wallpaper support
if [ -f /mnt/release/mc-fusion/menu.png ]; then
  cp /mnt/release/mc-fusion/menu.png /tmp/release/files/menu.png
fi

## MC-Fusion Companion Remote first-boot setup
mkdir -p /tmp/release/files/linux

if [ ! -f /tmp/release/files/linux/user-startup.sh ]; then
  cat > /tmp/release/files/linux/user-startup.sh <<'EOF'
#!/bin/sh
EOF
fi

if ! grep -F "# MC-Fusion Companion Remote First Boot BEGIN" /tmp/release/files/linux/user-startup.sh >/dev/null 2>&1; then
  cat >> /tmp/release/files/linux/user-startup.sh <<'EOF'

# MC-Fusion Companion Remote First Boot BEGIN
MC_FUSION_REMOTE_DONE="/media/fat/Scripts/.config/companion_remote/.mc_fusion_first_boot_done"

if [ ! -f "$MC_FUSION_REMOTE_DONE" ] && [ -x /media/fat/Scripts/companion_remote.sh ]; then
  /media/fat/Scripts/companion_remote.sh install --unattended >/dev/null 2>&1
  /media/fat/Scripts/companion_remote.sh enable-boot --unattended >/dev/null 2>&1
  /media/fat/Scripts/companion_remote.sh start --unattended >/dev/null 2>&1

  # Enable Samba once on first boot.
  if [ -f /media/fat/linux/_samba.sh ] && [ ! -f /media/fat/linux/samba.sh ]; then
    mv /media/fat/linux/_samba.sh /media/fat/linux/samba.sh
    chmod +x /media/fat/linux/samba.sh 2>/dev/null || true
  fi

  # Enable the custom menu background once by sending F1 after the MiSTer menu has loaded.
  (
    sleep 15

    if [ -e /dev/uinput ] || modprobe uinput >/dev/null 2>&1; then
      python3 - <<'PYEOF' >/dev/null 2>&1
import os
import time
import fcntl
import struct

UINPUT_PATH = "/dev/uinput"

UI_DEV_CREATE = 0x5501
UI_DEV_DESTROY = 0x5502
UI_SET_EVBIT = 0x40045564
UI_SET_KEYBIT = 0x40045565

EV_SYN = 0x00
EV_KEY = 0x01
SYN_REPORT = 0
BUS_USB = 0x03

KEY_F1 = 59

def input_event(event_type, code, value):
    now = time.time()
    sec = int(now)
    usec = int((now - sec) * 1000000)
    return struct.pack("llHHi", sec, usec, event_type, code, value)

fd = os.open(UINPUT_PATH, os.O_WRONLY | os.O_NONBLOCK)

fcntl.ioctl(fd, UI_SET_EVBIT, EV_KEY)
fcntl.ioctl(fd, UI_SET_KEYBIT, KEY_F1)

data = bytearray(1116)
name = b"MC-Fusion First Boot Keyboard"
data[0:len(name)] = name
struct.pack_into("HHHH", data, 80, BUS_USB, 0x4D43, 0xF001, 1)

os.write(fd, data)
fcntl.ioctl(fd, UI_DEV_CREATE, 0)
time.sleep(0.5)

os.write(fd, input_event(EV_KEY, KEY_F1, 1))
os.write(fd, input_event(EV_SYN, SYN_REPORT, 0))
time.sleep(0.08)
os.write(fd, input_event(EV_KEY, KEY_F1, 0))
os.write(fd, input_event(EV_SYN, SYN_REPORT, 0))

time.sleep(0.2)
fcntl.ioctl(fd, UI_DEV_DESTROY, 0)
os.close(fd)
PYEOF
    fi
  ) &

  mkdir -p /media/fat/Scripts/.config/companion_remote
  touch "$MC_FUSION_REMOTE_DONE"

  TMP_STARTUP="/media/fat/linux/user-startup.sh.tmp.$$"
  awk '
    /^# MC-Fusion Companion Remote First Boot BEGIN$/ { skip = 1; next }
    /^# MC-Fusion Companion Remote First Boot END$/ { skip = 0; next }
    skip == 1 { next }
    { print }
  ' /media/fat/linux/user-startup.sh > "$TMP_STARTUP" && mv "$TMP_STARTUP" /media/fat/linux/user-startup.sh

  chmod +x /media/fat/linux/user-startup.sh
fi
# MC-Fusion Companion Remote First Boot END
EOF
fi

chmod +x /tmp/release/files/linux/user-startup.sh

## Custom wpa_supplicant.conf support
if [ -f /mnt/release/wpa_supplicant.conf ]; then
  cp /mnt/release/wpa_supplicant.conf /tmp/release/files/linux
fi

## Custom samba.sh support
if [ -f /mnt/release/samba.sh ]; then
  cp /mnt/release/samba.sh /tmp/release/files/linux
fi

## Custom config support
cp -r /mnt/release/config /tmp/release/files/

## Generate a locally administered unicast MAC address for ethernet NIC
MAC=$(hexdump -n 6 -ve '1/1 "%.2x "' /dev/urandom | \
  awk -v a="2,6,a,e" -v r="$RANDOM" \
  'BEGIN { srand(r); }
  NR==1 { split(a,b,",");
  r=int(rand()*4+1);
  printf("%s%s:%s:%s:%s:%s:%s\n", substr($1,0,1),b[r],$2,$3,$4,$5,$6); }' | \
  tr "[:lower:]" "[:upper:]")
mkdir -p /tmp/release/files/linux
echo "ethaddr=${MAC}" > /tmp/release/files/linux/u-boot.txt

## SDL Game Controller DB support
mkdir -p /tmp/release/files/linux/gamecontrollerdb
cp -r /mnt/release/gamecontrollerdb.txt /tmp/release/files/linux/gamecontrollerdb/

umount /mnt/release

# Re-partition the SD card:
# 1. Create an ExFAT partition spanning almost the entire SD card.
# 2. Create a small 0xA2 type partition at the end to store the bootloader.
DATA_PARTITION_SIZE=$(($( cat /sys/block/mmcblk0/size ) - 8192))
sfdisk --force /dev/mmcblk0 << EOF
; ${DATA_PARTITION_SIZE}; 07
; ; a2
EOF

# Create the MiSTer_Data partition.
mkfs.exfat -n "MiSTer_Data" /dev/mmcblk0p1

# Mount the MiSTer_Data partition.
mkdir -p /mnt/data
mount.exfat-fuse /dev/mmcblk0p1 /mnt/data

# Copy the MiSTer release files to the MiSTer_Data partition.
cp -r /tmp/release/files/* /mnt/data/
umount /mnt/data

# Write the MiSTer bootloader.
dd if="/tmp/release/files/linux/uboot.img" of="/dev/mmcblk0p2" bs=64k
sync

reboot