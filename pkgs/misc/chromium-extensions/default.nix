{ stdenv, pkgs }:
let
  inherit (import ./build-chromium-extension.nix { inherit stdenv pkgs; }) buildChromiumExtension;
in {
  decentraleyes = pkgs.callPackage ./extensions/decentraleyes { inherit buildChromiumExtension; };

  https-everywhere = pkgs.callPackage ./extensions/https-everywhere { inherit buildChromiumExtension; };

  ublock-origin = pkgs.callPackage ./extensions/ublock-origin { inherit buildChromiumExtension; };
}
