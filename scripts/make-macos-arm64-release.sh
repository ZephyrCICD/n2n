#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage:
  scripts/make-macos-arm64-release.sh --package-url URL [--build-dir DIR] [--dist-dir DIR] [--skip-tap-driver]

Example:
  scripts/make-macos-arm64-release.sh \
    --package-url https://example.com/n2n/n2n-macos-arm64.tar.gz

Outputs:
  dist/macos-arm64/n2n-macos-arm64.tar.gz
  dist/macos-arm64/install-n2n-macos-arm64.sh
USAGE
}

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
build_dir="$repo_root/build"
dist_dir="$repo_root/dist/macos-arm64"
package_url=""
tunnelblick_dmg_url="${N2N_TUNNELBLICK_DMG_URL:-https://tunnelblick.net/iprelease/Tunnelblick_8.0.1_build_6301.dmg}"
tunnelblick_dmg_sha256="${N2N_TUNNELBLICK_DMG_SHA256:-5357625ecaa01fb07e0ddffbca93623e1f62314e71132a9c2f35fcbb090a9adc}"
include_tap_driver=1

while [ "$#" -gt 0 ]; do
  case "$1" in
    --package-url)
      package_url="${2:-}"
      shift 2
      ;;
    --build-dir)
      build_dir="$(mkdir -p "$2" && cd "$2" && pwd)"
      shift 2
      ;;
    --dist-dir)
      dist_dir="$(mkdir -p "$2" && cd "$2" && pwd)"
      shift 2
      ;;
    --skip-tap-driver)
      include_tap_driver=0
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

if [ -z "$package_url" ]; then
  echo "--package-url is required." >&2
  usage >&2
  exit 1
fi

if [ "$(uname -s)" != "Darwin" ] || [ "$(uname -m)" != "arm64" ]; then
  echo "This release script must run on an Apple Silicon Mac." >&2
  exit 1
fi

for cmd in cmake file gzip install sed tar; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "Missing required command: $cmd" >&2
    exit 1
  fi
done

include_tunnelblick_tap_driver() {
  for cmd in curl hdiutil shasum; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
      echo "Missing required command: $cmd" >&2
      exit 1
    fi
  done

  driver_tmp="$dist_dir/.tunnelblick-driver"
  dmg="$driver_tmp/Tunnelblick.dmg"
  mountpoint="$driver_tmp/mount"
  mkdir -p "$driver_tmp" "$mountpoint"

  echo "Downloading Tunnelblick TAP/TUN kexts..."
  curl -fL "$tunnelblick_dmg_url" -o "$dmg"
  actual_sha256="$(shasum -a 256 "$dmg" | awk '{print $1}')"
  if [ "$actual_sha256" != "$tunnelblick_dmg_sha256" ]; then
    echo "Tunnelblick disk image SHA256 mismatch." >&2
    echo "Expected: $tunnelblick_dmg_sha256" >&2
    echo "Actual:   $actual_sha256" >&2
    exit 1
  fi

  hdiutil attach "$dmg" -nobrowse -readonly -mountpoint "$mountpoint" >/dev/null

  tap_kext="$(find "$mountpoint" -path '*/tap-notarized.kext' -type d | head -n 1)"
  tun_kext="$(find "$mountpoint" -path '*/tun-notarized.kext' -type d | head -n 1)"

  if [ -z "$tap_kext" ] || [ -z "$tun_kext" ]; then
    hdiutil detach "$mountpoint" >/dev/null || true
    echo "Tunnelblick TAP/TUN kexts were not found in the downloaded disk image." >&2
    exit 1
  fi

  mkdir -p "$stage/drivers/tunnelblick/Extensions" "$stage/drivers/tunnelblick/LaunchDaemons"
  cp -R "$tap_kext" "$stage/drivers/tunnelblick/Extensions/tap.kext"
  cp -R "$tun_kext" "$stage/drivers/tunnelblick/Extensions/tun.kext"

  cat > "$stage/drivers/tunnelblick/LaunchDaemons/net.tunnelblick.tap.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>KeepAlive</key>
  <false/>
  <key>Label</key>
  <string>net.tunnelblick.tap</string>
  <key>ProgramArguments</key>
  <array>
    <string>/sbin/kextload</string>
    <string>/Library/Extensions/tap.kext</string>
  </array>
  <key>RunAtLoad</key>
  <true/>
  <key>UserName</key>
  <string>root</string>
</dict>
</plist>
PLIST

  cat > "$stage/drivers/tunnelblick/LaunchDaemons/net.tunnelblick.tun.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>KeepAlive</key>
  <false/>
  <key>Label</key>
  <string>net.tunnelblick.tun</string>
  <key>ProgramArguments</key>
  <array>
    <string>/sbin/kextload</string>
    <string>/Library/Extensions/tun.kext</string>
  </array>
  <key>RunAtLoad</key>
  <true/>
  <key>UserName</key>
  <string>root</string>
</dict>
</plist>
PLIST

  hdiutil detach "$mountpoint" >/dev/null
  rm -rf "$driver_tmp"
}

