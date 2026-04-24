# Apple Silicon macOS Release

This repository can package the local macOS arm64 build into two files that are easy to share with non-technical users:

- `n2n-macos-arm64.tar.gz`
- `install-n2n-macos-arm64.sh`
- `uninstall-n2n-macos-arm64.sh`

Build the package on an Apple Silicon Mac:

```bash
scripts/make-macos-arm64-release.sh \
  --package-url https://example.com/n2n/n2n-macos-arm64.tar.gz
```

Upload both files from `dist/macos-arm64/` to the same directory on your file server, GitHub Release, or internal object storage.

Give users this command:

```bash
curl -fsSL https://example.com/n2n/install-n2n-macos-arm64.sh | bash
```

The installer copies `edge` and `supernode` to `/usr/local/sbin`, creates convenience links in `/usr/local/bin`, and installs the man pages. Users can override the install prefix:

```bash
curl -fsSL https://example.com/n2n/install-n2n-macos-arm64.sh | N2N_INSTALL_PREFIX="$HOME/.local" bash
```

The release package includes Tunnelblick's notarized TAP/TUN kexts, but it does not install the Tunnelblick app. The installer checks for `/dev/tap0`; if TAP support is missing, it installs the bundled `tap.kext` and `tun.kext` plus launch daemons. On Apple Silicon macOS, the final system extension approval cannot be fully automated; the user may need to approve the Tunnelblick system extension in System Settings and restart.

To skip TAP/TUN kext setup:

```bash
curl -fsSL https://example.com/n2n/install-n2n-macos-arm64.sh | N2N_SKIP_TAP_DRIVER=1 bash
```

`edge` usually needs to run with `sudo` because it creates a virtual network interface:

```bash
sudo edge --help
```

macOS may still require TUN/TAP support and a one-time approval in System Settings, depending on the target macOS version and your n2n configuration.

## GitHub Release

The `macOS arm64 Release` workflow publishes these files automatically when you push a version tag:

```bash
git tag v3.0.0-m1.1
git push origin v3.0.0-m1.1
```

After the workflow finishes, give users the generated installer command:

```bash
curl -fsSL https://github.com/zephyrcicd/n2n/releases/download/v3.0.0-m1.1/install-n2n-macos-arm64.sh | bash
```

The generated uninstaller command is:

```bash
curl -fsSL https://github.com/zephyrcicd/n2n/releases/download/v3.0.0-m1.1/uninstall-n2n-macos-arm64.sh | bash
```

To uninstall n2n while keeping TAP/TUN kexts:

```bash
curl -fsSL https://github.com/zephyrcicd/n2n/releases/download/v3.0.0-m1.1/uninstall-n2n-macos-arm64.sh | N2N_KEEP_TAP_DRIVER=1 bash
```
