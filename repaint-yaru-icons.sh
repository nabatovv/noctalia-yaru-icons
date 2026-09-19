#!/usr/bin/env bash
#
# 1) Copies the default Yaru icon theme to $HOME/.icons/Yaru-noctalia
#    (only if it doesn't already exist), dereferencing symlinks so real
#    files are copied.
# 2) Color-shifts every PNG (including symlinked PNGs) under every
#    "places" subfolder from Yaru's default color to a color you supply,
#    writing the results into the matching "places" subfolder under
#    Yaru-noctalia (overwriting anything already there).
# 3) Sets Yaru-noctalia as the current GNOME icon theme.
#
# Usage:
#   ./repaint-yaru-icons.sh
#
# Example:
#   ./repaint-yaru-icons.sh

set -euo pipefail

# Noctalia updates colors in ~/.config/gtk-4.0/noctalia.css with a delay. Let's wait.
sleep 5

# Config

# Default accent color used by stock Yaru "places" icons (Ubuntu orange).
OLD_COLOR="#da5b2a"
NEW_COLOR="${1:-"$(awk -F':' '/--accent-color/ {gsub(/[;[:space:]]/, "", $2); print $2}' ~/.config/gtk-4.0/noctalia.css)"}"
THEME_NAME="Yaru-noctalia"
DEST_THEME_DIR="$HOME/.icons/${THEME_NAME}"


# Args / sanity checks

usage() {
    echo "Usage: $0 <new_color_hex>"
    echo "Example: $0 \"#8A2BE2\""
    exit 1
}

