with import <nixpkgs> {};

let nix = nixUnstable; in

stdenv.mkDerivation {
  name = "nix-serve-2";

  buildInputs = [ perl nix perlPackages.Plack perlPackages.Starman perlPackages.DBDSQLite ];

  unpackPhase = "true";

  installPhase =
    ''
      mkdir -p $out/libexec/nix-serve
      cp ${./nix-serve.psgi} $out/libexec/nix-serve/nix-serve.psgi

      mkdir -p $out/bin
      cat > $out/bin/nix-serve <<EOF
      #! ${stdenv.shell}
      PERL5LIB=$PERL5LIB exec ${perlPackages.Starman}/bin/starman $out/libexec/nix-serve/nix-serve.psgi "\$@"
      EOF
      chmod +x $out/bin/nix-serve
    '';
}
