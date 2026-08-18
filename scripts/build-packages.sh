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
reqs=""
missing=""
for p in $PACKAGES; do
  d="$(resolve_dir "$p")" || true
  if [ -z "$d" ]; then
    missing="$missing $p"
    continue
  fi
  echo "==> $p -> package/$d"
  targets="$targets package/$d/compile"
  reqs="$reqs $p|$d"
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
# Enable it explicitly in .config, then re-run defconfig so the package
# metadata/builddirs pick it up.
#   - bare package name (openssl-util): enable exactly that package; its
#     DEPENDS entries are auto-selected by kconfig ('select') in defconfig.
#   - bare directory name (openssl) or path (package/libs/openssl): enable
#     every package the target Makefile defines (BuildPackage/KernelPackage).
extra_cfg=""
for r in $reqs; do
  p="${r%%|*}"
  d="${r##*|}"
  case "$p" in
    */*) want_all=1 ;;
    *)   want_all=0 ;;
  esac
  mk="package/$d/Makefile"
  [ -f "$mk" ] || continue
  names="$(grep -oE '(BuildPackage,[[:alnum:]_-]+|KernelPackage/[[:alnum:]_-]+)' "$mk" | sed -E 's/.*[,/]//' | sort -u)"
  if [ "$want_all" = 1 ] || ! grep -qE "BuildPackage,${p}[,)]" "$mk"; then
    sel="$names"
  else
    sel="$p"
  fi
  for name in $sel; do
    if ! grep -qE "^CONFIG_PACKAGE_${name}=([ym])" .config; then
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

# On cache hits HiGarfield/cachewrtbuild restores staging_dir/host* and
# staging_dir/tool* (already-built host tools + cross toolchain) but NOT
# build_dir. `make tools/install` / `make toolchain/install` would therefore
# rebuild everything from scratch; rebuilding binutils after the cross musl
# headers are already restored even fails, because binutils ends up including
# musl's sys/types.h (no off64_t) and readelf.c stops compiling. If the cached
# staging dirs are present, reuse them directly and skip those rebuilds.
skip_host=0
skip_toolchain=0
[ -x staging_dir/host/bin/gcc ] && skip_host=1
if [ -n "$(ls staging_dir/tool*/bin/*gcc 2>/dev/null | head -1)" ]; then
  skip_toolchain=1
fi

if [ "$skip_host" = 1 ]; then
  echo "==> [1/4] host tools: restored from cache, skipping tools/install"
else
  echo "==> [1/4] building host tools"
  make -j$(nproc) tools/install || { echo "==> tools failed, retrying -j1 V=s"; make -j1 tools/install V=s; }
fi
if [ "$skip_toolchain" = 1 ]; then
  echo "==> [2/4] cross toolchain: restored from cache, skipping toolchain/install"
else
  echo "==> [2/4] building cross toolchain"
  make -j$(nproc) toolchain/install || { echo "==> toolchain failed, retrying -j1 V=s"; make -j1 toolchain/install V=s; }
fi
echo "==> [3/4] compiling kernel target (needed for kmod packages)"
make -j$(nproc) target/compile || { echo "==> target failed, retrying -j1 V=s"; make -j1 target/compile V=s; }
echo "==> [4/4] compiling requested packages"
make -j$(nproc) $targets V=s || make -j1 $targets V=s