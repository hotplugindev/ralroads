{
  description = "Minimal Flutter dev shell";

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

        # Force a completely empty SDK composition so it doesn't pull 19GB of data
        minimalAndroidSdk = (pkgs.androidenv.composeAndroidPackages {
          includeEmulator = false;
          includeSystemImages = false;
          includeSources = false;
        }).androidsdk;
      in
      {
        devShells.default = pkgs.mkShell {
          packages = with pkgs; [
            flutter
            android-tools
            minimalAndroidSdk
          ];

          ANDROID_HOME = "${minimalAndroidSdk}/libexec/android-sdk";
          ANDROID_SDK_ROOT = "${minimalAndroidSdk}/libexec/android-sdk";
        };
      });
}