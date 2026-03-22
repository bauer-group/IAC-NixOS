# Makes pkgs.unstable.* available in all modules.
# Usage: pkgs.unstable.somePackage (latest from nixos-unstable channel)
nixpkgs-unstable: final: prev: {
  unstable = import nixpkgs-unstable {
    inherit (final) config;
    inherit (final.stdenv.hostPlatform) system;
  };
}
