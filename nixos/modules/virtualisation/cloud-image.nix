{ config, lib, pkgs, ... }:

{

  system.build.cloudImage = import (pkgs.path + "/nixpkgs/nixos/lib/make-disk-image.nix") {
    inherit pkgs lib config;
    inherit (config.services.cloud-init-custom) configFile;
    partitioned = true;
    diskSize = 1 * 1024;
  };

}
