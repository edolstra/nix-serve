{
  description = "A utility for sharing a Nix store as a binary cache";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";
    treefmt-nix = {
      url = "github:numtide/treefmt-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    {
      self,
      nixpkgs,
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
      treefmtFor =
        pkgs:
        treefmt-nix.lib.evalModule pkgs {
          projectRootFile = "flake.lock";
          programs.nixfmt.enable = true;
        };
    in
    {

      overlays.default = final: prev: {
        nix-serve = final.pkgs.callPackage ./package.nix {
          inherit self;
          nixComponents = final.nixVersions.nixComponents_git;
        };
      };

      packages = forAllSystems (
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
        in
        rec {
          default = nix-serve;
          nix-serve = nixpkgs.legacyPackages.${system}.callPackage ./package.nix {
            inherit self;
            nixComponents = pkgs.nixVersions.nixComponents_git;
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
