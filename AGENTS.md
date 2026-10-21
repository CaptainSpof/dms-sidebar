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
