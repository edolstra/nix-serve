{
  lib,
  stdenv,
  meson,
  ninja,
  pkg-config,
  httplib,
  nixComponents,
  self,
}:

stdenv.mkDerivation {
  name = "nix-serve-${self.lastModifiedDate}";

  src = lib.fileset.toSource {
    fileset = lib.fileset.unions [
      ./meson.build
      ./nix-serve.cc
    ];
    root = ./.;
  };

  nativeBuildInputs = [
    meson
    ninja
    pkg-config
  ];

  buildInputs = [
    nixComponents.nix-util
    nixComponents.nix-store
    nixComponents.nix-cmd
    httplib
  ];
}
