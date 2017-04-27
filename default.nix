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
    cloudInitPatch = cpFileToStore "cloud-init-patch" ./cloud-init.patch;
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
              cloud-utils = pkgs.cloud-utils.overrideAttrs (oldAttrs: rec {
                buildPhase = '''
                  mkdir -p $out/bin
                  cp bin/growpart $out/bin/growpart
                  wrapProgram $out/bin/growpart --prefix PATH : "''${with pkgs; stdenv.lib.makeBinPath [ gnused gawk utillinux ]}"
                ''';
              });

              cloud-init =  pkgs.cloud-init.overrideAttrs (oldAttrs: rec {
                version = "0.7.9";
                name = "cloud-init-''${version}";
                namePrefix = "";
                src = pkgs.fetchurl {
                  url = "https://launchpad.net/cloud-init/trunk/''${version}/+download/cloud-init-''${version}.tar.gz";
                  sha256 = "0wnl76pdcj754pl99wxx76hkir1s61x0bg0lh27sdgdxy45vivbn";
                };

                patches = [ ${cloudInitPatch} ];
                prePatch = '''
                  patchShebangs ./tools

                  substituteInPlace setup.py \
                    --replace /usr $out \
                    --replace /etc $out/etc \
                    --replace /lib/systemd $out/lib/systemd \
                    --replace 'self.init_system = ""' 'self.init_system = "systemd"'

                    substituteInPlace cloudinit/config/cc_growpart.py \
                      --replace 'util.subp(["growpart"' 'util.subp(["''${cloud-utils}/bin/growpart"'
                ''';

                ## For some reason, the patch phase is not executet in an overridden package
                ## without this
                patchPhase = '''
                  patchPhase
                ''';

                propagatedBuildInputs = with pkgs.pythonPackages; [ cheetah jinja2 prettytable
                  oauthlib pyserial configobj pyyaml argparse requests jsonpatch ];

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
