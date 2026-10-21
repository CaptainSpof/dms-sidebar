# Home Manager module. Needs DankMaterialShell's own module
# (programs.dank-material-shell) imported alongside it.
self:
{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.programs.dms-sidebar;
  inherit (lib)
    mkEnableOption
    mkIf
    mkOption
    types
    ;

  pluginSettingsFile = "${config.xdg.configHome}/DankMaterialShell/plugin_settings.json";

  # Only what differs from the plugin's own defaults reaches the file.
  pluginConfig = lib.filterAttrs (_: v: v != null) {
    inherit (cfg) url tokenFile;
    tabs = if cfg.tabs == [ ] then null else cfg.tabs;
  };
in
{
  options.programs.dms-sidebar = {
    enable = mkEnableOption "the DMS tabbed sidebar";

    url = mkOption {
      type = types.str;
      default = "http://homeassistant.local:8123";
      example = "http://192.168.0.10:8123";
      description = ''
        Home Assistant base URL. Prefer a LAN address: an address that reaches
        HA through a proxy or a VPN may be refused (401) even with a valid token.
      '';
    };

    tokenFile = mkOption {
      type = types.str;
      default = "~/.config/hass/token";
      description = ''
        File holding a Home Assistant long-lived access token, read at runtime
        by the shell. Deliberately a path: the token must never enter the store.
      '';
    };

    tabs = mkOption {
      type = types.listOf (types.attrsOf types.anything);
      default = [ ];
      example = lib.literalExpression ''
        [
          {
            id = "home";
            text = "Maison";
            icon = "home";
            type = "home";
            sections = [ { byArea = true; } ];
          }
        ]
      '';
      description = ''
        Tabs, as in `dafSidebar.json`. Empty keeps the plugin's default: a
        single "home" tab with one section per area.
      '';
    };
  };

  config = mkIf cfg.enable {
    programs.dank-material-shell.plugins.dafSidebar.src = "${self}/plugin";

    xdg.configFile."DankMaterialShell/dafSidebar.json".text = builtins.toJSON pluginConfig;

    # Plugin enable-state is runtime-owned by DMS; seed it once, then leave the
    # toggle to the DMS UI.
    home.activation.dmsSidebarPlugin = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      settings=${lib.escapeShellArg pluginSettingsFile}
      run mkdir -p "$(dirname "$settings")"
      [ -f "$settings" ] || run sh -c "echo '{}' > \"$settings\""
      if [ "$(${lib.getExe pkgs.jq} -r 'has("dafSidebar")' "$settings")" != "true" ]; then
        tmp=$(mktemp)
        ${lib.getExe pkgs.jq} '.dafSidebar = { "enabled": true }' "$settings" > "$tmp" \
          && run mv "$tmp" "$settings"
      fi
    '';
  };
}
