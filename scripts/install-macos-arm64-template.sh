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

echo "n2n has been installed."
echo "Try: edge --help"
echo "Running edge usually requires sudo, for example: sudo edge ..."
