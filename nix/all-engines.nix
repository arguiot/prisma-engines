{ pkgs, flakeInputs, lib, self', ... }:

let
  stdenv = pkgs.clangStdenv;
  srcPath = ../.;
  srcFilter = flakeInputs.gitignore.lib.gitignoreFilterWith {
    basePath = srcPath;
    extraRules = ''
      /nix
      /flake.*
    '';
  };
  src = lib.cleanSourceWith {
    filter = srcFilter;
    src = srcPath;
    name = "prisma-engines-source";
  };
  craneLib = flakeInputs.crane.mkLib pkgs;
  deps = craneLib.vendorCargoDeps { inherit src; };
  libSuffix = if stdenv.isDarwin then "dylib" else "so";
in
{
  packages.prisma-engines = stdenv.mkDerivation {
    name = "prisma-engines";
    inherit src;

    buildInputs = [ pkgs.openssl.out ];
    nativeBuildInputs = with pkgs; [
      cargo
      git # for our build scripts that bake in the git hash
      protobuf # for tonic
      openssl.dev
      pkg-config
    ] ++ lib.optionals stdenv.isDarwin [
      perl # required to build openssl
      darwin.apple_sdk.frameworks.Security
    ];

    configurePhase = ''
      mkdir .cargo
      ln -s ${deps}/config.toml .cargo/config.toml
    '';

    buildPhase = ''
      cargo build --release --bins
      cargo build --release -p query-engine-node-api
    '';

    installPhase = ''
      mkdir -p $out/bin $out/lib
      cp target/release/query-engine $out/bin/
      cp target/release/migration-engine $out/bin/
      cp target/release/introspection-engine $out/bin/
      cp target/release/prisma-fmt $out/bin/
      cp target/release/libquery_engine.${libSuffix} $out/lib/libquery_engine.node
    '';
  };

  packages.test-cli = lib.makeOverridable
    ({ profile }: stdenv.mkDerivation {
      name = "test-cli";
      inherit src;
      inherit (self'.packages.prisma-engines) buildInputs nativeBuildInputs configurePhase;

      buildPhase = "cargo build --profile=${profile} --bin=test-cli";

      installPhase = ''
        set -eu
        mkdir -p $out/bin
        QE_PATH=$(find target -name 'test-cli')
        cp $QE_PATH $out/bin
      '';
    })
    { profile = "release"; };

  packages.query-engine-bin = lib.makeOverridable
    ({ profile }: stdenv.mkDerivation {
      name = "query-engine-bin";
      inherit src;
      inherit (self'.packages.prisma-engines) buildInputs nativeBuildInputs configurePhase;

      buildPhase = "cargo build --profile=${profile} --bin=query-engine";

      installPhase = ''
        set -eu
        mkdir -p $out/bin
        QE_PATH=$(find target -name 'query-engine')
        cp $QE_PATH $out/bin
      '';
    })
    { profile = "release"; };
}
