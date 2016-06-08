{ config, lib, pkgs, ... }:

with lib;

let cfg = config.services.cloud-init-custom;
  growpart = pkgs.stdenv.mkDerivation {
    name = "growpart";
    src = pkgs.fetchurl {
      url = "https://launchpad.net/cloud-utils/trunk/0.27/+download/cloud-utils-0.27.tar.gz";
      sha256 = "16shlmg36lidp614km41y6qk3xccil02f5n3r4wf6d1zr5n4v8vd";
    };
    patches = [ (pkgs.fetchurl {
                  url = "http://pkgs.fedoraproject.org/cgit/rpms/cloud-utils.git/plain/0002-Support-new-sfdisk-version-2.26.patch";
                  sha256 = "15pcr90rnq41ffspip9wwnkar4gk2la6qdhl2sxbipb787nabcg3";
                })
              ];
    buildPhase = ''
      mkdir -p $out/bin
      cp bin/growpart $out/bin
      substituteInPlace $out/bin/growpart --replace awk ${pkgs.gawk}/bin/awk --replace sed ${pkgs.gnused}/bin/sed
    '';
    dontInstall = true;
    dontPatchShebangs = true;
  };
  waitNetworkUp = pkgs.writeScriptBin "wait-network-up" ''
    #!${pkgs.bash}/bin/bash
    while true; do
      echo "Checking for IPv4 default route"
      netstat -rn | grep -q '^0\.0\.0\.0' && break
      sleep 1
    done
    echo "Default route present, marking network as up"
  '';

    path = with pkgs; [ cloud-init nettools utillinux e2fsprogs shadow dmidecode openssh growpart ];
    configFile = pkgs.writeText "cloud-init.cfg"
      ''
        system_info:
          distro: nixos
          default_user:
            name: nixos

        users:
          - default

        disable_root: true
        preserve_hostname: false

        growpart:
          mode: auto
          devices: ["/"]
          resize_rootfs: True
          resize_rootfs_tmp: /dev

        syslog_fix_perms: root:root

        cloud_init_modules:
          - migrator
          - seed_random
          - bootcmd
          - write-files
          - growpart
          - resizefs
          - set_hostname
          - update_hostname
          - update_etc_hosts
          - ca-certs
          - rsyslog
          - users-groups
          - ssh

        cloud_config_modules:
          - emit_upstart
          - disk_setup
          - mounts
          - ssh-import-id
          - set-passwords
          - timezone
          - disable-ec2-metadata
          - runcmd

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
      '';
in
{
  options = {

    services.cloud-init-custom = {

      enable = mkOption {
        type = types.bool;
        default = false;
        description = ''
          Enable the cloud-init service. This services reads
          configuration metadata in a cloud environment and configures
          the machine according to this metadata.

          This configuration is not completely compatible with the
          NixOS way of doing configuration, as configuration done by
          cloud-init might be overriden by a subsequent nixos-rebuild
          call. However, some parts of cloud-init fall outside of
          NixOS's responsibility, like filesystem resizing and ssh
          public key provisioning, and cloud-init is useful for that
          parts. Thus, be wary that using cloud-init in NixOS might
          come as some cost.
        '';
      };

      configFile = mkOption {
        type = types.nullOr types.path;
	default = null;
	description = ''
	  File to be installed as /etc/nixos/configuration.nix
	'';
      };
    };

  };

  config = mkIf cfg.enable {

    environment.etc."cloud/cloud.cfg".source = configFile;

    systemd.services.wait-network-up =
      { description = "Check network target";
        wantedBy = [ "multi-user.target" ];
        wants = [ "network.target" ];
        after = [ "network.target" ];

        path = path;
        serviceConfig =
          { Type = "oneshot";
            ExecStart = "${waitNetworkUp}/bin/wait-network-up";
            RemainAfterExit = "yes";
            TimeoutSec = "0";
            StandardOutput = "journal+console";
          };
      };

  systemd.services.cloud-init-local =
      { description = "Initial cloud-init job (pre-networking)";
        wantedBy = [ "multi-user.target" ];
        wants = [ "local-fs.target" ];
        after = [ "local-fs.target" ];
        path = path;
        serviceConfig =
          { Type = "oneshot";
            ExecStart = "${pkgs.cloud-init}/bin/cloud-init init --local";
            RemainAfterExit = "yes";
            TimeoutSec = "0";
            StandardOutput = "journal+console";
          };
      };

    systemd.services.cloud-init =
      { description = "Initial cloud-init job (metadata service crawler)";
        wantedBy = [ "multi-user.target" ];
        wants = [ "local-fs.target" "cloud-init-local.service" "sshd.service" "sshd-keygen.service" ];
        after = [ "local-fs.target" "wait-network-up.service" "cloud-init-local.service" ];
        before = [ "sshd.service" "sshd-keygen.service" ];
        requires = [ "network.target "];
        path = path;
        serviceConfig =
          { Type = "oneshot";
            ExecStart = "${pkgs.cloud-init}/bin/cloud-init init";
            RemainAfterExit = "yes";
            TimeoutSec = "0";
            StandardOutput = "journal+console";
          };
      };

    systemd.services.cloud-config =
      { description = "Apply the settings specified in cloud-config";
        wantedBy = [ "multi-user.target" ];
        wants = [ "wait-network-up.service" ];
        after = [ "wait-network-up.service" "syslog.target" "cloud-config.target" ];

        path = path;
        serviceConfig =
          { Type = "oneshot";
            ExecStart = "${pkgs.cloud-init}/bin/cloud-init modules --mode=config";
            RemainAfterExit = "yes";
            TimeoutSec = "0";
            StandardOutput = "journal+console";
          };
      };

    systemd.services.cloud-final =
      { description = "Execute cloud user/final scripts";
        wantedBy = [ "multi-user.target" ];
        wants = [ "wait-network-up.service" ];
        after = [ "wait-network-up.service" "syslog.target" "cloud-config.service" "rc-local.service" ];
        requires = [ "cloud-config.target" ];
        path = path;
        serviceConfig =
          { Type = "oneshot";
            ExecStart = "${pkgs.cloud-init}/bin/cloud-init modules --mode=final";
            RemainAfterExit = "yes";
            TimeoutSec = "0";
            StandardOutput = "journal+console";
          };
      };

    systemd.targets.cloud-config =
      { description = "Cloud-config availability";
        requires = [ "cloud-init-local.service" "cloud-init.service" ];
      };
  };
}
