{
  description = "Tabbed side panel (Home Assistant dashboard) for DankMaterialShell";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs =
    { self, nixpkgs }:
    let
      systems = [
        "x86_64-linux"
        "aarch64-linux"
      ];
      forAllSystems = f: nixpkgs.lib.genAttrs systems (system: f nixpkgs.legacyPackages.${system});
    in
    {
      packages = forAllSystems (pkgs: {
        mdi-icons = pkgs.callPackage ./nix/mdi-icons.nix { };
      });

      homeModules = {
        dms-sidebar = import ./nix/home-module.nix self;
        default = self.homeModules.dms-sidebar;
      };

      formatter = forAllSystems (pkgs: pkgs.nixfmt);
    };
}
