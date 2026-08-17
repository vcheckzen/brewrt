#!/bin/bash
# Reproduces the extra packages the original firmware workflow added:
#   sbwml/openwrt_pkgs (git HEAD on 2025-01-25, pinned) -> luci-app-netspeedtest + speedtest-cli
set -e
cd "$OPENWRT_PATH"

SBWML_PKGS_SHA="${SBWML_PKGS_SHA:-cce5f6547b70464abacb461e64ec7a4ea1391d11}"
dst="package/new/custom"

git init -q "$dst"
git -C "$dst" remote add origin https://github.com/sbwml/openwrt_pkgs.git
git -C "$dst" fetch -q --depth 1 origin "$SBWML_PKGS_SHA"
git -C "$dst" checkout -q FETCH_HEAD

for d in luci-app-netspeedtest speedtest-cli; do
  if [ ! -d "$dst/$d" ]; then
    echo "ERROR: pinned sbwml/openwrt_pkgs commit does not contain '$d'" >&2
    ls -la "$dst"
    exit 1
  fi
done

mv "$dst/luci-app-netspeedtest" package/new
mv "$dst/speedtest-cli" package/new
rm -rf "$dst"