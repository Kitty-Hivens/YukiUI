# Handle args for subcmd: update
# shellcheck shell=bash

showhelp(){
echo -e "Syntax: $0 update [OPTIONS]...

Brings YukiUI and the system up to date: pulls this repository, upgrades the
system's packages, rebuilds the packages built from this repository that have
moved on, and copies the files again with the desktops already installed.

Options:
  -h, --help        Show this help message
      --check       Say whether YukiUI can be updated, and change nothing.
                    Fetches from the remote, which is the one part that goes
                    over the network.
      --no-system   Leave the system's packages alone
      --no-aur      Upgrade the repositories' packages and not the AUR's
      --unattended  Ask nothing, and print a line for each step as the shell
                    reads them. AUR packages are built without their scripts
                    being shown. A conflict stops the run. Root is sudo where
                    it needs no password, and polkit's prompt otherwise.
      --files       Copy the files again even when nothing was pulled
      --offline     With --check, fetch nothing: what was fetched last time
                    is what it counts against.
      --channel C   Follow C from now on: stable, the latest release, which is
                    what a copy follows unless told otherwise, or main, every
                    commit on the main branch. A copy past the latest release
                    stays where it is on stable until a newer one comes.
"
}

UPDATE_CHECK=false
UPDATE_SYSTEM=true
UPDATE_AUR=true
UPDATE_UNATTENDED=false
UPDATE_FILES=false
UPDATE_SET_CHANNEL=""
UPDATE_OFFLINE=false
# Set by the run itself after a pull, which starts the new version of this
# script on what was there before it. Not for typing by hand.
UPDATE_CONTINUE_FROM=""

# `man getopt` to see more
para=$(getopt \
  -o h \
  -l help,check,no-system,no-aur,unattended,files,offline,channel:,continue-from: \
  -n "$0" -- "$@")
[ $? != 0 ] && echo "$0: Error when getopt, please recheck parameters." && exit 1
eval set -- "$para"
while true ; do
  case "$1" in
    -h|--help) showhelp;exit;;
    --check) UPDATE_CHECK=true;shift;;
    --no-system) UPDATE_SYSTEM=false;shift;;
    --no-aur) UPDATE_AUR=false;shift;;
    --unattended) UPDATE_UNATTENDED=true;shift;;
    --files) UPDATE_FILES=true;shift;;
    --offline) UPDATE_OFFLINE=true;shift;;
    --channel)
      case "$2" in
        stable|main) UPDATE_SET_CHANNEL="$2";;
        *) echo -e "$0: --channel takes stable or main.";exit 1;;
      esac
      shift 2;;
    --continue-from) UPDATE_CONTINUE_FROM="$2";shift 2;;
    --) shift;break ;;
    *) echo -e "$0: Wrong parameters.";exit 1;;
  esac
done
