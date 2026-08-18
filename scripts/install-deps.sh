#!/bin/bash
# Install host build dependencies on an Ubuntu (22.04/24.04) GitHub runner.
# GitHub hosted runners ship with a nearly-full root filesystem, so we free up
# preinstalled junk FIRST (the original openwrt-ci workflow did the same),
# then install what the build actually needs.
#
# NOTE: do NOT delete /etc/apt/sources.list.d here. On ubuntu-24.04 all apt
# sources live there (deb822 format, e.g. ubuntu.sources); deleting the dir
# removes the Ubuntu repos entirely ("no installation candidate" errors).
#
# Apt is hardened: on some runner instances apt-get update/install silently
# hung for hours (root fs 100% full at boot wedges apt-daily/unattended-upgrades,
# and a stalled mirror has no timeout by default). We stop the background
# updaters, apply network timeouts/retries and wrap every apt command in a hard
# timeout so the job fails fast and visibly instead of hitting the 6h limit.
set -e
export DEBIAN_FRONTEND=noninteractive

APT_NET=(-o Acquire::Retries=5 -o Acquire::http::Timeout=30 -o Acquire::https::Timeout=30 -o Acquire::ftp::Timeout=30)
APT_OPTS=(-y --no-install-recommends)

# apt_run <label> <timeout-seconds> <apt-get args...>
apt_run() {
  local label="$1" tmo="$2" i
  shift 2
  for i in 1 2 3; do
    echo "== apt-get $label (attempt $i/3) =="
    if timeout "$tmo" sudo apt-get "${APT_NET[@]}" "$@"; then
      return 0
    fi
    echo "== apt-get $label attempt $i failed (exit $?), retrying in 5s =="
    sleep 5
  done
  echo "ERROR: apt-get $label failed after 3 attempts" >&2
  return 1
}

echo "== root disk before cleanup =="
df -h / | tail -n1

# Free space on the root filesystem (where /usr lives)
docker rmi $(docker images -q) >/dev/null 2>&1 || true
sudo rm -rf /usr/share/dotnet /usr/local/lib/android \
  /opt/ghc /usr/local/share/powershell "$AGENT_TOOLSDIRECTORY" >/dev/null 2>&1 || true
sudo apt-get -qq purge -y azure-cli 'ghc*' 'zulu*' 'llvm*' firefox 'google-chrome*' \
  'dotnet*' powershell 'openjdk*' 'mongodb*' 'moby*' 'containerd*' >/dev/null 2>&1 || true
sudo apt-get -qq autoremove --purge >/dev/null 2>&1 || true
sudo apt-get -qq clean >/dev/null 2>&1 || true

echo "== root disk after cleanup =="
df -h / | tail -n1

# Stop background apt jobs that may hold the dpkg lock forever.
sudo systemctl stop apt-daily.service apt-daily-upgrade.service unattended-upgrades 2>/dev/null || true
sudo pkill -9 -f 'unattended-upgrade' 2>/dev/null || true
sudo pkill -9 -f 'apt.systemd.daily' 2>/dev/null || true
sleep 2
sudo timeout 300 dpkg --configure -a || true

apt_run update 600 update

# ncurses5 dev package is named differently on newer Ubuntu releases
if ! apt_run install-ncurses5 900 install "${APT_OPTS[@]}" libncurses5-dev; then
  apt_run install-ncurses 900 install "${APT_OPTS[@]}" libncurses-dev
fi

apt_run install-main 900 install "${APT_OPTS[@]}" \
  build-essential clang flex bison g++ gawk gettext git \
  libssl-dev python3 python3-setuptools python3-pyelftools \
  rsync swig unzip zlib1g-dev file wget curl quilt xz-utils time \
  cpio bzip2 pkg-config libelf-dev nodejs gperf subversion

echo "== root disk after apt =="
df -h / | tail -n1