#!/bin/sh
# Verify a packaged archive on a clean minimal Debian container:
#  1. install only the packages named in DEPENDENCIES.txt
#  2. extract the archive to a NON-default per-service path (proves the tree is
#     relocatable: libs are found via $ORIGIN-relative runpaths, not an
#     absolute /opt/softdial/freeswitch rpath)
#  3. every ELF file must fully resolve its shared libraries (ldd)
#  4. freeswitch -version must run
#
# Usage: smoke-test.sh <archive.tar.gz>
set -eux

ARCHIVE="$1"
# Deliberately NOT the build-time prefix (/opt/softdial/freeswitch): extracting
# under a per-service directory is what proves relocatability.
PREFIX=/opt/softdial/edge-gateway/freeswitch

mkdir -p /opt/softdial/edge-gateway
tar -C /opt/softdial/edge-gateway -xzf "$ARCHIVE"

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
