# nixos-cloud-image

Disk image for an OpenStack-based cloud. Up to NixOS 16.09, there was
no working cloud-init Module.  The branch `nixos-16.09` builds a cloud
image for those NixOS versions. The tricky part is to integrate the
customization in manner that still allows the image to use the
standard NixOS channel.

Most of the required changes have been upstreamed to 17.03, but not
all of them.  The branch nixos-17.03 builds an image for that version.

Starting with 17.09, NixOS can create a working cloud image out of the
box.  The master branch of this repository now only contains a
customization of the default cloud-init configuration, which
essentially only adds a user `nixos` for initial access with full
`sudo` privileges (`root` login is not permitted).  It also creates a
`raw` image instead of `qcow2`.

# Usage

To create an image, run

```
$ NIX_PATH=<path-to-nixpkgs> nix-build
```

in the cloned repository, where `<path-to-nixpkgs>` is the path to an
instance of the `nixpkgs` distribution for which you want to build the
image (must be at least 17.09).  For example:

```
$ git clone https://github.com/alexandergall/nixos-cloud-image.git
$ cd nixos-cloud-image
$ git clone https://github.com/NixOS/nixpkgs.git
$ cd nixpkgs
$ git checkout release-17.09
$ cd ..
$ NIX_PATH=`pwd` nix-build
```

