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
  inherit (lib) mkEnableOption mkIf;

  pluginSettingsFile = "${config.xdg.configHome}/DankMaterialShell/plugin_settings.json";
in
{
  options.programs.dms-sidebar.enable = mkEnableOption "the DMS tabbed sidebar";

  config = mkIf cfg.enable {
    programs.dank-material-shell.plugins.dafSidebar.src = "${self}/plugin";

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
