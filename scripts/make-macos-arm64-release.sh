#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage:
  scripts/make-macos-arm64-release.sh --package-url URL [--build-dir DIR] [--dist-dir DIR]

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
