{
  inputs.nixpkgs.url = "nixpkgs/nixos-20.09";

  outputs = { self, nixpkgs }:

    let
      forAllSystems = f: nixpkgs.lib.genAttrs systems (system: f system);
      systems = [ "x86_64-linux" "aarch64-linux" "i686-linux" "x86_64-darwin" ];
    in {

      overlay = final: prev: {

        nix-serve = with final; stdenv.mkDerivation {
          name = "nix-serve-${self.lastModifiedDate}";

          buildInputs = [ perl nix.perl-bindings perlPackages.Plack perlPackages.Starman perlPackages.DBDSQLite ];

          unpackPhase = "true";

          installPhase =
            ''
              mkdir -p $out/libexec/nix-serve
              cp ${./nix-serve.psgi} $out/libexec/nix-serve/nix-serve.psgi

              mkdir -p $out/bin
              cat > $out/bin/nix-serve <<EOF
              #! ${stdenv.shell}
              PERL5LIB=$PERL5LIB \
              NIX_REMOTE="\''${NIX_REMOTE:-auto?path-info-cache-size=0}" \
              exec ${perlPackages.Starman}/bin/starman --preload-app $out/libexec/nix-serve/nix-serve.psgi "\$@"
              EOF
              chmod +x $out/bin/nix-serve
            '';
        };

      };

      packages = forAllSystems (system: {
        nix-serve = (import nixpkgs { inherit system; overlays = [ self.overlay ]; }).nix-serve;
      });

      defaultPackage = forAllSystems (system: self.packages.${system}.nix-serve);

      checks = forAllSystems (system: {
        build = self.defaultPackage.${system};
        # FIXME: add a proper test.
      });

    };
}
