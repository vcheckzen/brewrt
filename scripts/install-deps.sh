#!/bin/bash
# Install host build dependencies on an Ubuntu (22.04/24.04) GitHub runner.
# GitHub hosted runners ship with a nearly-full root filesystem, so we free up
# preinstalled junk FIRST (the original openwrt-ci workflow did the same),
# then install what the build actually needs.
set -e
export DEBIAN_FRONTEND=noninteractive

echo "== root disk before cleanup =="
df -h / | tail -n1

# Free space on the root filesystem (where /usr lives)
docker rmi $(docker images -q) >/dev/null 2>&1 || true
sudo rm -rf /usr/share/dotnet /etc/apt/sources.list.d /usr/local/lib/android \
  /opt/ghc /usr/local/share/powershell "$AGENT_TOOLSDIRECTORY" >/dev/null 2>&1 || true
sudo apt-get -qq purge -y azure-cli 'ghc*' 'zulu*' 'llvm*' firefox 'google-chrome*' \
  'dotnet*' powershell 'openjdk*' 'mongodb*' 'moby*' 'containerd*' >/dev/null 2>&1 || true
sudo apt-get -qq autoremove --purge >/dev/null 2>&1 || true
sudo apt-get -qq clean >/dev/null 2>&1 || true

echo "== root disk after cleanup =="
df -h / | tail -n1

sudo apt-get -qq update

# ncurses5 dev package is named differently on newer Ubuntu releases
if ! sudo apt-get -qq install -y --no-install-recommends libncurses5-dev; then
  sudo apt-get -qq install -y --no-install-recommends libncurses-dev
fi

sudo apt-get -qq install -y --no-install-recommends \
  build-essential clang flex bison g++ gawk gettext git \
  libssl-dev python3 python3-setuptools python3-pyelftools \
  rsync swig unzip zlib1g-dev file wget curl quilt xz-utils time \
  cpio bzip2 pkg-config libelf-dev nodejs gperf subversion

echo "== root disk after apt =="
df -h / | tail -n1