#!/bin/bash
# Resolve package inputs (bare names or source paths) and run the OpenWrt
# compile. In OpenWrt the valid make targets are SOURCE DIRECTORIES
# (e.g. package/libs/openssl/compile), not package/subpackage names, so bare
# names are resolved to their Makefile directory first.
set -e
cd "$OPENWRT_PATH"

resolve_dir() {
  local n="$1" cand
  # path form: package/libs/openssl, libs/openssl, package/feeds/x/y, .../compile
  case "$n" in
    */*)
      n="${n#package/}"
      n="${n%/compile}"
      if [ -d "package/$n" ]; then
        echo "$n"
        return 0
      fi
      echo "ERROR: path does not exist in source tree: package/$n" >&2
      return 1
      ;;
  esac
  for cand in package/* package/*/* package/*/*/* package/feeds/*/* package/feeds/*/*/*; do
    [ -f "$cand/Makefile" ] || continue
    case "$cand" in
      *feeds/base*) continue ;;
    esac
    if [ "$(basename "$cand")" = "$n" ]; then
      echo "${cand#package/}"
      return 0
    fi
    if grep -qE "^PKG_NAME[: ]?=[[:space:]]*${n}([[:space:]]|$)" "$cand/Makefile"; then
      echo "${cand#package/}"
      return 0
    fi
    if grep -qE "BuildPackage,${n}[,)]" "$cand/Makefile"; then
      echo "${cand#package/}"
      return 0
    fi
  done
  return 1
}

targets=""
missing=""
for p in $PACKAGES; do
  d="$(resolve_dir "$p")"
  if [ -z "$d" ]; then
    missing="$missing $p"
    continue
  fi
  echo "==> $p -> package/$d"
  targets="$targets package/$d/compile"
done

if [ -n "$missing" ]; then
  echo "ERROR: cannot resolve package(s):$missing" >&2
  echo "Use the source path form instead, e.g.:" >&2
  echo "  package/libs/openssl        (builds openssl + openssl-util + libopenssl)" >&2
  echo "  package/feeds/packages/aria2" >&2
  echo "  package/feeds/luci/luci-app-passwall" >&2
  exit 1
fi

echo "==> targets: $targets"
echo "CPU cores: $(nproc)"

# A bare `make package/<dir>/compile` does NOT build the host tools, the cross
# toolchain or the kernel by itself - only the full `make` (world) target does.
# Build them explicitly to mirror the original firmware build environment, so
# userspace packages and kmod packages both work. Everything is cached by
# HiGarfield/cachewrtbuild, so on re-runs these are fast no-ops.
echo "==> [1/4] building host tools"
make -j$(nproc) tools/install || { echo "==> tools failed, retrying -j1 V=s"; make -j1 tools/install V=s; }
echo "==> [2/4] building cross toolchain"
make -j$(nproc) toolchain/install || { echo "==> toolchain failed, retrying -j1 V=s"; make -j1 toolchain/install V=s; }
echo "==> [3/4] compiling kernel target (needed for kmod packages)"
make -j$(nproc) target/compile || { echo "==> target failed, retrying -j1 V=s"; make -j1 target/compile V=s; }
echo "==> [4/4] compiling requested packages"
make -j$(nproc) $targets V=s || make -j1 $targets V=s