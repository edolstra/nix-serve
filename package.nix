{
  stdenv,
  perl,
  perlPackages,
  nix,
  self,
}:

stdenv.mkDerivation {
  name = "nix-serve-${self.lastModifiedDate}";

  buildInputs = [
    perl
    nix.perl-bindings
    perlPackages.Plack
    perlPackages.Starman
    perlPackages.DBDSQLite
  ];

  unpackPhase = "true";

  installPhase = ''
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
}
