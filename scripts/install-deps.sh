#!/bin/bash
# Install host build dependencies on an Ubuntu (22.04/24.04) GitHub runner.
# The actual cross toolchain (gcc/musl/binutils) is compiled from the pinned
# source tree, so host packages only need to build host tools.
set -e
export DEBIAN_FRONTEND=noninteractive

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