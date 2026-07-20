# Sytel FreeSWITCH build for Debian

Monolithic FreeSWITCH build, self-contained under `/opt/softdial/freeswitch`
in the Softdial style. Includes binaries, loadable modules, default
configuration (`conf/`), and the bundled `sofia-sip` and `spandsp` libraries
(which have no generally-available Debian packages).

A matching `-dev` archive overlays the same tree with development headers,
pkg-config files, and (Release) the split debug symbols.

## Install

```sh
apt-get install $(grep -v '^#' DEPENDENCIES.txt)   # generally-available Debian packages
tar -C /opt/softdial -xzf freeswitch-Release.tar.gz
```

The build is linked with an absolute rpath of `/opt/softdial/freeswitch/lib`,
so no `ldconfig` or environment setup is needed, but the tree must be
reachable at that path (a symlink from a versioned directory is fine).

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

Release archives are stripped; matching DWARF symbols ship separately in
`freeswitch-symbols.tar.gz` (`.debug` files linked via `.gnu_debuglink`).
Point gdb at them with `set debug-file-directory` or place them next to the
binaries. Debug archives (`freeswitch-Debug.tar.gz`) are built `-O0 -ggdb3`
with symbols left in place.
