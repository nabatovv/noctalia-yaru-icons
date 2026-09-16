# Noctalia yaru icons

Script that recolors Yaru icons to match Noctalia's theme.

![Noctalia Settings with the script applied](img.png)

## Prerequisites:

### System / Environment
- Linux with a GNOME desktop (uses `gsettings` and the `org.gnome.desktop.interface` schema, plus `gtk-update-icon-cache`)
- Bash (the script uses `set -euo pipefail`, process substitution `< <(...)`, etc. — not POSIX `sh`)

### Packages / Commands on `$PATH`
- **ImageMagick** — provides the `convert` command (the script explicitly checks for this and exits with an install hint if missing)
- **Python 3** — with the standard library `colorsys` module (used for the HSL modulate math)
- **`gsettings`** — normally part of `libglib2.0-bin` / a standard GNOME install
- **`gtk-update-icon-cache`** — normally part of `libgtk-3-bin` or similar
- Core utilities: `find`, `sed`, `awk`, `cp`, `mkdir` (standard on virtually any Linux system)

### Files / Directories
- A source Yaru icon theme at either `/usr/share/icons/Yaru` or `/usr/local/share/icons/Yaru` (the script errors out if neither exists) — implies Ubuntu or an Ubuntu-based distro with the Yaru theme package installed
- `$HOME/.icons/` must be writable (created automatically if absent)
- If no color argument is passed, `~/.config/gtk-4.0/noctalia.css` must exist and contain a `--accent-color` line, since the script parses it with `awk` to determine the default color — this implies **Noctalia** (a GNOME shell theming tool) is installed and has already generated that CSS file

### Input
- Optionally, a hex color argument such as `"#8A2BE2"`
- If omitted, the script falls back to scraping the accent color from Noctalia's CSS as described above

### Permissions
- No `sudo`/root required for the script's own operations, but the user needs write access to their own home directory
- The `gsettings set` call only has a visible effect if a GNOME session is actually running (not just installed)

### Implicit Assumption
- The script starts with `sleep 5`, with a comment noting it's waiting for Noctalia to update `noctalia.css`. If relying on the auto-detected color, Noctalia should have just triggered a theme/color change shortly before this script runs (e.g., invoked as a hook/callback from Noctalia rather than run cold).
