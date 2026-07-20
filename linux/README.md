# Sytel FreeSWITCH build for Debian

Monolithic, relocatable FreeSWITCH build, self-contained in the Softdial
style. Includes binaries, loadable modules, default configuration (`conf/`),
and the bundled `sofia-sip`, `spandsp` and `libks2` libraries (which have no
generally-available Debian packages; `libks2` is required for
`endpoints/mod_verto`).

A matching `-dev` archive overlays the same tree with development headers,
pkg-config files, and (Release) the split debug symbols.

## Install

```sh
apt-get install $(grep -v '^#' DEPENDENCIES.txt)   # generally-available Debian packages
tar -C /opt/softdial -xzf freeswitch-<version>-<codename>-<arch>.tar.gz
```

The tree is **relocatable**: every executable and module carries an
`$ORIGIN/../lib` runpath, so the bundled libraries are found relative to the
extracted location. Extract it anywhere (e.g. a per-service directory such as
`/opt/softdial/edge-gateway/freeswitch` or `/opt/softdial/media-server/freeswitch`);
no `ldconfig`, `LD_LIBRARY_PATH` or fixed install path is needed.

Note that FreeSWITCH still bakes in the configure-time prefix
(`/opt/softdial/freeswitch`) as the compiled-in default for its `conf`, `db`,
`log`, `mod` and `run` directories. When the archive is extracted anywhere
other than that prefix, pass explicit locations on the command line, e.g.
`freeswitch -conf <dir>/conf -log <dir>/log -db <dir>/db -mod <dir>/mod`
(the Softdial services do this automatically).

`DEPENDENCIES.txt` is generated per build from the actual linked libraries and
is specific to the Debian release this archive was built for.

## Layout

- `bin/` — `freeswitch`, `fs_cli`, tools
- `mod/` — loadable modules (the Sytel module set)
- `conf/` — default configuration (edit or replace; not overwritten by upgrades
  if you deploy versioned directories)
- `lib/` — `libfreeswitch` plus bundled `sofia-sip` / `spandsp`
- `include/`, `lib/pkgconfig/` — headers and pkg-config files for building
  out-of-tree modules against this build
- `log/`, `db/`, `run/` — runtime state (created empty)

## Debug information

The main archive is stripped; DWARF symbols ship in the matching `-dev`
overlay (`freeswitch-dev-<version>-<codename>-<arch>.tar.gz`) as `.debug`
files placed next to their binaries and linked via `.gnu_debuglink` — extract
the overlay over an installed tree and gdb finds them automatically. Debug
builds (`freeswitch-debug-<version>-<codename>-<arch>.tar.gz`) are
`-O0 -ggdb3` with symbols left in place.
