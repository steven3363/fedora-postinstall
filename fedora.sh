#!/usr/bin/env bash
nomusic=false
while [[ $# -gt 0 ]]; do
  key="$1"
  case $key in
    -n|--nomusic)
	  nomusic=true
	  echo -e "\033[0;36mINFO\033[0m: Music packages are disabled. Fedora Jam+ Will not be installed."
      shift # past argument
      ;;
  esac
done
#fancy stuff

spinner()
{
	local args=">> $*"
	local count="${#args}"
    local pid=$!
    local delay=0.1
    local spinstr='|/-\'
    while [ "$(ps a | awk '{print $1}' | grep $pid)" ]; do
        local temp=${spinstr#?}
        printf "[\033[0;34m%c\033[0m] %s" "$spinstr" "$args"
        local spinstr=$temp${spinstr%"$temp"}
        sleep $delay
        printf "\b\b\b\b\b\b\b\b"
		for i in $(seq $count); do
		printf "\b"
		done
    done
    printf "   \b\b\b\b\b"
}

#Dependencies funny lol
if ! command -v figlet &> /dev/null
then
    sudo dnf install figlet -yq
fi

clear
figlet UML-Lite
echo "Ultramarine Environment deployment script for Fedora"

PACKAGE_LIST=(
	cascadia-code-fonts
	cascadia-code-pl-fonts
	gnome-boxes
	handbrake
	gnome-extensions-app
	gnome-tweaks
	python3
	python3-pip
	neofetch
	pv
	wget
	yabridge
	java-latest-openjdk
	java-11-openjdk
	python3-pip
	kernel-xanmod-edge
	fwupd
	virt-manager
	v4l2loopback
	
)

FLATPAK_LIST=(
	org.telegram.desktop

)
if [ -f .stage3 ]; then
	figlet STAGE 3
	sudo echo "Root Check!"
	echo ">> You're almost done!"
	echo ">> Installing extra packages..."

	#FJ+ setup
	if [ $nomusic = true ]; then
	{
		sudo dnf copr enable cappyishihara/fedorajam-plus
		sudo dnf --disablerepo fedora --disablerepo updates install wine yabridge
	} &> /dev/null & spinner "Setting up Fedora Jam+..."
	echo ">> Setting up Fedora Jam+...done!"
	else
	echo -e "\033[0;36mINFO\033[0m: Music packages are disabled. Fedora Jam+ Will not be installed."
	fi


	#discord setup
	pushd rpmbuild/discord &> /dev/null || return 127
	yes | ./create-package.sh canary & spinner Installing Discord Canary...
	echo ">> Installing Discord Canary...done!"
	popd &> /dev/null || return 127

	#OBS setup

	pushd rpmbuild/obs-studio.spec &> /dev/null || return 127 
	sudo dnf builddep obs-studio.spec -yq
	{
		./build.sh
		cp f_downloads/* ~/rpmbuild/SOURCES/
		rpmbuild -bb obs-studio.spec
	} &> /dev/null & spinner Compiling OBS Studio + CEF Browser source...
	pushd ~/rpmbuild/RPMS/x86_64/ &> /dev/null || exit
	sudo dnf install ./obs* -y
	popd &> /dev/null || exit
	echo ">> Installing OBS Studio + CEF Browser source...done!"
	popd &> /dev/null || return 127


	rm ~/.config/autostart/postinstall.desktop
	rm .stage3
	echo ">> Configuration done!"

elif [ ! -f .stage2 ]; then

	# gnome settings
	wget -qO- https://raw.githubusercontent.com/Bonandry/adwaita-plus/master/install.sh | sh
	gsettings set org.gnome.desktop.interface gtk-theme "Adwaita-dark"
	gsettings set org.gnome.desktop.interface icon-theme "Adwaita++-Dark-Colorful"
	sed "s/changeme/$USER/g" gdm-custom.conf > custom.conf
	sudo cp custom.conf /etc/gdm/custom.conf
	rm custom.conf

	# enable rpmfusion
	sudo dnf install https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-$(rpm -E %fedora).noarch.rpm https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-$(rpm -E %fedora).noarch.rpm -yq & spinner "Installing RPMFusion Repos..."

	
	sudo dnf groupupdate core -yq & spinner Updating core packages...

	# install development tools
	
	{
		sudo dnf groupinstall "Development Tools" -yq 
		sudo dnf groupinstall "RPM Development Tools" -yq
	} & spinner Installing dev tools...
	echo ">> Installing dev tools...done!"

	{
		sudo dnf groupupdate multimedia --setop="install_weak_deps=False" --exclude=PackageKit-gstreamer-plugin -yq

		sudo dnf groupupdate sound-and-video -yq
	} & spinner Updating multimedia packages...
	echo ">> Updating multimedia packages...done!"
	# fedora better fonts
	{
		sudo dnf copr enable dawid/better_fonts -yq &> /dev/null
		sudo dnf install fontconfig-enhanced-defaults fontconfig-font-replacements -yq
	} & spinner Setting up Better fonts...
	echo ">> Setting up Better fonts...done!"
	# add flathub repository
	sudo flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo

	# add third party software
	
	echo ">> Adding COPR Repos..."
	{
		sudo dnf copr enable sentry/v4l2loopback -yq
		sudo dnf copr enable atim/heroic-games-launcher -yq
	} &> /dev/null
	printf "\bdone!"
	# update repositories

	sudo dnf check-update -yq

	echo "-----------PACKAGE SETUP----------------"
	# iterate through packages and installs them if not already installed
	for package_name in ${PACKAGE_LIST[@]}; do
		if ! sudo dnf list --installed | grep -q "^\<$package_name\>"; then
			echo "installing $package_name..."
			sleep .5
			sudo dnf install "$package_name" -y &> /dev/null & spinner "Installing $package_name..."
			echo "Installing $package_name...done!"
		else
			echo "$package_name already installed!"
		fi
	done

	for flatpak_name in ${FLATPAK_LIST[@]}; do
		if ! flatpak list | grep -q $flatpak_name; then
			flatpak install "$flatpak_name" -y & spinner
		else
			echo "$package_name already installed"
		fi
	done
	echo "-----------PACKAGE SETUP DONE-----------"
	sudo usermod -aG mock,qemu,kvm $USER

	# add protonup (now that prerequisites are fulfilled)
	pip install protonup


	# add mesa-aco from GloriousEggroll
	sudo dnf copr enable gloriouseggroll/mesa-aco -yq &> /dev/null & spinner Adding mesa-aco...

	# upgrade packages
	sudo dnf distro-sync -y && sudo dnf update --refresh -y && flatpak update -y && flatpak remove --unused && sudo fwupdmgr get-updates & spinner Updating system...
	sudo dnf autoremove -yq & spinner Cleaning up packages...
	#set default kernel to xanmod
	sudo grubby --set-default $(ls /boot | grep vmlinuz | grep xm)

	#prepare for stage 2
	touch .stage2
	sed "s|changeme|$PWD/fedora.sh|g" postinstall.desktop | sed "s|chme|$PWD|g" > ~/.config/autostart/postinstall.desktop

	echo "************************************************"
	echo "Rebooting machine in 10 seconds..."
	echo "************************************************"
	sleep 10
	reboot
else
	figlet STAGE 2
	echo ">> Installing NVIDIA Drivers..."
	sudo dnf install akmod-nvidia -y
	echo ">> Installing dotfiles..."
	cp -R dotfiles/.config ~/.config
	sed -i "s|changeme|$USER|g" ~/.config/neofetch/config.conf
	mv .stage2 .stage3
	echo "************************************************"
	echo "Rebooting machine in 10 seconds..."
	echo "************************************************"
	sleep 10
	reboot
fi

