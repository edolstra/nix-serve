{
  hello,
  testers,
  nix-serve,
}:

testers.runNixOSTest {
  name = "nix-serve-no-signing";
  nodes.machine =
    { pkgs, ... }:
    {
      services.nix-serve.enable = true;
      services.nix-serve.package = nix-serve;
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
      machine.wait_for_unit("nix-serve.service")
      machine.wait_for_open_port(5000)

      # --- /nix-cache-info ---

      info = machine.succeed("curl --fail -g http://0.0.0.0:5000/nix-cache-info")
      assert "StoreDir: /nix/store" in info, f"unexpected nix-cache-info: {info}"
      assert "WantMassQuery: 1" in info
      assert "Priority: 30" in info

      # Check response status
      headers = machine.succeed(
          "curl -sI -g http://0.0.0.0:5000/nix-cache-info"
      )
      assert "200" in headers, f"expected 200: {headers}"

      # --- /<hash>.narinfo ---

      narinfo = machine.succeed(
          "curl --fail -g http://0.0.0.0:5000/${pkgHash}.narinfo"
      )
      assert "StorePath: ${helloStorePath}" in narinfo, f"unexpected narinfo: {narinfo}"
      assert "NarHash: sha256:" in narinfo, "NarHash should be sha256"
      assert "NarSize:" in narinfo
      assert "Compression: none" in narinfo, "Compression field missing or wrong"
      # References and Deriver are optional (only present when the store has them)
      # but hello should have references (at least glibc)
      assert "References:" in narinfo, "References field missing"

      # URL should be in the new format: nar/<hash>-<narhash>.nar
      url_match = re.search(r"URL: (nar/([0-9a-z]+)-([0-9a-z]+)\.nar)", narinfo)
      assert url_match, f"URL not in expected format: {narinfo}"
      nar_url = url_match.group(1)
      url_hash = url_match.group(2)
      url_narhash = url_match.group(3)
      assert url_hash == "${pkgHash}", f"URL hash mismatch: {url_hash} != ${pkgHash}"

      # NarHash in narinfo should match the hash embedded in the URL
      narhash_match = re.search(r"NarHash: sha256:(\S+)", narinfo)
      assert narhash_match, f"could not parse NarHash: {narinfo}"
      assert narhash_match.group(1) == url_narhash, \
          f"NarHash vs URL mismatch: {narhash_match.group(1)} != {url_narhash}"

      # NarSize should be a positive integer
      narsize_match = re.search(r"NarSize: (\d+)", narinfo)
      assert narsize_match, f"could not parse NarSize: {narinfo}"
      assert int(narsize_match.group(1)) > 0, "NarSize should be positive"
      expected_nar_size = int(narsize_match.group(1))

      # Check narinfo Content-Type header
      narinfo_headers = machine.succeed(
          "curl -sI -g http://0.0.0.0:5000/${pkgHash}.narinfo"
      )
      assert "x-nix-narinfo" in narinfo_headers, f"wrong Content-Type: {narinfo_headers}"

      # Unsigned server should not have Sig field (no secret key configured)
      assert "Sig:" not in narinfo, "unsigned server should not produce Sig"

      # --- /nar/<hash>-<narhash>.nar (new format) ---

      machine.succeed(
          f"curl --fail -g http://0.0.0.0:5000/{nar_url} -o /tmp/hello-new.nar"
      )
      # Verify file size matches NarSize
      new_nar_size = int(machine.succeed("stat -c %s /tmp/hello-new.nar").strip())
      assert new_nar_size == expected_nar_size, \
          f"new NAR size {new_nar_size} != expected {expected_nar_size}"

      # Verify NAR content: unpack and check the hello binary exists
      machine.succeed("nix-store --restore /tmp/hello-unpacked < /tmp/hello-new.nar")
      machine.succeed("test -x /tmp/hello-unpacked/bin/hello")
      machine.succeed("/tmp/hello-unpacked/bin/hello")

      # --- /nar/<hash>.nar (legacy format) ---

      machine.succeed(
          "curl --fail -g http://0.0.0.0:5000/nar/${pkgHash}.nar -o /tmp/hello-legacy.nar"
      )
      # Legacy NAR should have the same size
      legacy_nar_size = int(machine.succeed("stat -c %s /tmp/hello-legacy.nar").strip())
      assert legacy_nar_size == expected_nar_size, \
          f"legacy NAR size {legacy_nar_size} != expected {expected_nar_size}"

      # Both NAR formats should produce identical content
      machine.succeed("diff /tmp/hello-new.nar /tmp/hello-legacy.nar")

      # --- /nar/ with wrong NAR hash (should 404) ---

      exit_code = machine.execute(
          "curl --fail -g http://0.0.0.0:5000/nar/${pkgHash}-0000000000000000000000000000000000000000000000000000.nar"
      )[0]
      assert exit_code != 0, "wrong narhash should return failure"

      # --- /nar/ with nonexistent hash (both formats) ---

      machine.fail(
          "curl --fail -g http://0.0.0.0:5000/nar/0000000000000000000000000000000a-0000000000000000000000000000000000000000000000000000.nar"
      )
      machine.fail(
          "curl --fail -g http://0.0.0.0:5000/nar/0000000000000000000000000000000a.nar"
      )

      # --- /log/<path> endpoint ---

      # Build a trivial derivation inside the VM so we have a build log available
      built_path = machine.succeed(
          "nix-build --no-out-link -E '"
          'derivation { name = "log-test"; system = "x86_64-linux";'
          ' builder = "/bin/sh"; args = ["-c" "echo log-test-output >&2; echo done > $out"]; }'
          "'"
      ).strip()
      built_basename = built_path.split("/")[-1]

      # The /log/ endpoint should return the build log
      log_output = machine.succeed(
          f"curl --fail -g http://0.0.0.0:5000/log/{built_basename}"
      )
      assert "log-test-output" in log_output, f"expected build log content, got: {log_output}"

      # --- narinfo for locally-built path (has Deriver) ---

      built_hash = built_basename.split("-")[0]
      built_narinfo = machine.succeed(
          f"curl --fail -g http://0.0.0.0:5000/{built_hash}.narinfo"
      )
      assert f"StorePath: {built_path}" in built_narinfo, \
          f"unexpected StorePath: {built_narinfo}"
      assert "Deriver:" in built_narinfo, \
          f"locally-built path should have Deriver: {built_narinfo}"
      assert "log-test" in built_narinfo, \
          f"Deriver should reference log-test: {built_narinfo}"

      # --- 404 for nonexistent .narinfo ---

      machine.fail(
          "curl --fail -g http://0.0.0.0:5000/0000000000000000000000000000000a.narinfo"
      )

      # --- 404 for unknown routes ---

      machine.fail("curl --fail -g http://0.0.0.0:5000/nonexistent")
      machine.fail("curl --fail -g http://0.0.0.0:5000/")
      machine.fail("curl --fail -g http://0.0.0.0:5000/nix-cache-info/extra")
    '';
}
