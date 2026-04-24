#!/usr/bin/env bash
set -euo pipefail

PREFIX="${N2N_INSTALL_PREFIX:-/usr/local}"

if [ "$(uname -s)" != "Darwin" ]; then
  echo "This uninstaller is only for macOS." >&2
  exit 1
fi

if [ "$(id -u)" -eq 0 ]; then
  SUDO=""
else
  SUDO="sudo"
fi

remove_path() {
  path="$1"
  if [ -e "$path" ] || [ -L "$path" ]; then
    $SUDO rm -rf "$path"
  fi
}

echo "Stopping TAP/TUN launch daemons..."
$SUDO launchctl unload -w /Library/LaunchDaemons/net.tunnelblick.tap.plist 2>/dev/null || true
$SUDO launchctl unload -w /Library/LaunchDaemons/net.tunnelblick.tun.plist 2>/dev/null || true

echo "Unloading TAP/TUN kexts..."
$SUDO /sbin/kextunload /Library/Extensions/tap.kext 2>/dev/null || true
$SUDO /sbin/kextunload /Library/Extensions/tun.kext 2>/dev/null || true

echo "Removing n2n commands..."
remove_path "$PREFIX/sbin/edge"
remove_path "$PREFIX/sbin/supernode"
remove_path "$PREFIX/bin/n2n-benchmark"

if [ -L "$PREFIX/bin/edge" ]; then
  remove_path "$PREFIX/bin/edge"
fi

if [ -L "$PREFIX/bin/supernode" ]; then
  remove_path "$PREFIX/bin/supernode"
fi

echo "Removing n2n man pages..."
remove_path "$PREFIX/share/man/man1/supernode.1.gz"
remove_path "$PREFIX/share/man/man7/n2n.7.gz"
remove_path "$PREFIX/share/man/man8/edge.8.gz"

if [ "${N2N_KEEP_TAP_DRIVER:-0}" = "1" ]; then
  echo "Keeping TAP/TUN kexts because N2N_KEEP_TAP_DRIVER=1."
else
  echo "Removing bundled TAP/TUN kexts..."
  remove_path /Library/LaunchDaemons/net.tunnelblick.tap.plist
  remove_path /Library/LaunchDaemons/net.tunnelblick.tun.plist
  remove_path /Library/Extensions/tap.kext
  remove_path /Library/Extensions/tun.kext
fi

echo "n2n has been uninstalled."
echo "Restart the Mac if TAP/TUN devices are still visible or macOS asks for it."
