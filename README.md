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

By default, the image uses the newest kernel available in the NixOS
distribution defined by the package `linuxPackages_latest`.  This can
be changed by setting the argument `kernelLatest` of the default Nix
expression to `false`, i.e. with `nix-build --arg kernelLatest false`.
In that case, the kernel is defined by the package `linuxPackages`.

On a running instance, the kernel can be selected by setting the
option `boot.kernelPackages` in `/etc/nixos/configuration.nix`.

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

To use the default kernel of the distribution, execute
```
$ NIX_PATH=`pwd` nix-build --arg kernelLatest false
```

The size of the image is 1GiB by default.  A different size can be
selected by setting the `diskSize` parameter (in units of MiB), e.g.
```
$ NIX_PATH=`pwd` nix-build --arg diskSize 2048
```

After a successful build, the current directory contains a symlink
`result` which points to the location in the Nix store where the disk
image is stored.