if ! [[ "$NEW_COLOR" =~ ^#[A-Fa-f0-9]{6}$ ]]; then
    echo "Error: new color must be a hex value like #RRGGBB" >&2
    exit 1
fi

if ! command -v convert >/dev/null 2>&1; then
    echo "Error: ImageMagick's 'convert' is required. Install with:" >&2
    echo "  sudo apt install imagemagick" >&2
    exit 1
fi

# Locate the default Yaru theme directory.
SRC_THEME_DIR=""
for candidate in /usr/share/icons/Yaru /usr/local/share/icons/Yaru; do
    if [[ -d "$candidate" ]]; then
        SRC_THEME_DIR="$candidate"
        break
    fi
done

if [[ -z "$SRC_THEME_DIR" ]]; then
    echo "Error: could not find the default Yaru icon theme." >&2
    exit 1
fi

# Compute HSL modulate values (lightness%, saturation%, hue%) that take OLD_COLOR to NEW_COLOR, to use with `convert -modulate`
read -r LIGHT_PCT SAT_PCT HUE_PCT < <(python3 - "$OLD_COLOR" "$NEW_COLOR" <<'PYEOF'
import sys, colorsys

def hex_to_rgb(h):
    h = h.lstrip('#')
    return tuple(int(h[i:i+2], 16) / 255.0 for i in (0, 2, 4))

base = hex_to_rgb(sys.argv[1])
new = hex_to_rgb(sys.argv[2])

bh, bl, bs = colorsys.rgb_to_hls(*base)
nh, nl, ns = colorsys.rgb_to_hls(*new)

# ImageMagick's -modulate shifts hue over a 200-point range (not 100),
# i.e. new_hue = old_hue + 0.5*(hue_pct-100)/100
hue_diff = nh - bh
hue_pct = (100 + hue_diff * 200.0) % 200
if hue_pct < 0:
    hue_pct += 200

sat_pct = (ns / bs * 100) if bs > 0 else 100
light_pct = (nl / bl * 100) if bl > 0 else 100

print(f"{light_pct:.6f} {sat_pct:.6f} {hue_pct:.6f}")
PYEOF
)

echo "Source theme:      $SRC_THEME_DIR"
echo "Destination theme:  $DEST_THEME_DIR"
echo "Repainting $OLD_COLOR -> $NEW_COLOR"
echo

# ---------------------------------------------------------------------------
# Step 1: copy Yaru -> Yaru-noctalia (real files, not symlinks), only if
# the destination folder doesn't already exist.
# ---------------------------------------------------------------------------

if [[ ! -e "$DEST_THEME_DIR" ]]; then
    echo "Copying $SRC_THEME_DIR -> $DEST_THEME_DIR ..."
    mkdir -p "$HOME/.icons"
    # -L dereferences symlinks so actual file contents are copied,
    # -r copies recursively, -p preserves mode/timestamps.
    cp -rLp "$SRC_THEME_DIR" "$DEST_THEME_DIR"
    echo "Copy complete."
else
    echo "$DEST_THEME_DIR already exists, skipping copy."
fi
echo

 # update theme name to make it discoverable for applications
sed -i 's/^Name=Yaru.*/Name=Yaru-noctalia/g' "$HOME/.icons/Yaru-noctalia/index.theme"

# ---------------------------------------------------------------------------
# Step 2: repaint PNGs under every "places" subfolder.
# ---------------------------------------------------------------------------

echo "Repainting PNGs ..."

# Icon names (without .png) to process wherever they appear in the theme,
# in addition to everything inside "places" directories.
INCLUDE_LIST=(
    file-manager filemanager-app nautilus org.gnome.Nautilus
    system-file-manager emblem-readonly go-first go-last
    mail-reply-all mail-replyall stock_mail-reply-to-all
    applications-system livepatch org.gnome.tweaks org.gnome.Tweaks
    preferences-desktop tweaks-app unity-tweak-tool
    workspace-switcher-left-bottom workspace-switcher-left-top
    workspace-switcher-right-bottom workspace-switcher-right-top
    workspace-switcher-top-left
    preferences-system-brightness-lock system-lock-screen
    unity-screen-panel folder-drag-accept
)

# Icon names (without .png) that are never processed, even inside "places".
EXCLUDE_LIST=(
    folder-recent network-server start-here user-trash
    network-workgroup distributor-logo
)

# Lowercased lookup tables (matching is case-insensitive, like -iname was)
declare -A INCLUDE_NAMES=() EXCLUDE_NAMES=()
for n in "${INCLUDE_LIST[@]}"; do INCLUDE_NAMES["${n,,}"]=1; done
for n in "${EXCLUDE_LIST[@]}"; do EXCLUDE_NAMES["${n,,}"]=1; done

MAX_JOBS="$(nproc)"

# Include both real files and symlinks so linked PNGs are processed too.
while IFS= read -r -d '' png; do
    fname="$(basename "$png")"
    key="${fname%.*}"
    key="${key,,}"

    # Exclusions always win
    [[ -n "${EXCLUDE_NAMES[$key]+x}" ]] && continue

    rel="${png#"$SRC_THEME_DIR"/}"
    reldir="$(dirname "$rel")"

    # Process if it lives under a "places" dir, or its name is in the include list
    if [[ "/$reldir/" == */places/* || -n "${INCLUDE_NAMES[$key]+x}" ]]; then
        destdir="$DEST_THEME_DIR/$reldir"
        mkdir -p "$destdir"

        # Throttle parallel jobs so we don't spawn thousands of convert processes
        while (( $(jobs -rp | wc -l) >= MAX_JOBS )); do wait -n; done

        convert "$png" -strip -modulate "$LIGHT_PCT,$SAT_PCT,$HUE_PCT" \
            "$destdir/$fname" &
        # echo "  repainted: $rel"
    fi
done < <(find "$SRC_THEME_DIR" \( -type f -o -type l \) -iname "*.png" -print0)

wait   # let the last background conversions finish

echo "Repainting complete."
echo

# ---------------------------------------------------------------------------
# Step 3: make Yaru-noctalia the active GNOME icon theme.
# ---------------------------------------------------------------------------

gsettings set org.gnome.desktop.interface icon-theme 'Yaru-noctalia'

gtk-update-icon-cache -f -t "$HOME/.icons"
gtk-update-icon-cache -f -t "$HOME/.icons/Yaru-noctalia"

echo "Done."