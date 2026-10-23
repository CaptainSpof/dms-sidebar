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
  mdi = self.packages.${pkgs.stdenv.hostPlatform.system}.mdi-icons;

  pluginConfig = lib.filterAttrs (_: v: v != null) {
    inherit (cfg) url tokenFile;
    mdiFont = "${mdi}/mdi.ttf";
    mdiMap = "${mdi}/mdi.json";
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
            type = "lovelace";
            dashboard = "dashboard-maison";
          }
          {
            id = "salon";
            text = "Salon";
            icon = "weekend";
            type = "lovelace";
            dashboard = "dashboard-maison";
            page = "#popup_living_room";
            skipSections = [ 0 ];
            hideUnsupported = true;
          }
          {
            id = "pieces";
            text = "Pièces";
            icon = "grid_view";
            type = "home";
            sections = [ { byArea = true; } ];
          }
        ]
      '';
      description = ''
        Tabs, as in `dafSidebar.json`. `type = "lovelace"` renders the HA
        dashboard `dashboard` (its url_path), optionally opened on the pop-up
        `page`, leaving out the view sections listed in `skipSections` and,
        with `hideUnsupported`, cards it cannot render;
        `type = "rer"` lists the next departures at a PRIM `stopArea`, with
        the token read at runtime from `keyFile`, and Open-Meteo weather for
        the `weather` places under it;
        `type = "home"` lists entities by area. Empty keeps the
        plugin's default: a single "home" tab with one section per area.
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
