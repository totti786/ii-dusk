# Quickshell startup caches

Optional native optimization for ii-dusk, pinned to upstream revision
`9b0f339b19057f4731bf3b48293307d7ef241671` (package release 3).
The source archive and checked patches reproduce the locally validated build.

```sh
cd sdata/dist-arch/quickshell-startup-cache
makepkg --cleanbuild --force
sudo pacman -U quickshell-git-0.3.2.r11.g9b0f339-3-x86_64.pkg.tar.zst
```

The patches cache canonical paths, enable compiled QML disk caching through file
URLs, and avoid redundant QML header parsing and import metadata lookups. Rebuild
after incompatible Qt updates. A stock AUR upgrade can replace this custom build.
This package is optional and is not wired into the normal installer.

The patched scanner automatically creates `qmldir` metadata in writable config
directories, marks it with `# quickshell-generated qmldir`, and updates it only
when its content changes. Generated paths are ignored by Git; authored `qmldir`
files remain source. If a new QML directory gets generated metadata, add its path
to the ignore lists. Do not delete these files from a running installation as a
cleanup step: the optimized file loader relies on them for sibling type imports.
The virtual fallback is not reliable for every implicit sibling inheritance case.

The QML startup changes work with regular Quickshell too. Wallpaper loads first,
bar and Dynamic Island next, other panels and services follow, and desktop widgets
load last. Optional island sources are deferred until the desktop is ready.
`.WarmStartupCache.qml` can precompile core types without opening desktop windows:

```sh
qs --no-color -p ~/.config/quickshell/ii/.WarmStartupCache.qml
```

Measured warm-cache session restarts on the development machine (median of three):

| Milestone | Generated files + file loader | Virtual loader without generated files |
|---|---:|---:|
| Wallpaper painted | 1.256 s | 2.096 s |
| Dynamic Island painted | 2.080 s | 4.094 s |
| Bar painted | 2.166 s | 4.221 s |
| Widgets loading starts | 4.956 s | 9.365 s |

These compare the two working loading paths, not the isolated cost of metadata
files. They are not cold-boot timings. The virtual test used a temporary build;
production source, installed shell, and all 218 generated files were restored.
