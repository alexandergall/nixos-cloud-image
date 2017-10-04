{}:
let
  eval = import <nixpkgs/nixos/lib/eval-config.nix> {
    modules = [ ./nova-image.nix ];
  };
in
{
  inherit (eval.config.system.build) novaImage;
}
