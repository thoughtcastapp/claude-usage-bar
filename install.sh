#!/usr/bin/env bash
# ClaudeUsageBar — one-shot installer
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/irysagency/claude-usage-bar/main/install.sh | bash
#
# What it does:
#   1. Confirms macOS arm64 (Apple Silicon)
#   2. Downloads the latest signed-ad-hoc .app bundle from the GitHub Releases page
#   3. Strips macOS quarantine attributes so the app launches without a Gatekeeper warning
#   4. Moves it to /Applications (replacing any prior install)
#   5. Launches it
#
# This is a self-contained Bash script. It writes only to /Applications and a temp dir.
# No telemetry, no curl-piped sudo. Re-running is idempotent.

set -euo pipefail

REPO="irysagency/claude-usage-bar"
APP_NAME="ClaudeUsageBar"
ASSET_NAME="ClaudeUsageBar.zip"
INSTALL_DIR="/Applications"

c_reset="\033[0m"; c_bold="\033[1m"; c_dim="\033[2m"
c_green="\033[32m"; c_red="\033[31m"; c_yellow="\033[33m"; c_blue="\033[34m"

step()    { printf "${c_blue}==>${c_reset} ${c_bold}%s${c_reset}\n" "$*"; }
success() { printf "${c_green}✓${c_reset} %s\n" "$*"; }
warn()    { printf "${c_yellow}!${c_reset} %s\n" "$*"; }
fatal()   { printf "${c_red}✗${c_reset} %s\n" "$*" >&2; exit 1; }

# --- 1. Platform check -------------------------------------------------------
[[ "$(uname -s)" == "Darwin" ]] || fatal "This installer only runs on macOS."

ARCH="$(uname -m)"
[[ "$ARCH" == "arm64" ]] || fatal "Apple Silicon (arm64) only for now. Detected: $ARCH"

step "Resolving latest release of $REPO"
LATEST_JSON="$(curl -fsSL "https://api.github.com/repos/$REPO/releases/latest")" \
  || fatal "Failed to fetch release info from GitHub. Check the repo URL and your network."

TAG="$(printf '%s' "$LATEST_JSON" | /usr/bin/awk -F'"' '/"tag_name"/{print $4; exit}')"
[[ -n "${TAG:-}" ]] || fatal "Could not parse latest tag from GitHub API response."

ASSET_URL="$(printf '%s' "$LATEST_JSON" \
  | /usr/bin/awk -F'"' -v name="$ASSET_NAME" '
      $2 == "assets" {in_assets=1}
      in_assets && $2 == "name" && $4 == name {found=1}
      found && $2 == "browser_download_url" {print $4; exit}
    ')"
[[ -n "${ASSET_URL:-}" ]] || fatal "Could not find asset $ASSET_NAME in release $TAG."

success "Latest release: $TAG"

# --- 2. Download to a temp dir ----------------------------------------------
TMP="$(mktemp -d -t claudeusagebar)"
trap 'rm -rf "$TMP"' EXIT

step "Downloading $ASSET_NAME"
curl -fL --progress-bar -o "$TMP/$ASSET_NAME" "$ASSET_URL" \
  || fatal "Download failed."

# --- 3. Unzip ----------------------------------------------------------------
step "Unpacking"
/usr/bin/unzip -q -o "$TMP/$ASSET_NAME" -d "$TMP" \
  || fatal "Unzip failed."

[[ -d "$TMP/$APP_NAME.app" ]] || fatal "Expected $APP_NAME.app inside the archive — not found."

# --- 4. Strip quarantine -----------------------------------------------------
# The .app is ad-hoc signed (no Apple Developer cert), so without this step macOS would
# show a Gatekeeper warning on first launch. We use the system-blessed `xattr` for this.
step "Removing quarantine attribute"
/usr/bin/xattr -dr com.apple.quarantine "$TMP/$APP_NAME.app" 2>/dev/null || true

# --- 5. Install --------------------------------------------------------------
step "Installing to $INSTALL_DIR"
if [[ -e "$INSTALL_DIR/$APP_NAME.app" ]]; then
    /bin/rm -rf "$INSTALL_DIR/$APP_NAME.app" \
      || fatal "Could not remove existing $INSTALL_DIR/$APP_NAME.app — try running with appropriate permissions."
fi
/bin/mv "$TMP/$APP_NAME.app" "$INSTALL_DIR/" \
  || fatal "Move into $INSTALL_DIR failed — try running with appropriate permissions."

# --- 6. Launch ---------------------------------------------------------------
step "Launching"
/usr/bin/open "$INSTALL_DIR/$APP_NAME.app"

cat <<EOF

${c_green}${c_bold}✓ ClaudeUsageBar $TAG installed.${c_reset}

  ${c_dim}•${c_reset} Look at the right side of your menu bar — the icon should appear once Claude Desktop is running.
  ${c_dim}•${c_reset} On first launch, macOS may ask for Keychain access ("Claude Safe Storage"). Click ${c_bold}Always Allow${c_reset}.
  ${c_dim}•${c_reset} To start it automatically with macOS:
       System Settings → General → Login Items → ${c_bold}+${c_reset} → /Applications/ClaudeUsageBar.app

  ${c_dim}Bug? Question? Open an issue:${c_reset} https://github.com/$REPO/issues

EOF
