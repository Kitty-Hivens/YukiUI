# This script is meant to be sourced.
# It's not for directly running.

install-yay(){
  x sudo pacman -S --needed --noconfirm base-devel
  x git clone https://aur.archlinux.org/yay-bin.git /tmp/buildyay
  x cd /tmp/buildyay
  x makepkg -o
  x makepkg -se
  x makepkg -i --noconfirm
  x cd ${REPO_ROOT}
  rm -rf /tmp/buildyay
}

remove_deprecated_dependencies(){
  printf "${STY_CYAN}[$0]: Removing deprecated dependencies:${STY_RST}\n"
  local list=()
  list+=(illogical-impulse-{microtex,pymyc-aur,oneui4-icons-git})
  list+=(hyprland-qtutils)
  list+=({quickshell,hyprutils,hyprpicker,hyprlang,hypridle,hyprland-qt-support,hyprland-qtutils,hyprlock,xdg-desktop-portal-hyprland,hyprcursor,hyprwayland-scanner,hyprland}-git)
  list+=(matugen-bin)
  for i in ${list[@]};do try sudo pacman --noconfirm -Rdd $i;done
}
# NOTE: `implicitize_old_dependencies()` was for the old days when we just switch from dependencies.conf to local PKGBUILDs.
# However, let's just keep it as references for other distros writing their `sdata/dist-<OS_GROUP_ID>/install-deps.sh`, if they need it.
implicitize_old_dependencies(){
# Convert old dependencies to non explicit dependencies so that they can be orphaned if not in meta packages
  remove_bashcomments_emptylines ./sdata/dist-arch/previous_dependencies.conf ./cache/old_deps_stripped.conf
  readarray -t old_deps_list < ./cache/old_deps_stripped.conf
  pacman -Qeq > ./cache/pacman_explicit_packages
  readarray -t explicitly_installed < ./cache/pacman_explicit_packages

  echo "Attempting to set previously explicitly installed deps as implicit..."
  for i in "${explicitly_installed[@]}"; do for j in "${old_deps_list[@]}"; do
    [ "$i" = "$j" ] && yay -D --asdeps "$i"
  done; done

  return 0
}

#####################################################################################
if ! command -v pacman >/dev/null 2>&1; then
  printf "${STY_RED}[$0]: pacman not found, it seems that the system is not ArchLinux or Arch-based distros. Aborting...${STY_RST}\n"
  exit 1
fi

# Keep makepkg from resetting sudo credentials
if [[ -z "${PACMAN_AUTH:-}" ]]; then
  export PACMAN_AUTH="sudo"
fi

showfun remove_deprecated_dependencies
v remove_deprecated_dependencies

# Issue #363
case $SKIP_SYSUPDATE in
  true) true;;
  *) v sudo pacman -Syu;;
esac

# Use yay. Because paru does not support cleanbuild.
# Also see https://wiki.hyprland.org/FAQ/#how-do-i-update
if ! command -v yay >/dev/null 2>&1;then
  echo -e "${STY_YELLOW}[$0]: \"yay\" not found.${STY_RST}"
  showfun install-yay
  v install-yay
fi

showfun implicitize_old_dependencies
v implicitize_old_dependencies

# Install core dependencies from the meta-packages
source ./sdata/dist-arch/local-packages.sh
for i in "${LOCAL_PKGBUILDS[@]}"; do
  metainstallflags="--needed"
  $ask && showfun install-local-pkgbuild || metainstallflags="$metainstallflags --noconfirm"
  v install-local-pkgbuild "$i" "$metainstallflags"
done
