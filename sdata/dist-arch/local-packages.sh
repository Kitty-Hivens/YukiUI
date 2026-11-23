# This is NOT a script for execution, but for loading functions, so NOT need execution permission or shebang.
# shellcheck shell=bash

# The packages this repository builds itself, from the PKGBUILDs beside this
# file, and how one is built. Shared by the installer, which builds them all,
# and by the updater, which builds the ones whose PKGBUILD has moved on from
# what is installed.

LOCAL_PKGBUILDS=(./sdata/dist-arch/illogical-impulse-{audio,backlight,basic,fonts-themes,gtk,portal,python,screencapture,toolkit,widgets})
LOCAL_PKGBUILDS+=(./sdata/dist-arch/illogical-impulse-hyprland)
LOCAL_PKGBUILDS+=(./sdata/dist-arch/illogical-impulse-microtex-git)
LOCAL_PKGBUILDS+=(./sdata/dist-arch/yuki-quickshell)
LOCAL_PKGBUILDS+=(./sdata/dist-arch/illogical-impulse-bibata-modern-classic-bin)
LOCAL_PKGBUILDS+=(./sdata/dist-arch/illogical-impulse-material-originals-icons)
LOCAL_PKGBUILDS+=(./sdata/dist-arch/yuki-hyprland-plugins)

# https://github.com/end-4/dots-hyprland/issues/581
# yay -Bi is kinda hit or miss, instead cd into the relevant directory and manually source and install deps
install-local-pkgbuild() {
  local location=$1
  local installflags=$2

  x pushd $location

  source ./PKGBUILD
  x yay -S --sudoloop $installflags --asdeps "${depends[@]}"
  # man makepkg:
  # -A, --ignorearch: Ignore a missing or incomplete arch field in the build script.
  # -s, --syncdeps: Install missing dependencies using pacman. When build-time or run-time dependencies are not found, pacman will try to resolve them.
  # -f, --force: build a package even if it already exists in the PKGDEST
  x makepkg -Afs --noconfirm
  # Installed by pacman rather than by makepkg -i. A package that takes over
  # one installed under another name conflicts with it, and makepkg -i under
  # --noconfirm answers no to removing it, so the update stopped there. pacman
  # is told to answer that question yes (--ask 4, a conflict between packages).
  # Only the files this PKGBUILD builds, by --packagelist, as several versions
  # lie in the folder, and not its debug package.
  local packages=() package
  while IFS= read -r package; do
    [[ -f "$package" && "$package" != *-debug-* ]] && packages+=("$package")
  done < <(makepkg --packagelist)
  x sudo pacman -U --noconfirm --ask 4 "${packages[@]}"
  x popd
}

# The name a PKGBUILD builds, and the version it builds, the way pacman writes
# it: epoch, a colon, version, a dash, release. Read in a subshell, since
# sourcing a PKGBUILD sets variables the caller has no use for.
function local_pkgbuild_name(){
  ( source "$1/PKGBUILD" > /dev/null 2>&1; printf '%s\n' "$pkgname" )
}
function local_pkgbuild_version(){
  ( source "$1/PKGBUILD" > /dev/null 2>&1; printf '%s%s-%s\n' "${epoch:+${epoch}:}" "$pkgver" "$pkgrel" )
}

# Whether what is installed of a PKGBUILD's package is not what it builds:
# missing, or of another version.
function local_pkgbuild_outdated(){
  local name installed
  name="$(local_pkgbuild_name "$1")"
  installed="$(pacman -Q "$name" 2> /dev/null | awk '{print $2}')"
  [[ "$installed" != "$(local_pkgbuild_version "$1")" ]]
}
