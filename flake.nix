{
  description = "A Rust web server including a NixOS module";
  inputs.nixpkgs.url = "nixpkgs/nixos-23.05";
  inputs.import-cargo.url = github:edolstra/import-cargo;

  outputs = { self, nixpkgs, import-cargo }:
    let
      # to work with older version of flakes
      lastModifiedDate = self.lastModifiedDate or self.lastModified or "19700101";
      version = "${builtins.substring 0 8 lastModifiedDate}-${self.shortRev or "dirty"}";
      supportedSystems = [ "x86_64-linux" ];
      forAllSystems = f: nixpkgs.lib.genAttrs supportedSystems (system: f system);
      nixpkgsFor = forAllSystems (system: import nixpkgs { inherit system; overlays = [ self.overlay ]; });
    in {
      overlay = final: prev: {
        rust-web-server = with final; final.callPackage ({ inShell ? false }: stdenv.mkDerivation rec {
          name = "rust-web-server-${version}";

          # In 'nix develop', we don't need a copy of the source tree
          # in the Nix store.
          src = if inShell then null else ./.;

          buildInputs =
            [ rustc
              cargo
            ] ++ (if inShell then [
              # In 'nix develop', provide some developer tools.
              rustfmt
              clippy
            ] else [
              (import-cargo.builders.importCargo {
                lockFile = ./Cargo.lock;
                inherit pkgs;
              }).cargoHome
            ]);

          target = "--release";

          buildPhase = "cargo build ${target} --frozen --offline";

          doCheck = true;

          checkPhase = "cargo test ${target} --frozen --offline";

          installPhase =
            ''
              mkdir -p $out
              cargo install --frozen --offline --path . --root $out
              rm $out/.crates.toml
            '';
        }) {};

      };

      packages = forAllSystems (system:
        {
          inherit (nixpkgsFor.${system}) rust-web-server;
        });

      defaultPackage = forAllSystems (system: self.packages.${system}.rust-web-server);
      devShell = forAllSystems (system: self.packages.${system}.rust-web-server.override { inShell = true; });

      nixosModules.rust-web-server = { pkgs, ... }:
        {
          nixpkgs.overlays = [ self.overlay ];
          systemd.services.rust-web-server = {
            wantedBy = [ "multi-user.target" ];
            serviceConfig.ExecStart = "${pkgs.rust-web-server}/bin/rust-web-server";
          };
        };

      # Tests run by 'nix flake check' and by Hydra.
      checks = forAllSystems
        (system:
          with nixpkgsFor.${system};
          {
            inherit (self.packages.${system}) rust-web-server;

            # A VM test of the NixOS module.
            vmTest =
              with import (nixpkgs + "/nixos/lib/testing-python.nix") {
                inherit system;
              };

              makeTest {
                nodes = {
                  client = { ... }: {
                    imports = [ self.nixosModules.rust-web-server ];
                  };
                };

              testScript =
                ''
                  start_all()
                  client.wait_for_unit("multi-user.target")
                  assert "Hello Nixers" in client.wait_until_succeeds("curl --fail http://localhost:8080/")
                '';
              };
          }
        );
    };
}
