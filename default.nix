with import <nixpkgs> {};

stdenv.mkDerivation {
  name = "nix-serve-1";

  buildInputs = [ perl nix perlPackages.Plack perlPackages.Starman 
    makeWrapper 
  ];

  unpackPhase = "true";

  installPhase =
    ''
      mkdir -p "$out/libexec/nix-serve"
      cp ${./nix-serve.psgi} "$out/libexec/nix-serve/nix-serve.psgi"

      mkdir -p $out/bin
      makeWrapper '${perlPackages.Starman}/bin/starman' "$out/bin/nix-serve" \
          --prefix PERL5LIB : "$PERL5LIB" \
          --add-flags "$out/libexec/nix-serve/nix-serve.psgi"

      makeWrapper '${perlPackages.Plack}/bin/plackup' "$out/bin/nix-serve.cgi" \
          --prefix PERL5LIB : "$PERL5LIB" \
          --prefix PATH : '${bzip2}/bin' \
          --prefix PATH : '${nix}/bin' \
          --set NIX_REMOTE daemon \
          --set PATH_INFO '$QUERY_STRING' \
          --add-flags "$out/libexec/nix-serve/nix-serve.psgi"
    '';
}
