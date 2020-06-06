{ kernelLatest ? true, diskSize ? 2048 }:

with import <nixpkgs> {};
with lib;

let
  cloudConfigFile = pkgs.writeText "cloud-config"
    (''
      { config, lib, pkgs, ... }:

      with lib;

      let
        waitNetworkUp = pkgs.writeScriptBin "wait-network-up" '''
          #!${pkgs.bash}/bin/bash
          PATH=''${makeBinPath [ pkgs.nettools ]}:$PATH
          while true; do
            echo "Checking for IPv4 default route"
            netstat -rn | grep -q '^0\.0\.0\.0' && break
            sleep 1
          done
          echo "Default route present, marking network as up"
        ''';
      in
      {
        imports = [ <nixpkgs/nixos/modules/profiles/qemu-guest.nix> ];

        config = {
          fileSystems."/" = {
            device = "/dev/disk/by-label/nixos";
            fsType = "ext4";
            autoResize = true;
          };

          boot.growPartition = true;
          boot.kernelParams = [ "console=tty1" ];
          boot.loader.grub.device = "/dev/vda";
          boot.loader.timeout = 0;
     '' +  (if kernelLatest == true then
              "    boot.kernelPackages = pkgs.linuxPackages_latest;\n\n"
            else
              "") +
     ''
          services.openssh = {
            enable = true;
            permitRootLogin = "prohibit-password";
            passwordAuthentication = mkDefault false;
            authorizedKeysFiles = mkOverride 1 [ ".ssh/authorized_keys" ];
          };

          # Cloud-init configuration.
          services.cloud-init.enable = true;
          services.cloud-init.config =
            '''
              system_info:
                distro: nixos
                default_user:
                  name: nixos

              users:
                - default

              disable_root: true
              preserve_hostname: false
              datasource_list: [ 'OpenStack', 'Ec2' ]

              cloud_init_modules:
                - migrator
                - seed_random
                - bootcmd
                - write-files
                - growpart
                - resizefs
                - update_etc_hosts
                - ca-certs
                - rsyslog
                - users-groups

              cloud_config_modules:
                - disk_setup
                - mounts
                - ssh-import-id
                - set-passwords
                - timezone
                - disable-ec2-metadata
                - runcmd
                - ssh

              cloud_final_modules:
                - rightscale_userdata
                - scripts-vendor
                - scripts-per-once
                - scripts-per-boot
                - scripts-per-instance
                - scripts-user
                - ssh-authkey-fingerprints
                - keys-to-console
                - phone-home
                - final-message
                - power-state-change
            ''';

          users.extraUsers.nixos = {
            isNormalUser = true;
          };

          security.sudo.extraConfig = '''
            nixos ALL=(ALL:ALL) NOPASSWD: ALL
          ''';

          systemd.services.wait-network-up =
            { description = "Check network target";
              requiredBy = [ "network-online.target" ];
              wants = [ "network.target" ];
              after = [ "network.target" ];

              serviceConfig =
                { Type = "oneshot";
                  ExecStart = "''${waitNetworkUp}/bin/wait-network-up";
                  RemainAfterExit = "yes";
                  TimeoutSec = "0";
                  StandardOutput = "journal+console";
                };
            };
        };
      }
     '');

  configFile = pkgs.writeText "configuration.nix"
    (''
      { config, lib, pkgs, ... }:

      {
        imports = [ ./cloud-config.nix ];
      }
     '');


  cloudImageModule =
    { config, lib, pkgs, ... }:

    with lib;

    {
      system.build.cloudImage = import <nixpkgs/nixos/lib/make-disk-image.nix> {
        inherit lib config diskSize configFile;
        contents = [ { source = cloudConfigFile; target = "/etc/nixos/cloud-config.nix"; } ];
        pkgs = import <nixpkgs> { inherit (pkgs) system; }; # ensure we use the regular qemu-kvm package
        format = "raw";
      };
    };

  eval = import <nixpkgs/nixos/lib/eval-config.nix> {
    modules = [ (import cloudConfigFile) cloudImageModule ];
  };
in
{
  inherit (eval.config.system.build) cloudImage;
}
