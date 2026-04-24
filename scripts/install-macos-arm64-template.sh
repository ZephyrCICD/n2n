#!/usr/bin/env bash
set -euo pipefail

DEFAULT_PACKAGE_URL="@N2N_PACKAGE_URL@"
UNCONFIGURED_PACKAGE_URL="@""N2N_PACKAGE_URL@"
PACKAGE_URL="${N2N_MACOS_ARM64_URL:-$DEFAULT_PACKAGE_URL}"
PREFIX="${N2N_INSTALL_PREFIX:-/usr/local}"
TUNNELBLICK_DMG_URL="${N2N_TUNNELBLICK_DMG_URL:-https://tunnelblick.net/release/Latest_Tunnelblick_Stable.dmg}"

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

install_tunnelblick_from_dmg() {
  for cmd in hdiutil ditto; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
      echo "Missing required command: $cmd" >&2
      exit 1
    fi
  done

  dmg="$tmpdir/Tunnelblick.dmg"
  mountpoint="$tmpdir/Tunnelblick"

  echo "Downloading Tunnelblick for TAP support..."
  curl -fL "$TUNNELBLICK_DMG_URL" -o "$dmg"

  mkdir -p "$mountpoint"
  hdiutil attach "$dmg" -nobrowse -readonly -mountpoint "$mountpoint" >/dev/null

  app_path="$(find "$mountpoint" -maxdepth 2 -name 'Tunnelblick.app' -type d | head -n 1)"
  if [ -z "$app_path" ]; then
    echo "Tunnelblick.app was not found in the downloaded disk image." >&2
    exit 1
  fi

  $SUDO rm -rf /Applications/Tunnelblick.app
  $SUDO ditto "$app_path" /Applications/Tunnelblick.app
  hdiutil detach "$mountpoint" >/dev/null
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

  echo "TAP support was not found. Installing Tunnelblick to provide the TAP system extension..."

  if [ ! -d /Applications/Tunnelblick.app ]; then
    if command -v brew >/dev/null 2>&1; then
      brew install --cask tunnelblick || install_tunnelblick_from_dmg
    else
      install_tunnelblick_from_dmg
    fi
  fi

  echo "Opening Tunnelblick so macOS can finish TAP system extension approval."
  open -a Tunnelblick || open /Applications/Tunnelblick.app || true

  if tap_is_ready; then
    echo "TAP support is ready."
  else
    echo
    echo "One more macOS approval step may be required:"
    echo "1. In Tunnelblick, open Utilities and install Tun and Tap system extensions."
    echo "2. In System Settings > Privacy & Security, allow the Tunnelblick system extension if macOS asks."
    echo "3. Restart the Mac if macOS asks, then run your n2n edge command again."
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
