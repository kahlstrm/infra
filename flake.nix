{
  description = "Development environment";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs =
    {
      nixpkgs,
      flake-utils,
      ...
    }:
    flake-utils.lib.eachDefaultSystem (
      system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
        chrPackages = with pkgs; [
          python3
          qemu
          openssh
          curl
          just
        ];
      in
      {
        devShells.default = import ./shell.nix { inherit pkgs; };
        devShells.chr = pkgs.mkShellNoCC {
          packages = chrPackages;
        };
        devShells.chr-bootstrap = pkgs.mkShellNoCC {
          packages = chrPackages ++ [ pkgs.opentofu pkgs.jq pkgs.dig ];
        };

      }
    );
}
