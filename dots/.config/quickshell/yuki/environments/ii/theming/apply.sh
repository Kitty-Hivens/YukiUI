#!/usr/bin/env bash
# What Illogical Impulse asks of the desktop outside the shell.
#
# Called by switchwall.sh after matugen has written this environment's templates,
# with the mode it settled on as the only argument. Everything here used to sit in
# switchwall.sh itself, where it applied whichever environment was up -- so an
# environment that wants a different toolkit theme, a different icon set or a
# different Qt style had nowhere to say so.

set -u

mode="${1:-dark}"
XDG_STATE_HOME="${XDG_STATE_HOME:-$HOME/.local/state}"
XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
STATE_DIR="$XDG_STATE_HOME/quickshell"
THEMING_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SHELL_ROOT="$(cd "$THEMING_DIR/../../.." && pwd)"

# GTK: adw-gtk3 in both modes, recoloured by the generated gtk-3.0/gtk-4.0 css.
if [[ "$mode" == "light" ]]; then
    gtk_theme='adw-gtk3'
    scheme_preference='prefer-light'
    qt_icons='breeze'
    scheme_name='MaterialYouLight'
else
    gtk_theme='adw-gtk3-dark'
    scheme_preference='prefer-dark'
    qt_icons='breeze-dark'
    scheme_name='MaterialYouDark'
fi

gsettings set org.gnome.desktop.interface color-scheme "$scheme_preference"
gsettings set org.gnome.desktop.interface gtk-theme "$gtk_theme"
gsettings set org.gnome.desktop.interface icon-theme 'Material-Originals'

# Qt. One lever covers both halves of it: Kirigami and QML applications read the
# colour scheme through Kirigami.Theme, and Darkly is a Lightly fork that takes
# its colours from the same scheme, so the widget half follows without a second
# theme to keep in agreement.
fragment="$STATE_DIR/user/generated/kdeglobals.colors"
if [[ -f "$fragment" ]]; then
    python3 "$SHELL_ROOT/scripts/colors/merge-kdeglobals.py" \
        "$fragment" "$XDG_CONFIG_HOME/kdeglobals"
    kwriteconfig6 --file kdeglobals --group General --key ColorScheme "$scheme_name"
    kwriteconfig6 --file kdeglobals --group Icons --key Theme "$qt_icons"
    kwriteconfig6 --file kdeglobals --group KDE --key widgetStyle Darkly
else
    echo "[ii/theming] no colour fragment at $fragment, leaving kdeglobals alone" >&2
fi
