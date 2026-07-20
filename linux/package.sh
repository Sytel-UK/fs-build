#!/bin/sh
# Package /opt/softdial/freeswitch into redistributable archives:
#
#   freeswitch-<Config>.tar.gz      runtime: bin/ mod/ conf/ lib/ (+README,
#                                   DEPENDENCIES.txt). Release binaries are
#                                   stripped.
#   freeswitch-<Config>-dev.tar.gz  overlay for the same tree: include/,
#                                   lib/pkgconfig/, and (Release) the split
#                                   DWARF symbols as .debug files placed next
#                                   to their binaries, so extracting the dev
#                                   archive over an installed runtime tree
#                                   makes gdb symbol lookup and third-party
#                                   module builds (PKG_CONFIG_PATH) just work.
#
# Usage: package.sh <Release|Debug> <output-dir>
#
# DEPENDENCIES.txt lists the Debian packages the target machine must have,
# derived from the actual NEEDED sonames of the built binaries (bundled libs
# and base glibc excluded), mapped to packages via dpkg -S on the build
# container.
set -eux

CONFIG="${1:-Release}"
OUT="${2:-$PWD/out}"
PREFIX=/opt/softdial/freeswitch
DEV="$OUT/devroot/freeswitch"

mkdir -p "$OUT" "$DEV/lib"

elf_files() {
  find "$PREFIX/bin" "$PREFIX/lib" "$PREFIX/mod" -type f \
    \( -name '*.so*' -o -perm -u+x \) 2>/dev/null |
    while read -r f; do
      head -c4 "$f" | grep -q "$(printf '\177ELF')" && echo "$f" || true
    done
}

# --- dependency manifest ----------------------------------------------------
NEEDED=$(elf_files | xargs -r -n1 objdump -p 2>/dev/null |
  awk '/NEEDED/{print $2}' | sort -u)

# sonames we ship ourselves
BUNDLED=$( { find "$PREFIX/lib" "$PREFIX/mod" -name '*.so*' -type f \
    -exec sh -c 'objdump -p "$1" 2>/dev/null | awk "/SONAME/{print \$2}"' _ {} \; ;
  find "$PREFIX/lib" "$PREFIX/mod" -name '*.so*' -exec basename {} \; ; } | sort -u)

PKGS=""
UNOWNED=""
for so in $NEEDED; do
  if printf '%s\n' "$BUNDLED" | grep -qx "$so"; then continue; fi
  case "$so" in
    libc.so.*|libm.so.*|libdl.so.*|libpthread.so.*|librt.so.*|ld-linux*|libresolv.so.*|libgcc_s.so.*|libstdc++.so.*) continue ;;
  esac
  pkg=$(dpkg -S "*/$so" 2>/dev/null | head -1 | cut -d: -f1) || true
  if [ -n "$pkg" ]; then
    PKGS="$PKGS $pkg"
  else
    UNOWNED="$UNOWNED $so"
  fi
done
PKGS=$(printf '%s\n' $PKGS | sort -u)

{
  echo "# Debian packages required at runtime (generated from linked sonames)"
  echo "# Install with: apt-get install \$(grep -v '^#' DEPENDENCIES.txt)"
  printf '%s\n' $PKGS
} > "$PREFIX/DEPENDENCIES.txt"
[ -n "$UNOWNED" ] && { echo "sonames with no owning package:$UNOWNED" >&2; exit 1; }

cp fs-build/linux/README.md "$PREFIX/README.md"

# --- carve out the dev overlay ----------------------------------------------
# Headers (FreeSWITCH + bundled sofia-sip/spandsp) and pkg-config files.
mv "$PREFIX/include" "$DEV/include"
mv "$PREFIX/lib/pkgconfig" "$DEV/lib/pkgconfig"
# libtool archives are build-system litter; nothing consumes them.
find "$PREFIX" -name '*.la' -delete

# --- symbol split (Release only) --------------------------------------------
if [ "$CONFIG" = "Release" ]; then
  for f in $(elf_files); do
    rel="${f#"$PREFIX"/}"
    mkdir -p "$DEV/$(dirname "$rel")"
    objcopy --only-keep-debug "$f" "$DEV/$rel.debug"
    # debuglink stores the basename; gdb searches the binary's own directory
    # first, which is where the dev overlay places the .debug file.
    objcopy --strip-debug --strip-unneeded --preserve-dates \
      --add-gnu-debuglink="$DEV/$rel.debug" "$f"
  done
fi

# --- archives ---------------------------------------------------------------
# Both rooted at 'freeswitch': deploy/overlay with tar -C /opt/softdial -xzf
tar -C /opt/softdial -czf "$OUT/freeswitch-$CONFIG.tar.gz" freeswitch
tar -C "$OUT/devroot" -czf "$OUT/freeswitch-$CONFIG-dev.tar.gz" freeswitch
rm -rf "$OUT/devroot"
