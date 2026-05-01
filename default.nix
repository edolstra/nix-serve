(import (fetchTarball "https://github.com/NixOS/flake-compat/archive/master.tar.gz") {
  src = ./.;
}).defaultNix
