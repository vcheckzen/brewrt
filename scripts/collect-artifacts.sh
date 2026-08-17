#!/bin/bash
# Collect built packages/firmware into $GITHUB_WORKSPACE/artifacts-*
set -e
cd "$OPENWRT_PATH"

apk_out="$GITHUB_WORKSPACE/artifacts-apk"
firm_out="$GITHUB_WORKSPACE/artifacts-firmware"
mkdir -p "$apk_out" "$firm_out"

n=0
while IFS= read -r -d '' f; do
  cp "$f" "$apk_out/"
  n=$((n+1))
done < <(find bin -type f \( -name '*.apk' -o -name '*.ipk' \) -print0)
echo "collected $n apk/ipk file(s)"

if [ -d bin/targets ]; then
  while IFS= read -r -d '' f; do
    case "$f" in
      *.bin|*.img|*.gz|*.tar|*.7z|sha256sums|*build.config|*version.buildinfo|*feeds.buildinfo|*config.buildinfo)
        cp "$f" "$firm_out/"
        ;;
    esac
  done < <(find bin/targets -type f -print0)
fi

find bin/targets -name 'version.buildinfo' -exec sh -c 'echo "--- version.buildinfo ---"; cat "$1"' _ {} \; 2>/dev/null || true