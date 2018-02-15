{ kernelLatest ? true }:

let
  kernelSelectionModule = if kernelLatest == true then
    { config, pkgs, ... }:
      {
        boot.kernelPackages = pkgs.linuxPackages_latest;
      }
    else
      { ... }: {};

  eval = import <nixpkgs/nixos/lib/eval-config.nix> {
    modules = [ (import ./nova-image.nix { inherit kernelLatest; })
                kernelSelectionModule ];
  };
in
{
  inherit (eval.config.system.build) novaImage;
}
