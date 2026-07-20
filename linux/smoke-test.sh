#!/bin/sh
# Verify a packaged archive on a clean minimal Debian container:
#  1. install only the packages named in DEPENDENCIES.txt
#  2. extract the archive to the real deployment path
#  3. every ELF file must fully resolve its shared libraries (ldd)
#  4. freeswitch -version must run
#
# Usage: smoke-test.sh <archive.tar.gz>
set -eux

ARCHIVE="$1"
PREFIX=/opt/softdial/freeswitch

mkdir -p /opt/softdial
tar -C /opt/softdial -xzf "$ARCHIVE"

apt-get update
# shellcheck disable=SC2046
apt-get install -y --no-install-recommends $(grep -v '^#' "$PREFIX/DEPENDENCIES.txt")

FAIL=0
for f in $(find "$PREFIX/bin" "$PREFIX/lib" "$PREFIX/mod" -type f \
             \( -name '*.so*' -o -perm -u+x \)); do
  head -c4 "$f" | grep -q "$(printf '\177ELF')" || continue
  if ldd "$f" 2>/dev/null | grep -q 'not found'; then
    echo "UNRESOLVED: $f"
    ldd "$f" | grep 'not found'
    FAIL=1
  fi
done
[ "$FAIL" = 0 ]

"$PREFIX/bin/freeswitch" -version
