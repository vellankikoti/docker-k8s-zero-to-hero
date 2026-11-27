#!/bin/sh
# install-terraform.sh [VERSION]: put the terraform command on your machine, without sudo and without a package manager.
# Downloads the official release zip from releases.hashicorp.com, checks its SHA-256, and installs it in ~/.local/bin.
set -eu
V=${1:-1.9.8}
BIN=${INSTALL_DIR:-$HOME/.local/bin}
if command -v terraform >/dev/null 2>&1 && terraform version 2>/dev/null | head -1 | grep -q "v$V"; then echo "✔ terraform $V is already installed"; exit 0; fi
case "$(uname -s)" in Linux) OS=linux ;; Darwin) OS=darwin ;; *) echo "✖ unsupported OS $(uname -s): install Terraform from https://developer.hashicorp.com/terraform/install" >&2; exit 1 ;; esac
case "$(uname -m)" in x86_64|amd64) ARCH=amd64 ;; aarch64|arm64) ARCH=arm64 ;; *) echo "✖ unsupported CPU $(uname -m)" >&2; exit 1 ;; esac
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
URL=https://releases.hashicorp.com/terraform/$V
Z=terraform_${V}_${OS}_${ARCH}.zip
echo "▶ downloading terraform $V ($OS/$ARCH)"
curl -fsSL -o "$T/$Z" "$URL/$Z" || { echo "✖ download failed: $URL/$Z (no internet, or releases.hashicorp.com is blocked)" >&2; exit 1; }
curl -fsSL -o "$T/SUMS" "$URL/terraform_${V}_SHA256SUMS"
want=$(grep " $Z\$" "$T/SUMS" | cut -d' ' -f1)
if command -v sha256sum >/dev/null; then got=$(sha256sum "$T/$Z" | cut -d' ' -f1); else got=$(shasum -a 256 "$T/$Z" | cut -d' ' -f1); fi
[ -n "$want" ] && [ "$want" = "$got" ] || { echo "✖ checksum mismatch: refusing to install" >&2; exit 1; }
mkdir -p "$BIN"
if command -v unzip >/dev/null; then unzip -qo "$T/$Z" terraform -d "$BIN"; else python3 -c "import zipfile,sys;zipfile.ZipFile(sys.argv[1]).extract('terraform',sys.argv[2])" "$T/$Z" "$BIN"; fi
chmod +x "$BIN/terraform"
echo "✔ installed $BIN/terraform"
case ":$PATH:" in *":$BIN:"*) ;; *) echo "• add it to your PATH:  export PATH=\"$BIN:\$PATH\"   (put that line in ~/.bashrc to keep it)" ;; esac
