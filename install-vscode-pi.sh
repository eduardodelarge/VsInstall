#!/usr/bin/env bash
#
# install-vscode-pi.sh
# Installs Visual Studio Code on a Raspberry Pi from Microsoft's official
# APT repository, so future updates arrive via `apt upgrade`.
#
# Supported: ARMv7 (armhf) and ARMv8 (arm64) — Pi 2 and newer.
# Not supported: ARMv6 (Pi 1, Pi Zero / Zero W) — see note at the end.
#
# Usage:  chmod +x install-vscode-pi.sh && ./install-vscode-pi.sh
#

set -euo pipefail

KEYRING="/usr/share/keyrings/microsoft-archive-keyring.gpg"
SOURCE_LIST="/etc/apt/sources.list.d/vscode.list"

log()  { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[!]\033[0m %s\n' "$*"; }
die()  { printf '\033[1;31m[x]\033[0m %s\n' "$*" >&2; exit 1; }

# --- Sanity checks -----------------------------------------------------------

[[ $EUID -eq 0 ]] && die "Don't run this as root. Run it as your normal user; it will call sudo when needed."

command -v apt-get >/dev/null || die "This script needs a Debian-based OS (Raspberry Pi OS, Ubuntu, etc.)."

if command -v code >/dev/null; then
    warn "VS Code is already installed: $(code --version | head -n1)"
    read -rp "Reinstall / repair anyway? [y/N] " reply
    [[ ${reply,,} == y ]] || exit 0
fi

# --- Detect architecture -----------------------------------------------------

ARCH="$(dpkg --print-architecture)"

case "$ARCH" in
    arm64|armhf|amd64)
        log "Detected architecture: $ARCH"
        ;;
    armel)
        die "ARMv6 (Pi 1 / Pi Zero) is not supported by VS Code. Try 'code-server' or a lighter editor such as Geany."
        ;;
    *)
        die "Unsupported architecture: $ARCH"
        ;;
esac

# --- Prerequisites -----------------------------------------------------------

log "Installing prerequisites..."
sudo apt-get update -qq
sudo apt-get install -y wget gpg apt-transport-https ca-certificates

# --- Add Microsoft's signing key --------------------------------------------

log "Adding Microsoft signing key..."
TMP_KEY="$(mktemp)"
trap 'rm -f "$TMP_KEY"' EXIT

wget -qO- https://packages.microsoft.com/keys/microsoft.asc \
    | gpg --dearmor > "$TMP_KEY"
sudo install -D -o root -g root -m 644 "$TMP_KEY" "$KEYRING"

# --- Add the repository ------------------------------------------------------

log "Adding the VS Code repository..."
echo "deb [arch=${ARCH} signed-by=${KEYRING}] https://packages.microsoft.com/repos/code stable main" \
    | sudo tee "$SOURCE_LIST" > /dev/null

# --- Install -----------------------------------------------------------------

log "Installing VS Code (this may take a few minutes)..."
sudo apt-get update -qq
sudo apt-get install -y code

# --- Done --------------------------------------------------------------------

log "Done. Installed: $(code --version | head -n1)"
cat <<'EOF'

Launch it from the Programming menu, or run `code` in a terminal.
Update it later with:  sudo apt update && sudo apt upgrade

Tips for a smoother experience on a Pi:
  * Disable telemetry and the built-in updater (Settings -> search "telemetry" / "update.mode": "none")
  * If the UI feels sluggish on 4 GB or less, disable extensions you aren't using
  * On a headless Pi, consider `code-server` or VS Code Remote-SSH from a desktop instead

EOF
