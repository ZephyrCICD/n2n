#!/usr/bin/env bash
set -euo pipefail

DEFAULT_PACKAGE_URL="@N2N_PACKAGE_URL@"
UNCONFIGURED_PACKAGE_URL="@""N2N_PACKAGE_URL@"
PACKAGE_URL="${N2N_MACOS_ARM64_URL:-$DEFAULT_PACKAGE_URL}"
PREFIX="${N2N_INSTALL_PREFIX:-/usr/local}"

if [ "$(uname -s)" != "Darwin" ]; then
  echo "This installer is only for macOS." >&2
  exit 1
fi

if [ "$(uname -m)" != "arm64" ]; then
  echo "This installer is only for Apple Silicon Macs." >&2
  exit 1
fi

if [ "$PACKAGE_URL" = "$UNCONFIGURED_PACKAGE_URL" ]; then
  echo "Package URL is not configured. Rebuild the installer with --package-url." >&2
  exit 1
fi

for cmd in curl tar mktemp install; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "Missing required command: $cmd" >&2
    exit 1
  fi
done

if [ "$(id -u)" -eq 0 ] || [ -w "$PREFIX" ] || { [ ! -e "$PREFIX" ] && [ -w "$(dirname "$PREFIX")" ]; }; then
  SUDO=""
else
  SUDO="sudo"
fi

tmpdir="$(mktemp -d)"
cleanup() {
  rm -rf "$tmpdir"
}
trap cleanup EXIT

tap_is_ready() {
  [ -c /dev/tap0 ]
}

print_tap_approval_instructions() {
  cat <<'INSTRUCTIONS'

TAP/TUN was installed, but macOS has not made /dev/tap0 available yet.
On Apple Silicon Macs this last approval step cannot be automated by this installer.

If macOS reports "not approved to load" for net.tunnelblick.tap or net.tunnelblick.tun:

1. Open System Settings > Privacy & Security.
2. In the Security section, click Details next to "Some system software requires your attention".
3. Enable "Jonathan Bullard". This is the developer signature for Tunnelblick's TAP/TUN kexts.
4. Click OK and enter an administrator password if prompted.
5. Restart the Mac.

If the Details/Allow control does not appear, trigger the approval prompt again:

  sudo kmutil load -p /Library/Extensions/tap.kext

Then return to System Settings > Privacy & Security immediately.

On Apple Silicon, if macOS still refuses to show the approval UI, boot into macOS Recovery,
open Startup Security Utility, choose Reduced Security, and enable user management of
kernel extensions from identified developers. Restart macOS and repeat the approval steps above.

After restart, verify TAP support with:

  sh -c 'ls -l /dev/tap* 2>/dev/null || true'
  kextstat | grep -i tunnelblick

INSTRUCTIONS
}

