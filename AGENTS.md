# dms-sidebar

DankMaterialShell plugin ([plugin/](plugin)) and a Home Manager module
([nix/home-module.nix](nix/home-module.nix)). The plugin id is `dafSidebar`;
saved settings live under that id, so never rename it.

## Layout

- [plugin/DafSidebar.qml](plugin/DafSidebar.qml) is a `daemon` plugin: one
  instance, no bar pill. It owns a `DankSlideout` per screen and the IPC target
  (`dms ipc call dafSidebar toggle`).
- [plugin/components/SidebarPanel.qml](plugin/components/SidebarPanel.qml) is the
  slideout body: a tab bar over a `StackLayout`. A new widget is a `tabs` entry
  plus a component.

## Rules

- **Sibling QML types need `components/` + `qmldir` + `import "./components"`**
  (DMS loads plugins from a `?revision=N` URL). Register new types in the qmldir.
- **Never write `Child { slideout: slideout }`** when the child declares that
  property; the slideout's id is `slideoutWindow` for that reason.
- Home Assistant token: read `~/.config/hass/token` at runtime, never put it in
  the Nix store.

## Testing against a running DMS

- Link `plugin/` over `~/.config/DankMaterialShell/plugins/dafSidebar`.
- `dms ipc call plugins reload dafSidebar` after an edit; restart `dms` after an
  edit under `components/` or after a component failed to load once.
- DMS swallows handler exceptions; probe by writing a file under `$HOME` with
  `Quickshell.execDetached`.

## Home Assistant

- [HaClient.qml](plugin/components/HaClient.qml) speaks the WebSocket API
  (`get_states`, `subscribe_events`, area/device/entity registries). It only
  connects while a slideout is visible.
- Config lives in `~/.config/DankMaterialShell/dafSidebar.json` (optional, see
  the header of [DafSidebar.qml](plugin/DafSidebar.qml)); the token is read from
  `~/.config/hass/token` at runtime.
- **Same-name binding trap, again**: `ha: ha` inside `SidebarPanel {}` binds the
  panel's property to itself. The client's id is `haClient`.
- **Restarting DMS**: `systemctl --user restart dms`. Never `pkill -f "dms run"`
  from a shell command that contains that string — it kills the shell too.
- **`dafoltop` resolves to its Tailscale address, which HA rejects (401, CGNAT
  vs `local_only`).** Use the LAN address in `dafSidebar.json`
  (`http://192.168.0.10:8123`); the token itself is fine.

## Lovelace tab (`type: "lovelace"`)

- [LovelaceTab.qml](plugin/components/LovelaceTab.qml) fetches
  `lovelace/config` for one dashboard and is the context (`dash`) for every
  card: icons, state text, conditions, actions, page stack.
  [LvCard.qml](plugin/components/LvCard.qml) renders one card and loads nested
  ones through a Loader.
- **Supported**: bubble-card `button` (name/state/switch/slider),
  `separator`, `sub-buttons`, `media-player`, `pop-up` (as a page);
  `paper-buttons-row` (a row whose base action navigates to `#…` is read as a
  room tile); `vertical-stack`, `horizontal-stack`, `grid`, `conditional`,
  `visibility`; HA `tile`/`entity`/`button`/`heading`/`entities`. Anything else
  is a fallback box naming its type, or nothing with `hideUnsupported`.
- **Read for meaning, not for looks**: `styles`, `card_mod`, bubble modules
  (origami_*) are ignored. JS (`${…}`) and Jinja (`{{ … }}`) templates are not
  evaluated; a templated string counts as absent.
- `more-info` opens an entity page (EntityRow); `navigate` only follows
  `#pop-up` hashes. Screen/user conditions are always true.
- **Inline `component`s cannot see the file's ids**: each one takes `dash` as a
  property, passed from `root.dash` at every instantiation.
- Icons: `mdi:` names map to codepoints of the Material Design Icons font
  through `mdi.json`, generated from the font's glyph names at build time
  ([nix/mdi-icons.nix](nix/mdi-icons.nix)); the HM module passes both paths.
- **Testing on a box where the HM module is deployed**: `dafSidebar.json` and
  the plugin dir are Home Manager links. Replace them for live work and put
  the links back before the next switch, or the switch refuses to clobber.
- `dms ipc call dafSidebar toggle` opens on the focused output, which may be a
  screen the user is watching; prefer asking for a visual check.
- **A deploy does not restart DMS.** The plugin link moves to the new store
  path, but the running shell keeps the component it compiled. After a switch,
  `systemctl --user restart dms` before judging a change.
- **Responsive layout**: both tabs spread their content over
  `floor(width / 360px)` columns. The lovelace tab groups cards into blocks (a
  header with the cards under it, or a self-contained `vertical-stack`) and
  sends each block to the currently shortest column, by a rough weight in leaf
  cards.
