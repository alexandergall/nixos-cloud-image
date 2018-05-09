{ kernelLatest ? true, diskSize ? 1024 }:

let
  eval = import <nixpkgs/nixos/lib/eval-config.nix> {
    modules = [ (import ./nova-image.nix { inherit kernelLatest diskSize; }) ];
  };
in
{
  inherit (eval.config.system.build) novaImage;
}
