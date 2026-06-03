{
  description = "Flutter dev shell matching NixOS flutter setup";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { nixpkgs, flake-utils, ... }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs {
          inherit system;
          config = {
            android_sdk.accept_license = true;
            allowUnfree = true;
          };
        };

        androidComposition = pkgs.androidenv.composeAndroidPackages {
          buildToolsVersions = [
            "35.0.0"
            "34.0.0"
          ];

          platformVersions = [
            "35"
            "34"
          ];

          abiVersions = [
            "x86_64"
            "arm64-v8a"
          ];

          includeEmulator = true;
          includeSystemImages = true;

          systemImageTypes = [
            "google_apis_playstore"
          ];
        };

        androidSdk = androidComposition.androidsdk;
      in
      {
        devShells.default = pkgs.mkShell {
          packages = with pkgs; [
            flutter
            androidSdk
            jdk17
            android-tools
          ];

          ANDROID_HOME = "${androidSdk}/libexec/android-sdk";
          ANDROID_SDK_ROOT = "${androidSdk}/libexec/android-sdk";
          JAVA_HOME = "${pkgs.jdk17}";

          shellHook = ''
            export PATH="$ANDROID_HOME/platform-tools:$ANDROID_HOME/emulator:$ANDROID_HOME/cmdline-tools/latest/bin:$PATH"

            echo "Flutter: $(flutter --version | head -n 1)"
            echo "Dart:    $(dart --version 2>&1)"
            echo "Java:    $(java -version 2>&1 | head -n 1)"
            echo "SDK:     $ANDROID_HOME"
          '';
        };
      });
}