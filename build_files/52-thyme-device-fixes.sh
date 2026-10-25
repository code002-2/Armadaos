#!/bin/bash
# Xiaomi Mi 10S (thyme) device fixes.
#
# Differences vs sheng (52-sheng-device-fixes.sh):
#   touch  is the in-kernel ST FTS driver (st,fts) — a real input device, so
#          there is no userspace THP daemon to install.
#   audio  ships the device-validated UCM2 (conf.d/sm8250/), already vendored
#          in system_files and installed by 40-vendor-system-files.
#   extras there is no sheng deb ecosystem (MiPPS/keyboard/pen) to pull in.
#
# What stays identical to sheng:
#   usb     sshd + an RNDIS USB gadget (Windows enumerates RNDIS natively).
#   steam   steam-now: probe the Steam CDN and fall back to offline mode so a
#           blocked or slow network never strands the user at a download
#           screen.
#   selinux permissive for this variant; see the note at the bottom.
#
# NOTE: everything here installs into /usr/bin or /usr/libexec, never
# /usr/local. On ostree /usr/local is a symlink into /var, so files placed
# there at image build time do not survive deployment.
set -euxo pipefail

# ---------------------------------------------------------------------------
# 1. Remote access: sshd + RNDIS USB gadget
# ---------------------------------------------------------------------------
systemctl enable sshd.service

cat > /usr/libexec/armada-usbgadget <<'GADGET'
#!/bin/bash
set -e
GADGET=/sys/kernel/config/usb_gadget/armada
up() {
  modprobe libcomposite || true
  mkdir -p "$GADGET"
  echo 0x1d6b > "$GADGET/idVendor"; echo 0x0104 > "$GADGET/idProduct"
  mkdir -p "$GADGET/strings/0x409"; echo armada > "$GADGET/strings/0x409/manufacturer"
  echo armada > "$GADGET/strings/0x409/product"
  mkdir -p "$GADGET/configs/c.1/strings/0x409"; echo armada > "$GADGET/configs/c.1/strings/0x409/configuration"
  # RNDIS: Windows enumerates this as a native network adapter (no driver
  # install); ECM is not supported by Windows.
  mkdir -p "$GADGET/functions/rndis.usb0"
  ln -s "$GADGET/functions/rndis.usb0" "$GADGET/configs/c.1/"
  ls /sys/class/udc > "$GADGET/UDC"
  ip link set usb0 up 2>/dev/null || true
  ip addr add 192.168.42.1/24 dev usb0 2>/dev/null || true
}
down() {
  [ -d "$GADGET" ] || return 0
  echo "" > "$GADGET/UDC" || true
  rm -f "$GADGET/configs/c.1/rndis.usb0" || true
  rmdir "$GADGET/functions/rndis.usb0" "$GADGET/configs/c.1/strings/0x409" \
        "$GADGET/configs/c.1" "$GADGET/strings/0x409" "$GADGET" 2>/dev/null || true
}
case "$1" in up) up;; down) down;; esac
GADGET
chmod 0755 /usr/libexec/armada-usbgadget

cat > /usr/lib/systemd/system/armada-usbgadget.service <<'UNIT'
[Unit]
Description=USB Ethernet gadget (RNDIS) for host access
After=network.target

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/libexec/armada-usbgadget up
ExecStop=/usr/libexec/armada-usbgadget down

[Install]
WantedBy=multi-user.target
UNIT
systemctl enable armada-usbgadget.service

# ---------------------------------------------------------------------------
# 2. Steam launcher with an offline fallback
# ---------------------------------------------------------------------------
cat > /usr/bin/steam-now <<'STEAM'
#!/bin/bash
# Launch Steam big picture; probe the Steam CDN briefly and fall back to
# offline mode so a blocked/slow network never strands the user at a
# download screen. The client tree is fully pre-staged in the image.
set -u
if curl -m 3 -sI https://store.steampowered.com >/dev/null 2>&1; then
    exec /usr/bin/steam -steamdeck "$@"
else
    logger -t steam-now "Steam CDN unreachable; starting offline"
    exec /usr/bin/steam -steamdeck -offline "$@"
fi
STEAM
chmod 0755 /usr/bin/steam-now

# ---------------------------------------------------------------------------
# 3. SELinux
#
# The thyme variant boots from a baked Android boot image with no ESP and no
# bootupd, and the image carries container-style labels. Relaxing to
# permissive keeps the phone functional while still logging every denial:
# `ausearch -m avc -ts recent`. To go back to enforcing, relabel the tree on
# the device (`touch /.autorelabel` + reboot) and flip this back.
# ---------------------------------------------------------------------------
if [ -f /etc/selinux/config ]; then
    sed -i 's/^SELINUX=enforcing/SELINUX=permissive/' /etc/selinux/config
    grep '^SELINUX=' /etc/selinux/config || true
fi

echo "==> thyme device fixes done"
