#!/usr/bin/env bash
# Download pinned CLI tools into ./bin (linux/darwin, amd64/arm64). No sudo needed.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BIN="$ROOT/bin"; mkdir -p "$BIN"

K3D=v5.9.0
KUSTOMIZE=v5.8.3
GH=2.103.3
KARGO=v1.12.5
YQ=v4.54.1

os=$(uname -s | tr '[:upper:]' '[:lower:]')
arch=$(uname -m); case $arch in x86_64) arch=amd64;; aarch64|arm64) arch=arm64;; esac
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT

[[ -x $BIN/k3d ]] || curl -fsSL -o "$BIN/k3d" "https://github.com/k3d-io/k3d/releases/download/$K3D/k3d-$os-$arch"
[[ -x $BIN/kargo ]] || curl -fsSL -o "$BIN/kargo" "https://github.com/akuity/kargo/releases/download/$KARGO/kargo-$os-$arch"
[[ -x $BIN/yq ]] || curl -fsSL -o "$BIN/yq" "https://github.com/mikefarah/yq/releases/download/$YQ/yq_${os}_${arch}"
[[ -x $BIN/kustomize ]] || curl -fsSL "https://github.com/kubernetes-sigs/kustomize/releases/download/kustomize%2F$KUSTOMIZE/kustomize_${KUSTOMIZE}_${os}_${arch}.tar.gz" | tar -xz -C "$BIN"
if [[ ! -x $BIN/gh ]]; then
  if [[ $os == darwin ]]; then
    curl -fsSL -o "$tmp/gh.zip" "https://github.com/cli/cli/releases/download/v$GH/gh_${GH}_macOS_${arch}.zip"
    unzip -q "$tmp/gh.zip" -d "$tmp" && mv "$tmp/gh_${GH}_macOS_${arch}/bin/gh" "$BIN/"
  else
    curl -fsSL "https://github.com/cli/cli/releases/download/v$GH/gh_${GH}_linux_${arch}.tar.gz" | tar -xz -C "$tmp"
    mv "$tmp/gh_${GH}_linux_${arch}/bin/gh" "$BIN/"
  fi
fi
chmod +x "$BIN"/*
echo "tools in $BIN: $(ls "$BIN" | tr '\n' ' ')"
echo "also required on PATH: docker, kubectl, helm, git, jq, curl, openssl"
