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

# Relocatable rpath: the archive is redeployed under per-service directories
# (e.g. /opt/softdial/edge-gateway/freeswitch), not the fixed build prefix, so
# the bundled libs must be found relative to each ELF rather than at an
# absolute path. Use an $ORIGIN-relative runpath: from bin/ and mod/,
# $ORIGIN/../lib is the sibling lib/; from lib/ itself it resolves back to
# lib/, so a single form works for every object. The doubled $$ORIGIN survives
# make's variable expansion (make collapses $$ -> $ before the linker sees it);
# package.sh additionally normalises and verifies these runpaths with
# patchelf/readelf, since libtool can drop or reorder -rpath flags.
export CFLAGS="$OPT_CFLAGS"
export CXXFLAGS="$OPT_CFLAGS"
export LDFLAGS='-Wl,-rpath,$$ORIGIN/../lib'

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

# libks: SignalWire's "kitchen sink" library. FreeSWITCH v1.11.1 configure
# requires it (pkg-config libks2 >= 2.0.11) to build endpoints/mod_verto.
# It is a CMake project; install it into $PREFIX so libks2.pc and libks2.so
# sit alongside the other bundled deps and are picked up via PKG_CONFIG_PATH.
# CMAKE_SKIP_INSTALL_RPATH stops CMake baking the absolute $PREFIX/lib rpath
# its CMakeLists hardcodes; package.sh sets the $ORIGIN runpath instead.
# WITH_PACKAGING=OFF skips the CPack/lsb_release/changelog machinery we do not
# use. Only the ks2 library target is built (the test harness is skipped).
(
  cd libks
  # Drop the $$ORIGIN LDFLAGS here: CMake's Unix-Makefiles link script runs the
  # flags through a shell (where $$ = PID, not a literal), which would embed a
  # bogus rpath. package.sh sets libks2.so's $ORIGIN runpath with patchelf.
  unset LDFLAGS
  cmake -B build -G "Unix Makefiles" \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX="$PREFIX" \
    -DCMAKE_C_FLAGS="$OPT_CFLAGS" \
    -DWITH_PACKAGING=OFF \
    -DCMAKE_SKIP_INSTALL_RPATH=ON
  cmake --build build --target ks2 -j"$JOBS"
  cmake --install build
)

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
