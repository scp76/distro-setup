# distro-setup

Shell script to automate setup of applications and configuration on a newly installed Linux distribution.

## Features

- Set system hostname
- Generate SSH keys
- Update system
- Install packages
- Install flatpaks
- Install VSC, keyd, Tailscale, Tresorit, and Ubuntu fonts
- Remove unwanted GNOME software

## Prerequisites

- `sudo` access.
- `flatpak` installed.
- A `packages.txt` file specifying the packages to install (one per line).
- A `flatpaks.txt` file specifying the flatpaks to install (one per line).

## Usage

```shell
git clone https://github.com/bashbadger/distro-setup.git /tmp/distro-setup
cd $_
./distro-setup.sh
```

## TODO

- [x] Test on Fedora
- [ ] Test on Debian
- [ ] Add function to test if flatpak is installed and install it if missing
