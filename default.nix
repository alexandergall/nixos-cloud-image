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

    cpFileToStore = name: file:
      runCommand name {}
      ''
        cp ${file} $out
      '';
    cloudModule = cpFileToStore "cloud-init-module" ./nixos/modules/services/system/cloud-init.nix;
    cloudInitPatch = cpFileToStore "cloud-init-patch" ./cloud-init-0.7.6.patch;
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

            boot.kernelParams = [ "console=ttyS0" ];
            boot.loader.grub.device = "/dev/vda";
            boot.loader.timeout = 0;

            services.openssh.enable = true;
            services.openssh.permitRootLogin = "without-password";

            users.extraUsers.nixos = {
              isNormalUser = true;
            };
            security.sudo.extraConfig = '''
              nixos ALL=(ALL:ALL) NOPASSWD: ALL
            ''';

            services.cloud-init-custom.enable = true;

            nixpkgs.config.packageOverrides = pkgs: rec {
              cloud-init = pkgs.cloud-init.overrideDerivation (oldAttrs: {
                patches = [ ${cloudInitPatch} ];
                patchPhase = oldAttrs.patchPhase + '''
                  substituteInPlace cloudinit/sources/DataSourceAltCloud.py \
                    --replace /usr/sbin/dmidecode ''${pkgs.dmidecode}/bin/dmidecode \
                    --replace /sbin/modprobe ''${pkgs.kmod}/bin/modprobe \
                    --replace /sbin/udevadm ''${config.systemd.package}/sbin/udevadm
                  patchPhase
                ''';
              });
            };
          }
        '');

    cloudImageModule = { config, lib, pkgs, ... }:
      {

        system.build.cloudImage = import nixos/lib/make-disk-image.nix {
          inherit pkgs lib config channel;
	  configFile = mkConfigFile "final-config"
                         ''
                           <nixpkgs/nixos/modules/profiles/qemu-guest.nix>
                               ${cloudModule}
                         '';
          partitioned = true;
          diskSize = 1 * 1024;
        };
      };

    extraConfig = {
      system.extraDependencies = [ cloudModule cloudInitPatch channel ];
    };

    eval = import (channel + "/nixos/nixos/lib/eval-config.nix") {
      modules = [ cloudImageModule
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
