#!/bin/sh
# Build FreeSWITCH and its non-Debian dependencies (sofia-sip, spandsp) into
# /opt/softdial/freeswitch inside a disposable debian build container.
#
# Usage: build.sh <Release|Debug>
#
# Expects sibling checkouts in the working directory:
#   fs-build/    this repository
#   freeswitch/  signalwire/freeswitch
#   sofia-sip/   freeswitch/sofia-sip
#   spandsp/     freeswitch/spandsp
set -eux

CONFIG="${1:-Release}"
PREFIX=/opt/softdial/freeswitch
JOBS="$(nproc)"

case "$CONFIG" in
  Release) OPT_CFLAGS="-O2 -g" ;;
  Debug)   OPT_CFLAGS="-O0 -ggdb3" ;;
  *) echo "unknown configuration: $CONFIG" >&2; exit 1 ;;
esac

# Absolute rpath: Softdial's Linux layout is a fixed extract location, so the
# bundled sofia-sip/spandsp libs are always found without ldconfig or
# LD_LIBRARY_PATH. A versioned-dir + symlink upgrade scheme still works as
# long as the symlink provides this path.
export CFLAGS="$OPT_CFLAGS"
export CXXFLAGS="$OPT_CFLAGS"
export LDFLAGS="-Wl,-rpath,$PREFIX/lib"

mkdir -p "$PREFIX"

build_autotools_dep() {
  # $1 = source dir
  (
    cd "$1"
    if [ ! -x ./configure ]; then
      if [ -x ./bootstrap.sh ]; then sh ./bootstrap.sh
      elif [ -x ./autogen.sh ]; then sh ./autogen.sh
      else autoreconf -fi
      fi
    fi
    ./configure --prefix="$PREFIX" --with-pic --disable-static
    make -j"$JOBS"
    make install
  )
}

build_autotools_dep sofia-sip
build_autotools_dep spandsp

# Codec libraries for mod_silk/mod_bv/mod_siren/mod_ilbc: no Debian packages
# exist; fetch the same source tarballs the Windows build downloads and build
# them into the prefix (each installs a .pc file that FS's configure checks).
for lib in libsilk-1.0.8 broadvoice-0.1.0 g722_1-0.2.0 ilbc-0.0.1; do
  wget -nv "https://files.freeswitch.org/downloads/libs/$lib.tar.gz"
  tar -xzf "$lib.tar.gz"
  build_autotools_dep "$lib"
done

# FreeSWITCH itself
export PKG_CONFIG_PATH="$PREFIX/lib/pkgconfig"
cd freeswitch

# Restrict the module set (Linux equivalent of the trimmed Windows build).
cp ../fs-build/linux/modules.conf modules.conf

./bootstrap.sh -j
# --disable-fhs is required: with an explicit --prefix, configure defaults to
# FHS layout (conf under etc/, modules under lib/freeswitch/mod, state under
# var/) instead of the flat self-contained tree we ship.
# --enable-portable-binary keeps codegen CPU-generic for redistribution.
./configure -C --prefix="$PREFIX" --disable-fhs \
  --enable-portable-binary --disable-dependency-tracking
make -j"$JOBS"
make install
