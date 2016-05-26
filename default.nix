{ nixpkgs ? { outPath = ./nixpkgs; } }:
with import nixpkgs {};
with lib;
with builtins;

let
  nixpkgsRevs = if ! (hasAttr "revCount" nixpkgs) then
    import (runCommand "get-rev-count"
      { preferLocalBuild = true;
        inherit nixpkgs;
        buildInputs = [ pkgs.git ];
        ## Force execution for every invocation because there
        ## is no easy way to detect when the Git rev has changed.
        ## dummy = currentTime;
      }
      ''
        git=${git}/bin/git
        cd ${nixpkgs}
        revision=$($git rev-list --max-count=1 HEAD)
        revCount=$($git rev-list $revision | wc -l)
        shortRev=$($git rev-parse --short $revision)
        echo "{ revCount = $revCount; shortRev = \"$shortRev\"; }" >$out
      '')
    else
      {};

    channel = let
      channelSrc = (import (nixpkgs + "/nixos/release.nix") {
        nixpkgs = nixpkgs // nixpkgsRevs;
        stableBranch = true;
      }).channel;
      channelTarPath = unsafeDiscardStringContext (channelSrc + "/tarballs/"
        + (head (attrNames (readDir (channelSrc + "/tarballs")))));
        releaseName = removeSuffix ".tar.xz" (baseNameOf channelTarPath);
    in import <nix/unpack-channel.nix> {
      channelName = "nixos";
      name = "${releaseName}";
      src = channelTarPath;
    };

    cloudModule = runCommand "cloud-init-module"
      {}
      ''
        cp ${builtins.toPath nixos/modules/services/system/cloud-init.nix} $out
      '';
    mkConfigFile = name: imports:
      builtins.toPath (pkgs.writeText "${name}"
        ''
          { config, lib, pkgs, ... }:

          with lib;

          {
            imports = [
              ${imports}
            ];

            fileSystems."/".device = "/dev/disk/by-label/nixos";

            boot.kernelParams = [ "console=ttyS0,115200" "console=tty0" "vga=normal" "nofb" ];
            boot.loader.grub.device = "/dev/vda";
            boot.loader.grub.timeout = 0;

            # Allow root logins
            services.openssh.enable = true;
            services.openssh.permitRootLogin = "without-password";

            services.cloud-init-custom.enable = true;

            nixpkgs.config.packageOverrides = pkgs: rec {
              cloud-init = pkgs.cloud-init.overrideDerivation (oldAttrs: {
                patchPhase = oldAttrs.patchPhase + '''
                  substituteInPlace cloudinit/sources/DataSourceAltCloud.py \
                    --replace /usr/sbin/dmidecode ''${pkgs.dmidecode}/bin/dmidecode \
                    --replace /sbin/modprobe ''${config.system.sbin.modprobe}/bin/modprobe \
                    --replace /sbin/udevadm ''${config.systemd.package}/sbin/udevadm
                ''';
              });
            };
          }
        '');

    extraConfig = {
      services.cloud-init-custom.configFile = mkConfigFile "final-config"
        ''
          <nixpkgs/nixos/modules/profiles/qemu-guest.nix>
              ${cloudModule}
        '';
      system.extraDependencies = [ cloudModule ];
    };

    eval = import (channel + "/nixos/nixos/lib/eval-config.nix") {
      modules = [ ./nixos/modules/virtualisation/cloud-image.nix
                  (mkConfigFile "build-config"
                    ''
                      ${channel + "/nixos/nixos/modules/profiles/qemu-guest.nix"}
                          ${./nixos/modules/services/system/cloud-init.nix}
                    '')
                  extraConfig ];
    };

    version = writeTextDir "nixos-disk-image-version"
      ''${eval.config.system.nixosVersion}'';
in

{ inherit (eval.config.system.build) cloudImage;
  inherit version; }
