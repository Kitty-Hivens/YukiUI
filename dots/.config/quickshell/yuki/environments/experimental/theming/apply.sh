#!/usr/bin/env bash
# What the experimental environment asks of the desktop outside the shell.
#
# Called by switchwall.sh with the mode it settled on as the only argument.
# Applications get a fixed look rather than the wallpaper's colours: Adwaita on
# the GTK side and Breeze on the Qt side, light or dark with the rest of the
# system, both carrying the environment's indigo accent, so the shell and the
# applications read as one desktop.

set -u

mode="${1:-dark}"
XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
THEMING_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SHELL_ROOT="$(cd "$THEMING_DIR/../../.." && pwd)"

# The accent as the shell draws it in each mode (ExLooks), and a lighter one
# for accent coloured text on a dark background.
if [[ "$mode" == "light" ]]; then
    gtk_theme='adw-gtk3'
    scheme_preference='prefer-light'
    qt_icons='breeze'
    breeze_scheme='BreezeLight'
    accent_bg='#4f6bed'
    accent_text='#3a55d6'
    accent_rgb='79,107,237'
else
    gtk_theme='adw-gtk3-dark'
    scheme_preference='prefer-dark'
    qt_icons='breeze-dark'
    breeze_scheme='BreezeDark'
    accent_bg='#6179f2'
    accent_text='#98a8ff'
    accent_rgb='97,121,242'
fi

gsettings set org.gnome.desktop.interface color-scheme "$scheme_preference"
gsettings set org.gnome.desktop.interface gtk-theme "$gtk_theme"
gsettings set org.gnome.desktop.interface icon-theme 'Material-Originals'
# The nearest of the named accents, for what asks the portal rather than
# reading the stylesheet.
gsettings set org.gnome.desktop.interface accent-color 'blue'

# The stylesheets another environment's matugen run left behind would go on
# recolouring every GTK application with its wallpaper, so they are replaced
# with nothing but the accent.
#
# Written beside and renamed into place, so an application starting meanwhile
# never reads half of one.
for version in gtk-3.0 gtk-4.0; do
    mkdir -p "$XDG_CONFIG_HOME/$version"
    staged="$(mktemp "$XDG_CONFIG_HOME/$version/gtk.css.XXXXXX")" || continue
    cat > "$staged" <<CSS
/* Written by the experimental environment: Adwaita as it is, with its accent. */
@define-color accent_color $accent_text;
@define-color accent_bg_color $accent_bg;
@define-color accent_fg_color #ffffff;

:root {
    --accent-color: $accent_text;
    --accent-bg-color: $accent_bg;
    --accent-fg-color: #ffffff;
}
CSS
    chmod 644 "$staged"
    mv -f "$staged" "$XDG_CONFIG_HOME/$version/gtk.css"
done

# Qt: Breeze's colours with its blue swapped for the accent, folded into
# kdeglobals group by group, since applications keep their own settings there.
# Only the colours: the scheme's [General] group, its name in every language
# among it, is left out, or it stayed in kdeglobals for good.
source_scheme="/usr/share/color-schemes/$breeze_scheme.colors"
if [[ -f "$source_scheme" ]]; then
    fragment="$(mktemp)"
    # The scheme is named only once its colours are in: named over colours that
    # failed to go in, applications would draw the other mode's palette under
    # this mode's name. --notify tells the ones running to read it again.
    if python3 - "$source_scheme" "$fragment" "$accent_rgb" <<'PY' && python3 "$SHELL_ROOT/scripts/colors/merge-kdeglobals.py" "$fragment" "$XDG_CONFIG_HOME/kdeglobals"; then
import sys
source, target, accent = sys.argv[1:4]
kept = []
group = ""
with open(source, encoding="utf-8") as scheme:
    for line in scheme:
        stripped = line.strip()
        if stripped.startswith("[") and stripped.endswith("]"):
            group = stripped
        if group != "[General]":
            kept.append(line.replace("61,174,233", accent))
with open(target, "w", encoding="utf-8") as out:
    out.writelines(kept)
PY
        kwriteconfig6 --notify --file kdeglobals --group General --key ColorScheme "$breeze_scheme"
        kwriteconfig6 --notify --file kdeglobals --group General --key AccentColor "$accent_rgb"
        kwriteconfig6 --notify --file kdeglobals --group Icons --key Theme "$qt_icons"
        kwriteconfig6 --notify --file kdeglobals --group KDE --key widgetStyle Darkly
        # What Plasma itself announces when the colours and the icons change.
        # --notify alone reaches neither the palette nor the icon loader of a
        # running application, so it went on drawing the other mode's palette
        # and the icons coloured by it, the shell's tray among them, until it
        # was restarted.
        dbus-send --session --type=signal /KGlobalSettings org.kde.KGlobalSettings.notifyChange int32:0 int32:0
        dbus-send --session --type=signal /KGlobalSettings org.kde.KGlobalSettings.notifyChange int32:4 int32:0
        dbus-send --session --type=signal /KIconLoader org.kde.KIconLoader.iconChanged int32:0
    else
        echo "[experimental/theming] could not merge the colours into kdeglobals, leaving it alone" >&2
    fi
    rm -f "$fragment"
else
    echo "[experimental/theming] no $source_scheme, leaving kdeglobals alone" >&2
fi
