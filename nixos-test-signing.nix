{
  hello,
  testers,
  nix-serve,
}:

let
  signingKeyName = "test-nix-serve-1";

in
testers.runNixOSTest {
  name = "nix-serve-signing";
  nodes.machine =
    { pkgs, ... }:
    {
      services.nix-serve.enable = true;
      services.nix-serve.package = nix-serve;
      services.nix-serve.secretKeyFile = "/etc/nix-serve/secret-key";
      environment.systemPackages = [ pkgs.hello ];
    };
  testScript =
    let
      pkgHash = builtins.head (builtins.match "${builtins.storeDir}/([^-]+).+" (toString hello));
      helloStorePath = toString hello;
    in
    ''
      import re

      start_all()

      # Generate a signing key pair
      machine.succeed(
          "mkdir -p /etc/nix-serve && "
          "nix-store --generate-binary-cache-key ${signingKeyName} /etc/nix-serve/secret-key /etc/nix-serve/public-key"
      )

      # Restart the service so it picks up the key
      machine.succeed("systemctl restart nix-serve.service")
      machine.wait_for_unit("nix-serve.service")
      machine.wait_for_open_port(5000)

      # --- Signed narinfo ---

      narinfo = machine.succeed(
          "curl --fail -g http://0.0.0.0:5000/${pkgHash}.narinfo"
      )

      # Signed narinfo should contain a Sig field
      assert "Sig:" in narinfo, f"signed narinfo missing Sig: {narinfo}"

      # Sig should reference our key name
      sig_match = re.search(r"Sig: (\S+)", narinfo)
      assert sig_match, f"could not parse Sig: {narinfo}"
      assert sig_match.group(1).startswith("${signingKeyName}:"), \
          f"Sig should start with key name: {sig_match.group(1)}"

      # All standard fields should still be present
      assert "StorePath: ${helloStorePath}" in narinfo
      assert "NarHash: sha256:" in narinfo
      assert "NarSize:" in narinfo
      assert "Compression: none" in narinfo
      assert "References:" in narinfo

      # --- NAR download should still work on signed server ---

      url_match = re.search(r"URL: (nar/\S+)", narinfo)
      assert url_match, f"no URL in narinfo: {narinfo}"
      machine.succeed(
          f"curl --fail -g http://0.0.0.0:5000/{url_match.group(1)} -o /tmp/signed-hello.nar"
      )

      # Verify the NAR is valid by unpacking it
      machine.succeed("nix-store --restore /tmp/signed-unpacked < /tmp/signed-hello.nar")
      machine.succeed("test -x /tmp/signed-unpacked/bin/hello")
    '';
}
