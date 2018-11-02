{ kernelLatest ? true, diskSize ? 1024 }:

with import <nixpkgs> {};
with lib;

let
  cloudInitConfig =
    ''
       system_info:
         distro: nixos
         default_user:
           name: nixos

       users:
         - default

       disable_root: true
       preserve_hostname: false

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
    '';

  indentBlock = count: text:
    let
      spaces = concatStrings (genList (i: " ") count);
      lines = splitString "\n" text;
    in
      concatStringsSep "\n" (map (line: concatStrings [ spaces line ])
                             lines);

  configFile = pkgs.writeText "configuration.nix"
    (''
      { config, lib, pkgs, ... }:

      with lib;

      {
        imports = [ <nixpkgs/nixos/modules/virtualisation/nova-config.nix> ];

        systemd.services = {
          ## nova-config.nix disables these via profiles/headless.nix
          "serial-getty@ttyS0".enable = pkgs.lib.mkForce true;
          "getty@tty1".enable = pkgs.lib.mkForce true;
          ## For some reason, getty@.service is missing
          ## a dependency on the getty.target.
          "getty@tty1".wantedBy = [ "getty.target" ];
        };

        boot.kernelParams = [ "console=tty1" ];
      '' +  (if kernelLatest == true then
            "  boot.kernelPackages = pkgs.linuxPackages_latest;\n\n"
          else
            "") +
    ''
        services.openssh = {
          authorizedKeysFiles = mkOverride 1 [ ".ssh/authorized_keys" ];
        };

        users.extraUsers.nixos = {
          isNormalUser = true;
        };

        security.sudo.extraConfig = '''
          nixos ALL=(ALL:ALL) NOPASSWD: ALL
        ''';

        services.cloud-init.config =
          '''
      ${indentBlock 6 cloudInitConfig}
          ''';
      }
    '');

  novaImageModule =
    { config, lib, pkgs, ... }:

    with lib;

    {
      system.build.novaImage = import <nixpkgs/nixos/lib/make-disk-image.nix> {
        inherit lib config diskSize configFile;
        pkgs = import <nixpkgs> { inherit (pkgs) system; }; # ensure we use the regular qemu-kvm package
        format = "raw";
      };
    };

  eval = import <nixpkgs/nixos/lib/eval-config.nix> {
    modules = [ (import configFile) novaImageModule ];
  };
in
{
  inherit (eval.config.system.build) novaImage;
}
