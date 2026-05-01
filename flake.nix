{
  description = "A utility for sharing a Nix store as a binary cache";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";
    nix = {
      url = "github:NixOS/nix/2.34-maintenance";
      flake = false;
    };
    treefmt-nix = {
      url = "github:numtide/treefmt-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      nix,
      treefmt-nix,
    }:

    let
      forAllSystems = f: nixpkgs.lib.genAttrs systems (system: f system);
      systems = [
        "x86_64-linux"
        "aarch64-linux"
        "i686-linux"
        "x86_64-darwin"
        "aarch64-darwin"
      ];
      nixComponentsFor =
        pkgs:
        let
          inherit (pkgs) lib;
          nixDependencies = lib.makeScope pkgs.newScope (
            import (nix + "/packaging/dependencies.nix") {
              inherit pkgs;
              inherit (pkgs) stdenv;
              inputs = { };
            }
          );
        in
        lib.makeScope nixDependencies.newScope (
          import (nix + "/packaging/components.nix") {
            officialRelease = true;
            inherit lib pkgs;
            src = nix;
            maintainers = [ ];
          }
        );
      treefmtFor =
        pkgs:
        treefmt-nix.lib.evalModule pkgs {
          projectRootFile = "flake.lock";

          programs.clang-format.enable = true;
          programs.meson.enable = true;
          programs.nixfmt.enable = true;
        };
    in
    {

      overlays.default = final: prev: {
        nix-serve = final.pkgs.callPackage ./package.nix {
          inherit self;
          nixComponents = nixComponentsFor final.pkgs;
        };
      };

      packages = forAllSystems (
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
        in
        rec {
          default = nix-serve;
          nix-serve = pkgs.callPackage ./package.nix {
            inherit self;
            nixComponents = nixComponentsFor pkgs;
          };
        }
      );

      checks = forAllSystems (
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
        in
        {
          build = self.packages.${system}.nix-serve;
          treefmt = (treefmtFor pkgs).config.build.check self;
        }
        // nixpkgs.lib.optionalAttrs (pkgs.stdenv.isLinux) {
          nixos-test-without-signing = pkgs.callPackage ./nixos-test-without-signing.nix {
            nix-serve = self.packages.${system}.nix-serve;
          };
          nixos-test-signing = pkgs.callPackage ./nixos-test-signing.nix {
            nix-serve = self.packages.${system}.nix-serve;
          };
        }
      );

      formatter = forAllSystems (
        system: (treefmtFor nixpkgs.legacyPackages.${system}).config.build.wrapper
      );
    };
}