ensure_tap_support() {
  if tap_is_ready; then
    echo "TAP support is already available."
    return
  fi

  if [ "${N2N_SKIP_TAP_DRIVER:-0}" = "1" ]; then
    echo "TAP support was not found, and driver setup was skipped."
    return
  fi

  driver_root="$root/drivers/tunnelblick"
  if [ ! -d "$driver_root/Extensions/tap.kext" ] || [ ! -d "$driver_root/Extensions/tun.kext" ]; then
    echo "TAP support was not found, and this package does not include TAP/TUN kexts." >&2
    exit 1
  fi

  echo "TAP support was not found. Installing bundled TAP/TUN system extensions..."
  $SUDO rm -rf /Library/Extensions/tap.kext /Library/Extensions/tun.kext
  $SUDO cp -R "$driver_root/Extensions/tap.kext" /Library/Extensions/tap.kext
  $SUDO cp -R "$driver_root/Extensions/tun.kext" /Library/Extensions/tun.kext
  $SUDO chown -R root:wheel /Library/Extensions/tap.kext /Library/Extensions/tun.kext
  $SUDO chmod -R go-w /Library/Extensions/tap.kext /Library/Extensions/tun.kext

  $SUDO install -m 644 "$driver_root/LaunchDaemons/net.tunnelblick.tap.plist" /Library/LaunchDaemons/net.tunnelblick.tap.plist
  $SUDO install -m 644 "$driver_root/LaunchDaemons/net.tunnelblick.tun.plist" /Library/LaunchDaemons/net.tunnelblick.tun.plist
  $SUDO chown root:wheel /Library/LaunchDaemons/net.tunnelblick.tap.plist /Library/LaunchDaemons/net.tunnelblick.tun.plist

  kext_log="$tmpdir/tap-kext-approval.log"
  : > "$kext_log"

  if command -v kmutil >/dev/null 2>&1; then
    $SUDO kmutil load -p /Library/Extensions/tap.kext >>"$kext_log" 2>&1 || true
    $SUDO kmutil load -p /Library/Extensions/tun.kext >>"$kext_log" 2>&1 || true
  fi

  $SUDO /sbin/kextload /Library/Extensions/tap.kext >>"$kext_log" 2>&1 || true
  $SUDO /sbin/kextload /Library/Extensions/tun.kext >>"$kext_log" 2>&1 || true
  $SUDO launchctl load -w /Library/LaunchDaemons/net.tunnelblick.tap.plist 2>/dev/null || true
  $SUDO launchctl load -w /Library/LaunchDaemons/net.tunnelblick.tun.plist 2>/dev/null || true
  $SUDO launchctl kickstart -k system/net.tunnelblick.tap 2>/dev/null || true
  $SUDO launchctl kickstart -k system/net.tunnelblick.tun 2>/dev/null || true

  if tap_is_ready; then
    echo "TAP support is ready."
  else
    if [ -s "$kext_log" ]; then
      echo
      echo "macOS TAP/TUN load output:"
      sed 's/^/  /' "$kext_log"
    fi
    print_tap_approval_instructions
  fi
}

archive="$tmpdir/n2n-macos-arm64.tar.gz"
payload="$tmpdir/payload"

echo "Downloading n2n for Apple Silicon..."
curl -fL "$PACKAGE_URL" -o "$archive"

mkdir -p "$payload"
tar -xzf "$archive" -C "$payload"

root="$payload/n2n-macos-arm64"
if [ ! -x "$root/sbin/edge" ] || [ ! -x "$root/sbin/supernode" ]; then
  echo "The downloaded package is missing edge or supernode." >&2
  exit 1
fi

echo "Installing n2n into $PREFIX..."
$SUDO install -d "$PREFIX/sbin" "$PREFIX/bin"
$SUDO install -m 755 "$root/sbin/edge" "$PREFIX/sbin/edge"
$SUDO install -m 755 "$root/sbin/supernode" "$PREFIX/sbin/supernode"

if [ -x "$root/bin/n2n-benchmark" ]; then
  $SUDO install -m 755 "$root/bin/n2n-benchmark" "$PREFIX/bin/n2n-benchmark"
fi

$SUDO ln -sf "$PREFIX/sbin/edge" "$PREFIX/bin/edge"
$SUDO ln -sf "$PREFIX/sbin/supernode" "$PREFIX/bin/supernode"

if [ -d "$root/share/man" ]; then
  $SUDO install -d "$PREFIX/share/man/man1" "$PREFIX/share/man/man7" "$PREFIX/share/man/man8"
  if [ -f "$root/share/man/man1/supernode.1.gz" ]; then
    $SUDO install -m 644 "$root/share/man/man1/supernode.1.gz" "$PREFIX/share/man/man1/supernode.1.gz"
  fi
  if [ -f "$root/share/man/man7/n2n.7.gz" ]; then
    $SUDO install -m 644 "$root/share/man/man7/n2n.7.gz" "$PREFIX/share/man/man7/n2n.7.gz"
  fi
  if [ -f "$root/share/man/man8/edge.8.gz" ]; then
    $SUDO install -m 644 "$root/share/man/man8/edge.8.gz" "$PREFIX/share/man/man8/edge.8.gz"
  fi
fi

ensure_tap_support

echo "n2n has been installed."
echo "Try: edge --help"
echo "Running edge usually requires sudo, for example: sudo edge ..."
