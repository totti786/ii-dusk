# App windows — the page pattern

> How a windowed app (Mixer, Packages, Bluetooth, Downloads, EasyEffects, ...) is laid out so
> they all read as one family. Settings pages have their own file, `settings-expressive.md`.
> Reference implementations: `modules/ii/mixer/` (simplest), `modules/ii/packages/`
> (long lists), `modules/ii/easyEffects/` (the richest).

## 1. The frame

Every app is a `FloatingWindow` (`XxxWindow.qml`) holding a `XxxContent.qml`:

- `ClockTopBar`: title and subtitle of the current tab, rail toggle, close.
- `ClockRail` on the left (labels when the window is wide, icons when narrow), with optional
  count `badges`. Set `showSettings: false` if the app has no settings page.
- `ClockNavigation` (bottom bar) instead of the rail when `width < ClockStyle.compactMax`.
- The page to the right of the rail. Ctrl+1..9 switch tabs, Ctrl+W/Q close; copy the key
  handler from `MixerContent.qml`.

The window background is `ClockStyle.colBackground`. A page's root is **transparent** and
fills the space; it does not paint the background and does not centre itself in a narrow
column or cap its width.

## 2. A page is: hero, then panes

```
ClockHero   what this page is for, in one sentence (+ buttons in `trailing`)
ClockPane   one section: badge, title, count, then rows or cards
ClockPane   ...
```

Lay them in a `Flickable` > `ColumnLayout` with `spacing: ClockStyle.paneGap`.

| Part | Use |
|---|---|
| `ClockHero` | `symbol`, `title`, `text`, `compact`, `shape`, `trailing: [buttons]`. One per page, first. A page that is a live tool (a node graph) may skip it. |
| `ClockPane` | `title`, `symbol`, `count`, `shape`; children go inside. `headerExtras` for buttons on the header row. |
| `ClockBadge` | The scalloped glyph shape both use. Vary `shape` (`Cookie9Sided`, `Clover4Leaf`, `SoftBurst`...) between sections. |
| `ClockEmptyState` | Inside a pane or alone; `Layout.alignment: Qt.AlignHCenter`, `shapeSize: ClockStyle.emptyShapeSmall` inside a pane. |

Pairs of related panes (Output / Input) go in a `GridLayout` with two columns once the page is
about 880 px wide, one column below that.

## 3. Surface layering

Page background `colBackground` < `ClockPane` (`colPane`) < things inside a pane
(`colSurfaceHigh`, hover `colSurfaceHighest`). A row inside a pane must **not** use
`colPane`, or it disappears. A selected or "in use" row uses `colActiveCard`. State is
colour and shape, not borders.

## 4. Long lists

Do not wrap a `ListView` of hundreds of rows in a pane's column. Make the list's own
`Rectangle { radius: ClockStyle.radiusCard; color: ClockStyle.colPane }` fill the remaining
height (`Layout.fillHeight: true`) with the `ListView` inside it (`anchors.margins:
ClockStyle.gap`). See `packages/UpdatesPage.qml`.

## 5. Sizes and type

Take every size from `ClockStyle` (`gap`, `gapSmall`, `paneGap`, `cardPadding`, `radiusCard`,
`radiusLarge`, `text*`). Titles use `Appearance.font.family.title` with the axes used in
`ClockPane` and `ClockHero`. Controls come from the shared `Clock*` set (`ClockButton`,
`ClockChip`, `ClockIconButton`, `ClockFormToggle`, `ClockSheet`...). Do not add an app-specific
copy of a control; extend the shared one.

## 6. Wiring a new app

1. `modules/ii/<app>/` with `qmldir`, `XxxApp.qml` (an `IpcHandler` target and a
   `GlobalShortcut`), `XxxWindow.qml` (title `ii Xxx`), `XxxContent.qml`, pages.
2. `GlobalStates.qml`: `xxxOpen`, `xxxPendingTab`, `openXxxApp`.
3. `modules/common/ShellActionRegistry.qml`: the action, keywords, `appIds`, `trigger`.
4. `panelFamilies/IllogicalImpulseFamily.qml` and `LiteFamily.qml`: import and
   `PanelUrlLoader`.
5. `~/.config/hypr/hyprland/keybinds.lua`: `hl.bind(..., hl.dsp.global("quickshell:xxxToggle"),
   { description = "..." })`; `rules.lua`: float and centre the `ii Xxx` window.

## 7. Checking a page

Render it in a throwaway headless Hyprland rather than on the live desktop: a generated
`shell.qml` that puts `XxxContent { anchors.fill: parent }` in a plain `Window`, run with
`qs -p` against that compositor, then `grim`. Look at every tab, at about 1500x960 and
at a narrow width (about 700) to see the compact layout.

## 8. Known exceptions

- **EasyEffects** keeps its own token set (`EasyEffectsStyle`) and copies of several controls
  from before this pattern; it is the visual reference, not yet built on the shared parts.
- **Music** has the labelled rail and puts its Library, Queue and Search results in a pane, but Home stays a cover grid with no hero, and Now Playing keeps its own cover-tinted look. **Monitor** and **Health** are
  dashboards of tiles, **Patchbay** is a canvas: each follows the frame but not the
  hero-and-panes page.
