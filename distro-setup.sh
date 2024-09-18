#!/usr/bin/env bash
#
# Set up a new distro with desired software and personal configuration.
SCRIPT=${0##*/}

PACKAGES_FILE=./packages.txt
FLATPAKS_FILE=./flatpaks.txt
KEYD_URL='https://github.com/rvaiya/keyd/archive/refs/tags/v2.4.3.tar.gz'
TRESORIT_URL='https://installer.tresorit.com/tresorit_installer.run'
UNWANTED_SW=( rhythmbox gnome-tour yelp simple-scan )

function Print_Usage {
    # Tab indents below
    cat <<-EoH
		Usage: Set up new distro with desired software and configuration.
		Specify flatpaks in: $FLATPAKS_FILE
		Specify packages in: $PACKAGES_FILE
		EoH
    # Tab indents above
    exit
}

function Log_Info {
    echo "INFO: $*"
}

function Extend_sudo_timeout {
    if sudo grep --quiet 'timestamp_timeout=60' \
      /etc/sudoers /etc/sudoers.d/99-sudo-timeout.conf 2>/dev/null; then
        return
    fi
    # Tab indents below
    cat <<-EOF | sudo tee /etc/sudoers.d/99-sudo-timeout.conf
	Defaults timestamp_type=global,timestamp_timeout=60
	EOF
    # Tab indents above
    Log_Info "Extended sudo timeout, may need to re-authenticate"
    sudo --reset-timestamp
}

function Set_Hostname {
    if grep --quiet --extended-regexp \
          --regexp fedora \
          --regexp ubuntu \
          --regexp debian \
          --regexp localhost \
          --regexp '^$' \
            /etc/hostname; then
        Log_Info "Configuring hostname"
        read -rp "Enter desired hostname: " system_hostname
        sudo hostnamectl set-hostname "$system_hostname"
    fi
}

function Check_Distro_Family {
    if type rpm &>/dev/null; then
        Log_Info "Distro family is ${distro_family:=rpm}"
    elif type dpkg &>/dev/null; then
        Log_Info "Distro family is ${distro_family:=deb}"
    else
        Log_Info "Could not determine distro family, exiting" >&2
        exit 1
    fi
}

function Update_System {
    Log_Info "Updating system"
    case $distro_family in
        rpm)
            sudo dnf update --assumeyes >/dev/null ;;
        deb)
            sudo apt-get update >/dev/null
            sudo apt-get upgrade --assume-yes >/dev/null ;;
    esac
}

function Install_Packages {
    Log_Info "Installing packages from $PACKAGES_FILE"

    if [[ ! -s "$PACKAGES_FILE" ]]; then
        Log_Info "$PACKAGES_FILE missing, exiting"
        exit 1
    fi

    case $distro_family in
        rpm) xargs --arg-file="$PACKAGES_FILE" \
               sudo dnf install --assumeyes 2>&1 \
               | grep --invert-match 'already installed' ;;
        deb) xargs --arg-file="$PACKAGES_FILE" \
               sudo apt-get install --assume-yes 2>&1 \
               | grep --invert-match 'already installed' ;;
    esac
}

function Install_Flatpaks {
    if ! flatpak remotes | grep --quiet flathub; then
        Log_Info "Adding flathub repo"
        sudo flatpak remote-add --if-not-exists flathub \
          https://dl.flathub.org/repo/flathub.flatpakrepo
    fi

    if [[ ! -s "$FLATPAKS_FILE" ]]; then
        Log_Info "$FLATPAKS_FILE missing, exiting"
        exit 1
    fi

    Log_Info "Installing packages from $FLATPAKS_FILE"
    # Note: this doesn't work over SSH
    xargs --arg-file="$FLATPAKS_FILE" \
      flatpak install --assumeyes --noninteractive 2>&1 \
      | grep --invert-match 'Skipping'
}