mkdir -p "$build_dir"
if [ -f "$build_dir/CMakeCache.txt" ] && ! grep -qx "CMAKE_HOME_DIRECTORY:INTERNAL=$repo_root" "$build_dir/CMakeCache.txt"; then
  echo "Removing stale CMake build directory: $build_dir"
  rm -rf "$build_dir"
  mkdir -p "$build_dir"
fi

cmake -S "$repo_root" -B "$build_dir" \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_POLICY_VERSION_MINIMUM=3.5
cmake --build "$build_dir" --target edge supernode n2n-benchmark

for binary in edge supernode n2n-benchmark; do
  path="$build_dir/$binary"
  if [ ! -x "$path" ]; then
    echo "Build output is missing or not executable: $path" >&2
    exit 1
  fi
  if ! file "$path" | grep -q "Mach-O 64-bit executable arm64"; then
    echo "Build output is not an arm64 macOS binary: $path" >&2
    file "$path" >&2
    exit 1
  fi
done

rm -rf "$dist_dir"
stage="$dist_dir/n2n-macos-arm64"
mkdir -p "$stage/sbin" "$stage/bin" "$stage/share/man/man1" "$stage/share/man/man7" "$stage/share/man/man8"

install -m 755 "$build_dir/edge" "$stage/sbin/edge"
install -m 755 "$build_dir/supernode" "$stage/sbin/supernode"
install -m 755 "$build_dir/n2n-benchmark" "$stage/bin/n2n-benchmark"

gzip -c "$repo_root/edge.8" > "$stage/share/man/man8/edge.8.gz"
gzip -c "$repo_root/supernode.1" > "$stage/share/man/man1/supernode.1.gz"
gzip -c "$repo_root/n2n.7" > "$stage/share/man/man7/n2n.7.gz"

cat > "$stage/README.txt" <<'README'
n2n for Apple Silicon macOS

Installed commands:
  edge
  supernode
  n2n-benchmark

edge usually requires sudo because it creates a virtual network interface.
README

if [ "$include_tap_driver" = "1" ]; then
  include_tunnelblick_tap_driver
fi

(cd "$dist_dir" && tar -czf n2n-macos-arm64.tar.gz n2n-macos-arm64)

escaped_package_url="$(printf '%s\n' "$package_url" | sed 's/[&#]/\\&/g')"
sed "s#@N2N_PACKAGE_URL@#$escaped_package_url#g" \
  "$repo_root/scripts/install-macos-arm64-template.sh" \
  > "$dist_dir/install-n2n-macos-arm64.sh"
chmod +x "$dist_dir/install-n2n-macos-arm64.sh"

echo "Release files are ready:"
echo "  $dist_dir/n2n-macos-arm64.tar.gz"
echo "  $dist_dir/install-n2n-macos-arm64.sh"
echo
echo "Upload both files, then share this command:"
echo "  curl -fsSL ${package_url%/*}/install-n2n-macos-arm64.sh | bash"
