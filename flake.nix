{
  description = "A utility for sharing a Nix store as a binary cache";

  inputs.nixpkgs.url = "nixpkgs/nixos-24.05";

  outputs = { self, nixpkgs }:

    let
      forAllSystems = f: nixpkgs.lib.genAttrs systems (system: f system);
      systems = [
        "x86_64-linux"
        "aarch64-linux"
        "i686-linux"
        "x86_64-darwin"
        "aarch64-darwin"
      ];
    in {

      overlays.default = final: prev: {
        nix-serve = final.pkgs.callPackage ./package.nix {
          inherit self;
          nix = final.nixVersions.git;
        };
      };

      packages = forAllSystems (system: let
        pkgs = nixpkgs.legacyPackages.${system};
      in rec {
        default = nix-serve;
        nix-serve = nixpkgs.legacyPackages.${system}.callPackage ./package.nix {
          inherit self;
          nix = pkgs.nixVersions.git;
        };
      });

      checks = forAllSystems (system: let
        pkgs = nixpkgs.legacyPackages.${system};
      in {
        build = self.packages.${system}.nix-serve;
      } // nixpkgs.lib.optionalAttrs (pkgs.stdenv.isLinux) {
        nixos-test = pkgs.callPackage ./nixos-test.nix {
          nix-serve = self.packages.${system}.nix-serve;
        };
      });
    };
}
