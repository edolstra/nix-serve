# nix-serve

`nix-serve` is a small utility to serve a Nix store as a binary cache,
allowing it to be used as a substituter by other Nix installations.

## Usage

The instructions below assume a flake-enabled version of Nix.

To start `nix-serve`, serving a binary cache on port 5000 of `localhost`:

```
# nix run github:edolstra/nix-serve
```

You can test whether the server works by running

```
# nix store ping --store http://localhost:5000
```

You can then pass `--substituters http://localhost:5000/` to Nix to
use this binary cache as a substituter.

`nix-serve` uses the Starman web server. See the [`starman`
documentation](https://metacpan.org/pod/distribution/Starman/script/starman)
for additional flags you can pass, e.g.

```
# nix run github:edolstra/nix-serve -- --access-log /dev/stderr
```

### Signing

It's possible to sign the binary cache. First create a key pair:

```
# nix-store --generate-binary-cache-key cache.example.org-1 ./secret ./public
# cat public
cache.example.org-1:l24SFecAdWV31HIN8jqFAYpCMFyreZizab3HJ3KFEgQ=
```

Then run the server as follows:

```
# NIX_SECRET_KEY_FILE=./secret nix run ...
```

To check whether signing and signature verification works, do:

```
# nix verify --store http://localhost:5000 \
    --trusted-public-keys 'cache.example.org-1:l24SFecAdWV31HIN8jqFAYpCMFyreZizab3HJ3KFEgQ=' \
    /nix/store/...
```

where `/nix/store/...` is one or more store paths served by your binary cache.
