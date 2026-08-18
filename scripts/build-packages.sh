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

# The firmware config only enables packages the firmware ships. A request like
# "openssl-util" (a subpackage of package/libs/openssl) is NOT selected there,
# so `make package/<dir>/compile` would silently skip it and produce no .apk.
# Extract every package name the resolved Makefiles define (BuildPackage /
# KernelPackage) and enable any that aren't explicitly set in .config, then
# re-run defconfig so the metadata/builddirs pick them up.
extra_cfg=""
for t in $targets; do
  d="${t#package/}"
  d="${d%/compile}"
  mk="package/$d/Makefile"
  [ -f "$mk" ] || continue
  for name in $(grep -oE '(BuildPackage,[[:alnum:]_-]+|KernelPackage/[[:alnum:]_-]+)' "$mk" | sed -E 's/.*[,/]//' | sort -u); do
    if ! grep -qE "^(# )?CONFIG_PACKAGE_${name}(=| )" .config; then
      extra_cfg="$extra_cfg CONFIG_PACKAGE_${name}=y"
    fi
  done
done
if [ -n "$extra_cfg" ]; then
  echo "==> enabling in .config:$extra_cfg"
  printf '%s\n' $extra_cfg >> .config
  make defconfig
  # defconfig drops unknown CONFIG_KERNEL_* lines; re-apply the kernel symbol
  # injected by the workflow (nf_conntrack dscpremark ext, see workflow comment).
  echo "CONFIG_KERNEL_NF_CONNTRACK_DSCPREMARK_EXT=y" >> .config
fi

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