function Install_VSC {
    if type code &>/dev/null; then
        return
    fi
    Log_Info "Installing VSC"
    if [[ $distro_family == "rpm" ]]; then
        sudo rpm --import https://packages.microsoft.com/keys/microsoft.asc
        # Tab indents below
        cat <<-EOF | sudo tee /etc/yum.repos.d/vscode.repo
			[code]
			name=Visual Studio Code
			baseurl=https://packages.microsoft.com/yumrepos/vscode
			enabled=1
			gpgcheck=1
			gpgkey=https://packages.microsoft.com/keys/microsoft.asc
			EOF
        # Tab indents above
        dnf check-update
        sudo dnf install code --assumeyes
    elif [[ $distro_family == "deb" ]]; then
        echo "code code/add-microsoft-repo boolean true" \
          | sudo debconf-set-selections
        sudo apt-get install apt-transport-https
        sudo apt-get update
        sudo apt-get install code --assume-yes
    fi

}

function Install_keyd {
    if type keyd &>/dev/null; then
        return
    fi
    local KEYD_TARBALL="${KEYD_URL##*/}"
    (
        cd "$(mktemp --directory)" || exit
        curl --remote-name --location "$KEYD_URL" \
          || { Log_Info "Failed to download keyd"; exit 1; }
        tar xzf "$KEYD_TARBALL"
        cd "$(tar tzf "$KEYD_TARBALL" | head -1)" || exit
        make
        sudo make install
        sudo systemctl enable --now keyd
    )
    # Tab indents below
    cat <<-EOF | sudo tee /etc/keyd/default.conf
		[ids]
		
		*
		
		[main]
		
		# Map capslock to control.
		capslock = leftcontrol
		EOF
    # Tab indents above
}

function Install_Tailscale {
    if type tailscale &>/dev/null; then
        return
    fi
    Log_Info "Installing Tailscale"
    curl --fail --silent --show-error --location \
      https://tailscale.com/install.sh | sh
}

function Install_Tresorit {
    if [[ -d $HOME/.local/share/tresorit ]]; then
        return
    fi
    Log_Info "Installing Tresorit"
    (
        cd "$(mktemp --directory)" || exit
        curl --remote-name --location "$TRESORIT_URL" \
          || { Log_Info "Failed to download tresorit"; exit 1; }
        { echo n; echo n; } | sh ./tresorit_installer.run
    )
}

function Install_Ubuntu_fonts {
    if fc-list | grep --quiet ubuntu; then
        return
    elif [[ $distro_family == rpm ]] \
      && rpm -qa | grep fontconfig-font-replacements &>/dev/null; then
        return
    else
        Log_Info "Installing Ubuntu fonts"
        if [[ $distro_family == "rpm" ]]; then
            sudo dnf copr enable hyperreal/better_fonts --assumeyes
            sudo dnf install fontconfig-font-replacements --assumeyes
        elif [[ $distro_family == "deb" ]]; then
            sudo apt-get install --assume-yes fonts-ubuntu
        fi
        sudo fc-cache -f &>/dev/null
    fi
}

function Remove_Unwanted_SW {
    if [[ $distro_family == rpm ]]; then
        Log_Info "Removing unwanted software"
        xargs <<<"${UNWANTED_SW[@]}" sudo dnf remove --assumeyes 2>&1 \
          | grep --invert-match 'No match for'
    fi
}

function Setup_SSH_keys {
    if [[ ! -f "$HOME/.ssh/id_ed25519" ]]; then
        Log_Info "Generating SSH keys"
        ssh-keygen -t ed25519 \
                   -C "${USER}@$(hostname)" \
                   -N "" \
                   -f "$HOME/.ssh/id_ed25519"
    fi
}

function Prompt_for_Reboot {
    read -r -p "Do you want to reboot now? [y/N]: " response
    if [[ "$response" =~ ^([yY][eE][sS]|[yY])$ ]]; then
        sudo reboot
    fi
}

if [[ $1 == '-h' || $1 == '--help' ]]; then
    Print_Usage
fi

Log_Info "${SCRIPT} - setting up distro"
Log_Info "sudo is required"
Extend_sudo_timeout
sudo --validate

Set_Hostname
Setup_SSH_keys
Check_Distro_Family
Update_System

Install_Packages
Install_Flatpaks
Install_VSC
Install_keyd
Install_Ubuntu_fonts

Remove_Unwanted_SW

Log_Info "Updating tldr cache"
tldr --update

Install_Tresorit
Install_Tailscale

Log_Info "Enabling syncthing service unit"
sudo systemctl enable --now "syncthing@${USER}.service"
Log_Info "Access syncthing - http://localhost:8384"

Log_Info "Setup complete"
Prompt_for_Reboot
