#!/usr/bin/env bash
# =============================================================================
# AI REFERENCE NOTES — Spotiapps_suite.sh
# For Claude or any AI assistant working on this file in future sessions.
#
# WHAT THIS SCRIPT DOES:
#   Manages three Spotify apps for Raspberry Pi OS Trixie:
#     • ncspot    — Terminal Spotify client (compiled from source, Rust)
#     • spotifyd  — Spotify Connect daemon (compiled from source, Rust)
#     • Spotify Web — Chromium PWA shortcut to open.spotify.com
#   ncspot and spotifyd are built as .deb packages via Rust/Cargo.
#
# CANONICAL FLAG SOURCE:
#   manage_spotify.sh is the master reference for Spotify Web (Chromium) flags.
#   SW_FLAGS in this file must always mirror CHROME_FLAGS from manage_spotify.sh.
#   The suite may have a few extra flags (--disable-stack-profiler etc.) but
#   the shared set must stay in sync. Always check manage_spotify.sh first.
#
# FLAG DECISIONS — DO NOT REVERSE WITHOUT EXPLICIT USER REQUEST:
#   --disable-client-side-phishing-detection : PRESENT in SW_FLAGS (matches
#     manage_spotify.sh). NOTE (2026-06): an older version of this comment
#     said this flag was "intentionally absent" — that was stale/incorrect;
#     the flag has been present in both scripts' actual code. Left unchanged
#     during the v1.6.2 flag-parity sync since both scripts already agree on
#     it. Whether to disable it is a separate, still-open question — not
#     decided as part of this fix.
#   --disable-features=MediaRouter : Intentionally ABSENT. Disabling this
#     breaks Chromecast/Cast device discovery on the local network.
#   --disable-web-resources : REMOVED — deleted from Chromium source, no-op
#     on Chromium 120+. Do not re-add.
#   --disable-translate : REMOVED — CLI switch was pulled from Chromium.
#     --disable-features=Translate (in the features block) covers it.
#
# FLAG REQUIREMENTS:
#   --js-flags MUST be a quoted string: "--max-old-space-size=192 --optimize-for-size"
#     Unquoted, only the first V8 flag takes effect.
#   --ozone-platform=wayland : Required for native Wayland under labwc.
#     Without it Chromium may fall back to XWayland.
#
# SAFE BROWSING:
#   --disable-safe-browsing is NOT set. The URL blocklist remains active.
#   Only client-side page content phishing detection is absent (see above).
#
# AUDIO / PIPEWIRE:
#   Pi OS Trixie uses PipeWire. NEVER replace or disable it. ncspot and
#   spotifyd run in user session only — never as system daemons. Running
#   audio daemons at boot (e.g. shairport-sync) broke PipeWire HDMI audio
#   enumeration on this system. User session launch only.
#
# ENVIRONMENT:
#   Raspberry Pi 4, Pi OS Trixie (Debian 13 arm64), labwc Wayland compositor.
#   800x480 touchscreen + 1080p HDMI. zram + log2ram active.
#
# VERSION HISTORY:
#   v1.6.2 (2026-06) — Synced Spotify Web Chromium flags to exact parity with
#     manage_spotify.sh v1.5.6 (canonical source). ADDED: --user-data-dir
#     (CRITICAL per manage_spotify.sh — isolates the Chromium profile; without
#     it Chromium reuses other PWA sessions and opens a tab instead of a
#     standalone app window). New SW_PROFILE_DIR constant
#     ($HOME/.config/webapps/spotify-web), created on install. REMOVED:
#     --disable-extensions (not present in manage_spotify.sh). No other flags
#     changed; --disable-client-side-phishing-detection remains present in
#     both scripts as-is (see note below — header text describing it as
#     "absent" is stale and does not match either script's actual flags).
#   v1.6.1 (2026-06) — Synced optional desktop launcher pin from
#     manage_spotify.sh v1.5.6 into install_spotify_web()/uninstall_spotify_web().
#     Adds an optional [y/N] prompt on install to pin a Spotify Web launcher
#     icon to ~/Desktop (XDG_DESKTOP_DIR), matching manage_spotify.sh exactly.
#     Uninstall now also removes that pinned launcher if present. No change to
#     ncspot/spotifyd behavior, Chromium flags, or uninstall philosophy.
#   v1.6.0 (2026-06) — Build/source folders routed to a fixed $HOME location.
#     v1.5.2 made build/uninstall agree by resolving the build folder via the
#     script's own location (SCRIPT_DIR/BASH_SOURCE). That still broke if the
#     script file itself was moved away from its build folders (e.g. synced
#     from Google Drive, copied to a new path, run from a USB stick). Now all
#     of fetch_or_clone(), build_ncspot(), build_spotifyd(), uninstall_ncspot(),
#     uninstall_spotifyd(), and do_uninstall() use a new fixed constant,
#     SPOTIAPPS_BUILD_ROOT="$HOME/.local/share/spotiapps-suite/build", so the
#     script file can be moved/copied/run from anywhere and build/update/
#     uninstall always agree. One-time migration: fetch_or_clone() detects a
#     pre-v1.6.0 build folder next to the script and moves it (not re-clones)
#     into the new location to avoid a redundant Rust rebuild; uninstall_*()
#     and do_uninstall() also clean up any leftover legacy-location folder.
#     No change to Chromium flags, .deb caching/update-check behavior, or
#     uninstall philosophy (dependencies still retained).
#   v1.5.2 (2026-06) — Fixed build/uninstall path mismatch. fetch_or_clone(),
#     build_ncspot(), and build_spotifyd() used to clone/cd into "ncspot" /
#     "spotifyd" relative to the caller's CWD at invocation time, while
#     uninstall_ncspot()/uninstall_spotifyd() always resolved the same folder
#     via SCRIPT_DIR (BASH_SOURCE-based, absolute). If the script was run from
#     any directory other than the one it's saved in, build would clone into
#     the wrong place and uninstall couldn't find it to clean up. All three
#     now resolve the build folder via SCRIPT_DIR the same way uninstall
#     already did, so both sides always agree regardless of invocation CWD.
#     No change to Chromium flags, .deb caching/update-check behavior, or
#     uninstall philosophy (dependencies still retained).
#   v1.5.1 (2026-06) — Fixed icon cache on install. install_spotify_web had
#     gtk-update-icon-cache pointed at $ICON_DIR subdirectory and missing
#     -f -t flags; now correctly targets hicolor root with force flags.
#     install_desktop_shortcut (ncspot/spotifyd) was missing gtk-update-icon-cache
#     entirely after write_icon — added with correct -f -t flags.
#   v1.5.0 (2026-06) — Synced with manage_spotify.sh v1.5.0. Added
#     --enable-accelerated-video-decode and UseChromeOSDirectVideoDecoder
#     to --disable-features. Enables VA-API hardware decode on Pi 4 VideoCore VI;
#     disables incorrect ChromeOS-specific decode path.
#   v1.4.0 (2026-06) — Synced with manage_spotify.sh v1.3.0. Removed
#     --disable-web-resources, --disable-translate. Fixed --js-flags quoting.
#     Added --ozone-platform=wayland. Added GlobalMediaControls,ChromeLabs
#     to --disable-features. Fixed duplicate goal #9 typo.
#   v1.3.0 — Dropped DesktopPWAsEnabledForLinux/DesktopPWAsBorderless (broken
#     on Pi OS labwc). manage_spotify.sh confirmed as canonical flag source.
#   v1.2.0 — Flags synced with manage_spotify.sh v1.1.0. Added --optimize-for-size.
#   v1.1.0 — CRITICAL: removed dependency uninstall prompts to prevent system breakage.
# =============================================================================

# =============================================================================
# Spotiapps_suite.sh
# Spotify Apps Suite — Raspberry Pi
# Version: 1.6.2
# Last updated: 2026-06
#
# v1.6.2 — Synced Spotify Web Chromium flags to exact parity with
#   manage_spotify.sh v1.5.6 (canonical source):
#   • ADDED:   --user-data-dir=$SW_PROFILE_DIR — isolated Chromium profile.
#     manage_spotify.sh marks this CRITICAL: without it, Chromium reuses other
#     PWA sessions (YouTube, Claude, etc.) and opens a tab instead of a
#     standalone app window.
#   • ADDED:   SW_PROFILE_DIR="$HOME/.config/webapps/spotify-web" constant,
#     created via mkdir -p in install_spotify_web().
#   • REMOVED: --disable-extensions — not present in manage_spotify.sh.
#   • No other flag changes.
#
# v1.6.1 — Synced optional desktop launcher pin from manage_spotify.sh v1.5.6:
#   • ADDED:   XDG_DESKTOP_DIR / SW_DESKTOP_LAUNCHER constants and
#     write_spotify_web_desktop_launcher() — writes a .desktop file pinned to
#     ~/Desktop, identical pattern to manage_spotify.sh.
#   • ADDED:   install_spotify_web() now prompts "Add a launcher icon to the
#     desktop? [y/N]" after the app-menu shortcut is created.
#   • ADDED:   uninstall_spotify_web() now also removes the pinned launcher.
#   • No change to ncspot/spotifyd, Chromium flags, or uninstall philosophy.
#
# v1.6.0 — Routed ncspot/spotifyd source+build folders to a fixed $HOME
#   location instead of resolving them by script location:
#   • ADDED:   SPOTIAPPS_BUILD_ROOT="$HOME/.local/share/spotiapps-suite/build"
#     — fixed constant used by fetch_or_clone(), build_ncspot(),
#     build_spotifyd(), uninstall_ncspot(), uninstall_spotifyd(), and
#     do_uninstall(). The script file can now be moved, copied, or run from
#     anywhere (Google Drive sync folder, USB stick, /tmp, etc.) without
#     breaking build/update/uninstall agreement.
#   • ADDED:   One-time migration in fetch_or_clone() — if a pre-v1.6.0 build
#     folder is found next to the script, it's moved (not re-cloned) into the
#     new fixed location, avoiding a redundant Rust rebuild on Pi 4 hardware.
#   • ADDED:   uninstall_ncspot()/uninstall_spotifyd()/do_uninstall() also
#     clean up any leftover legacy-location build folder.
#   • No change to Chromium flags, .deb caching/update-check behavior, or
#     uninstall philosophy (dependencies still retained).
#
# v1.5.2 — Fixed build/uninstall path mismatch (bug fix, no behavior change
#   to flags, caching, or uninstall philosophy):
#   • FIXED: fetch_or_clone() now resolves the build folder via SCRIPT_DIR
#     (script's own location, BASH_SOURCE-based, absolute) instead of the
#     caller's working directory at invocation time.
#   • FIXED: build_ncspot() and build_spotifyd() now cd into the SCRIPT_DIR-
#     resolved absolute build folder instead of a CWD-relative "ncspot" /
#     "spotifyd" path, and restore the original working directory on return.
#   • RESULT: build and uninstall_ncspot()/uninstall_spotifyd() now always
#     agree on the build folder location, regardless of where the script is
#     invoked from.
#
# v1.5.0 — Synced with manage_spotify.sh v1.5.0 (canonical source):
#   • ADDED:   --enable-accelerated-video-decode — enables VA-API hardware
#     video decode path on Pi 4 VideoCore VI
#   • ADDED:   UseChromeOSDirectVideoDecoder to --disable-features — disables
#     ChromeOS-specific decode path (incorrect on Pi OS); pairs with above
#
# v1.4.0 — Synced with manage_spotify.sh v1.3.0 (canonical source):
#   • REMOVED: Dependency uninstall prompts from uninstall routine
#   • All build packages are now kept permanently on system (safe to leave)
#   • Prevents accidental system breakage from removing essential libraries
#
# Manages three Spotify apps for Raspberry Pi OS Trixie:
#
#   ncspot    — Terminal Spotify client with Vim keybindings and MPRIS
#               Source: https://github.com/hrkfdn/ncspot
#
#   spotifyd  — Lightweight Spotify Connect daemon: makes your Pi appear as a
#               speaker in every Spotify app on your network
#               Source: https://github.com/Spotifyd/spotifyd
#
#   Spotify Web — Chromium PWA shortcut for open.spotify.com
#               RAM cache, tuned Chromium flags, embedded icon, no SD writes
#
# ncspot and spotifyd are compiled from source and packaged as .deb files.
# All three apps get desktop/launcher shortcuts with embedded SVG icons.
#
# Requirements:
#   - Raspberry Pi running Raspberry Pi OS Trixie (Debian 13) with desktop
#   - Internet connection
#   - ~2 GB free disk space (Rust toolchain + build artifacts, ncspot/spotifyd only)
#   - Spotify Premium required for ncspot and spotifyd
#   - Spotify Web works with both free and Premium accounts
#
# Audio:
#   Raspberry Pi OS Trixie uses PipeWire. PipeWire exposes a PulseAudio-
#   compatible interface so pulseaudio_backend works transparently.
#   This script auto-detects PipeWire / PulseAudio / ALSA automatically.
#
# Spotify Connect (spotifyd):
#   spotifyd implements the full Spotify Connect SPIRC protocol, making your
#   Pi appear as a speaker device in every Spotify app on your network.
#   Reference: https://github.com/Spotifyd/spotifyd
#   Cargo features: https://github.com/Spotifyd/spotifyd/blob/master/Cargo.toml
#
# MPRIS (ncspot):
#   Enables D-Bus control of ncspot — media keys, playerctl, desktop
#   environment integration.
#   Reference: https://specifications.freedesktop.org/mpris-spec/latest/
#
# Usage:
#   chmod +x Spotiapps_suite.sh
#   ./Spotiapps_suite.sh
#
# Disclaimer:
#   This script is provided as-is, free of charge, as part of an open source
#   community effort for Raspberry Pi users. It is not affiliated with or
#   endorsed by the ncspot project, spotifyd project, Raspberry Pi Ltd, or
#   Spotify AB. Use it at your own risk. No warranty is expressed or implied.
#   If it helps you — great. If you improve it — share it back.
# =============================================================================

set -euo pipefail

# ── Colours ───────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'
BOLD='\033[1m'; NC='\033[0m'
info()       { echo -e "${GREEN}[INFO]${NC}  $*"; }
warn()       { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error()      { echo -e "${RED}[ERROR]${NC} $*"; exit 1; }
step()       { echo -e "\n${CYAN}── $* ──${NC}"; }
divider()    { echo -e "${CYAN}════════════════════════════════════════════════════════════${NC}"; }
print_ok()   { echo -e "  ${GREEN}✔${NC}  $*"; }
print_info() { echo -e "  ${CYAN}•${NC}  $*"; }

# =============================================================================
# DESKTOP SHORTCUT HELPERS
# Reference: https://specifications.freedesktop.org/desktop-entry-spec/latest/
# =============================================================================

ICON_DIR="$HOME/.local/share/icons/hicolor/scalable/apps"
DESKTOP_DIR_SYSTEM="/usr/share/applications"
DESKTOP_DIR_USER="$HOME/.local/share/applications"

# =============================================================================
# BUILD ROOT — fixed $HOME location for ncspot/spotifyd source+build folders
# v1.6.0: previously these folders lived next to the script itself (resolved
# via BASH_SOURCE/SCRIPT_DIR), so moving the script anywhere other than
# alongside its build folders broke build/update/uninstall agreement. Now
# fixed under $HOME — works correctly no matter where the script file lives
# (Google Drive sync folder, USB stick, /tmp, wherever it's copied/run from).
# =============================================================================
SPOTIAPPS_BUILD_ROOT="$HOME/.local/share/spotiapps-suite/build"

# =============================================================================
# SPOTIFY WEB
# Optimized Chromium PWA shortcut for the Spotify Web Player.
# RAM cache in /dev/shm — zero SD card writes during playback.
#
# Canonical reference: manage_spotify.sh (standalone Spotify Web manager).
# This section is kept in sync with that script's flags and comments.
# manage_spotify.sh is the preferred standalone tool — no compilation,
# uses pre-installed Chromium, works with free and Premium accounts.
#
# Chromium flags goals:
#   1. RAM-disk cache to protect SD card from writes
#   2. Stop GPU shader/program caches writing to SD card on every launch
#   3. GPU acceleration + reduced CPU load
#   4. Suppressed animations (major CPU spike reducer)
#   5. Background process and network throttling
#   6. Disable telemetry, crash reporting, and component update disk writes
#   7. Disable unneeded features (sync, translate, logging, phishing detection)
#   8. Spotify brand black title bar via --app-color
#   9. Correct taskbar icon binding via --class
#
# Flags intentionally excluded for stability:
#   --single-process          : Long-standing crash bug history, officially unsupported
#   --disable-dev-shm-usage   : Conflicts with /dev/shm cache setup below
#   --force-device-scale-factor: Locks scale at launch — breaks layout on 1080p screen
#   --disable-partial-raster  : Can cause visual glitches and renderer instability
#   --safebrowsing-disable-auto-update : Deprecated in modern Chromium
#   --disable-web-resources   : Removed from Chromium source — silently ignored on 120+
#   --disable-translate       : Removed CLI switch — use --disable-features=Translate instead
#                               (already covered in --disable-features block below)
#   --disable-features=MediaRouter : Kept OUT intentionally — disabling this breaks
#                               Chromecast/Cast device discovery on your local network
#   --enable-features=DesktopPWAsEnabledForLinux,DesktopPWAsBorderless :
#     Dropped — Chrome-native PWA window does not work on Pi OS / labwc.
#     Standard Chromium app window (--app= flag) is stable and correct.
#
# RAM cache note:
#   /dev/shm is a tmpfs (RAM-backed) filesystem on Linux. Cache lives entirely
#   in RAM — zero SD card reads or writes during playback.
#   Uninstall cleans these up automatically.
#
# JS heap note:
#   --max-old-space-size=192 : Reduces GC thrash on Pi 4 (4 GB)
#   --optimize-for-size      : V8 prefers smaller memory over peak speed —
#                              ideal for a long-running single-tab PWA
#   Both flags passed together as a quoted string to --js-flags
#
# Wayland note:
#   --ozone-platform=wayland : Ensures Chromium runs as a native Wayland client
#                              under labwc, not XWayland. Better scaling on both
#                              the 480p touchscreen and 1080p HDMI output.
#                              Pi OS rpi-chromium-mods may set this system-wide,
#                              but explicit flag guarantees it per-launch.
# =============================================================================

SW_DESKTOP_FILE="$HOME/.local/share/applications/spotify-web.desktop"
SW_ICON_FILE="$ICON_DIR/spotify-web.svg"
SW_CACHE_DIR="/dev/shm/spotify-web-cache"
SW_PROFILE_DIR="$HOME/.config/webapps/spotify-web"   # isolated Chromium profile — matches manage_spotify.sh USER_DATA_DIR

# Optional desktop launcher (pinned to ~/Desktop) — mirrors manage_spotify.sh
# v1.5.6. Canonical source: manage_spotify.sh. Keep these two in sync.
XDG_DESKTOP_DIR="$(xdg-user-dir DESKTOP 2>/dev/null || echo "${HOME}/Desktop")"
SW_DESKTOP_LAUNCHER="${XDG_DESKTOP_DIR}/spotify-web.desktop"

SW_FLAGS="--user-data-dir=${SW_PROFILE_DIR} \
--app=https://open.spotify.com \
--app-color=#121212 \
--class=spotify-web \
--ozone-platform=wayland \
--process-per-site \
--renderer-process-limit=1 \
--disk-cache-dir=${SW_CACHE_DIR} \
--disk-cache-size=20971520 \
--media-cache-size=20971520 \
--disable-gpu-shader-disk-cache \
--disable-gpu-program-cache \
--enable-gpu-rasterization \
--enable-accelerated-video-decode \
--num-raster-threads=1 \
--force-prefers-reduced-motion \
--disable-smooth-scrolling \
--disable-threaded-animation \
--disable-threaded-scrolling \
--disable-checker-imaging \
--disable-background-networking \
--disable-background-timer-throttling \
--disable-renderer-backgrounding \
--disable-backgrounding-occluded-windows \
--disable-breakpad \
--disable-crash-reporter \
--disable-component-update \
--disable-domain-reliability \
--disable-client-side-phishing-detection \
--disable-default-apps \
--disable-stack-profiler \
--disable-component-extensions-with-background-pages \
--disable-updater-scheduler \
--no-pings \
--js-flags=\"--max-old-space-size=192 --optimize-for-size\" \
--disable-logging \
--log-level=3 \
--no-crash-upload \
--no-first-run \
--no-default-browser-check \
--disable-sync \
--disable-features=TranslateUI,AutofillAssistant,GlobalMediaControls,ChromeLabs,UseChromeOSDirectVideoDecoder"

# NOTE: SW_FLAGS is kept in sync with manage_spotify.sh (the canonical standalone
# Spotify Web manager). If flags are updated there, update them here too.
# manage_spotify.sh is the preferred, simplest Spotify solution — no compilation,
# uses pre-installed Chromium, minimal setup, works with free & Premium accounts.

# ──────────────────────────────────────────────────────────────────────────────
# SPOTIFY WEB ICON
#
# Circle fill : #1ED760  — Spotify icon green (lighter, used in the actual logo)
# Arc fill    : #FFFFFF  — white arcs on green background
# Note: #1DB954 is the darker brand/UI green — NOT the icon circle colour
#       #121212 is the Spotify dark background used for --app-color (title bar)
#
# Using Icon=spotify-web (name only) in the .desktop file lets labwc look up
# the taskbar icon by app-id, matching --class=spotify-web passed to Chromium.
# Ref: https://developer.gnome.org/documentation/guidelines/maintainer/integrating.html
# ──────────────────────────────────────────────────────────────────────────────
write_spotify_web_icon() {
    mkdir -p "$ICON_DIR"
    cat > "$SW_ICON_FILE" << 'SVGEOF'
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 168 168">
  <circle cx="84" cy="84" r="84" fill="#1ED760"/>
  <path d="M121.4 121.2c-1.5 2.4-4.7 3.2-7.1 1.7
           C93.7 110.1 67.5 107.4 36.4 114.5
           c-2.8.6-5.6-1.1-6.2-3.9-.6-2.8 1.1-5.6 3.9-6.2
           C67.2 97 96.1 100 118.2 112.5c2.4 1.5 3.2 4.7 1.7 7.1h.5z
           M132 95.8c-1.9 3.1-5.9 4.1-9 2.2
           C100.3 82.9 66.4 78.6 39.9 86.7
           c-3.5 1-7.1-.9-8.1-4.4-1-3.5.9-7.1 4.4-8.1
           C63.9 65.2 101.4 70.1 127 86c3.1 1.9 4.1 5.9 2.2 9z
           M133.5 69.3C105.7 52.7 60.4 51.2 34 59.2
           c-4.1 1.2-8.5-1.1-9.8-5.2-1.2-4.1 1.1-8.5 5.2-9.8
           C58.4 35.1 108.4 36.9 140.5 55.9
           c3.8 2.2 5 7 2.8 10.8-2.2 3.8-7 5-10.8 2.8z"
        fill="#fff"/>
</svg>
SVGEOF
    gtk-update-icon-cache -f -t "$HOME/.local/share/icons/hicolor" 2>/dev/null || true
    info "Spotify Web icon written: $SW_ICON_FILE"
}

# ── Optional desktop launcher (pinned to ~/Desktop) ──────────────────────────
# Mirrors manage_spotify.sh v1.5.6. Canonical source: manage_spotify.sh.
write_spotify_web_desktop_launcher() {
    mkdir -p "${XDG_DESKTOP_DIR}"
    cat > "${SW_DESKTOP_LAUNCHER}" << EOF
[Desktop Entry]
Type=Application
Version=1.0
Name=Spotify Web
Comment=Optimized Spotify Web Player (Raspberry Pi)
Exec=chromium $SW_FLAGS
Icon=spotify-web
Terminal=false
Categories=AudioVideo;Player;Music;
EOF
    chmod +x "${SW_DESKTOP_LAUNCHER}" 2>/dev/null || true
}

install_spotify_web() {
    echo ""
    echo -e "  ${CYAN}${BOLD}Installing Spotify Web…${NC}"
    mkdir -p "$HOME/.local/share/applications"
    write_spotify_web_icon
    mkdir -p "$SW_CACHE_DIR"
    mkdir -p "$SW_PROFILE_DIR"

    cat > "$SW_DESKTOP_FILE" << EOF
[Desktop Entry]
Name=Spotify Web
Comment=Optimized Spotify Web Player (Raspberry Pi)
Exec=chromium $SW_FLAGS
Icon=spotify-web
Terminal=false
Type=Application
Categories=AudioVideo;Player;
StartupNotify=true
StartupWMClass=spotify-web
EOF

    chmod +x "$SW_DESKTOP_FILE"
    update-desktop-database "$HOME/.local/share/applications" 2>/dev/null || true
    gtk-update-icon-cache -f -t "$HOME/.local/share/icons/hicolor" 2>/dev/null || true

    local ANS_DL
    read -rp "$(echo -e "${CYAN}Add a launcher icon to the desktop? [y/N]:${NC} ")" ANS_DL
    if [[ "${ANS_DL,,}" == "y" ]]; then
        write_spotify_web_desktop_launcher
        print_ok "Desktop launcher icon added to ${XDG_DESKTOP_DIR}."
    else
        rm -f "${SW_DESKTOP_LAUNCHER}"
        info "Desktop launcher skipped."
    fi

    echo ""
    print_ok "Spotify Web shortcut installed."
    echo ""
    echo "  Optimizations active:"
    print_info "Cache in RAM (/dev/shm) — no SD writes"
    print_info "GPU shader/program cache disabled — no SD writes on launch"
    print_info "Crash reporting and telemetry disabled"
    print_info "Component updater disabled"
    print_info "Animations and background activity fully suppressed"
    print_info "V8 heap 192 MB + optimize-for-size — reduces GC thrash"
}

uninstall_spotify_web() {
    echo ""
    echo -e "  ${CYAN}${BOLD}Uninstalling Spotify Web…${NC}"
    rm -f  "$SW_DESKTOP_FILE"
    rm -f  "$SW_ICON_FILE"
    rm -f  "$SW_DESKTOP_LAUNCHER"
    rm -rf "$SW_CACHE_DIR"
    update-desktop-database "$HOME/.local/share/applications" 2>/dev/null || true
    gtk-update-icon-cache -f -t "$HOME/.local/share/icons/hicolor" 2>/dev/null || true
    print_ok "Spotify Web shortcut, desktop launcher, icon, and RAM cache removed."
}

# write_icon APP_NAME
#   Writes a purpose-built SVG icon for ncspot or spotifyd into the hicolor
#   icon theme directory, then refreshes the icon cache so the desktop launcher
#   picks it up by name.
#
#   ncspot icon:
#     Dark terminal window with a blinking cursor prompt and a music note.
#     Dark background (#1a1a1a) with Spotify green (#1ED760) accents.
#     Represents the TUI/terminal nature of the app.
#
#   spotifyd icon:
#     A small speaker (representing the Pi as a playback device) with
#     two sound-wave arcs radiating from it, all in Spotify green on dark.
#     Represents Spotify Connect — the Pi as a wireless speaker.
#
#   Neither icon uses Spotify's trademarked circle+arcs logo.
#   References:
#     https://developer.gnome.org/documentation/guidelines/maintainer/integrating.html
#     https://specifications.freedesktop.org/icon-theme-spec/icon-theme-spec-latest.html
write_icon() {
    local APP_NAME="$1"
    local ICON_FILE="${ICON_DIR}/${APP_NAME}.svg"
    mkdir -p "$ICON_DIR"

    case "$APP_NAME" in

    ncspot)
        # Terminal window with prompt cursor and music note
        # viewBox 100x100 — square, scales cleanly at any size
        cat > "$ICON_FILE" << 'SVGEOF'
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100">
  <!-- Terminal window body -->
  <rect width="100" height="100" rx="12" fill="#1a1a1a"/>
  <!-- Title bar strip -->
  <rect width="100" height="22" rx="12" fill="#2a2a2a"/>
  <rect y="11" width="100" height="11" fill="#2a2a2a"/>
  <!-- Traffic-light dots (subtle — not macOS branded, just terminal feel) -->
  <circle cx="16" cy="11" r="4" fill="#555"/>
  <circle cx="28" cy="11" r="4" fill="#555"/>
  <circle cx="40" cy="11" r="4" fill="#555"/>
  <!-- Shell prompt: "> _" in Spotify green -->
  <text x="12" y="46" font-family="monospace" font-size="18" fill="#1ED760">&#x276F;</text>
  <!-- Blinking cursor block -->
  <rect x="30" y="30" width="10" height="18" fill="#1ED760" opacity="0.85"/>
  <!-- Music note -->
  <text x="55" y="72" font-family="serif" font-size="36" fill="#1ED760">♪</text>
  <!-- Bottom status bar line -->
  <rect x="10" y="82" width="80" height="3" rx="1.5" fill="#333"/>
  <rect x="10" y="82" width="35" height="3" rx="1.5" fill="#1ED760" opacity="0.7"/>
</svg>
SVGEOF
        ;;

    spotifyd)
        # Speaker + two sound-wave arcs = Spotify Connect / wireless playback
        cat > "$ICON_FILE" << 'SVGEOF'
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100">
  <!-- Dark background circle -->
  <circle cx="50" cy="50" r="50" fill="#1a1a1a"/>
  <!-- Speaker cone body -->
  <path d="M38 35 L28 42 L28 58 L38 65 Z"
        fill="#1ED760"/>
  <!-- Speaker rectangle (driver) -->
  <rect x="38" y="35" width="10" height="30" rx="2" fill="#1ED760"/>
  <!-- Sound wave arc 1 (near) -->
  <path d="M54 41 Q62 50 54 59"
        fill="none" stroke="#1ED760" stroke-width="4"
        stroke-linecap="round" opacity="0.9"/>
  <!-- Sound wave arc 2 (far) -->
  <path d="M60 34 Q73 50 60 66"
        fill="none" stroke="#1ED760" stroke-width="4"
        stroke-linecap="round" opacity="0.55"/>
  <!-- Small "d" daemon indicator dot at bottom-right -->
  <circle cx="72" cy="72" r="7" fill="#1ED760" opacity="0.3"/>
  <text x="69" y="77" font-family="monospace" font-size="10" fill="#1ED760">d</text>
</svg>
SVGEOF
        ;;

    *)
        # Fallback: plain music note on dark circle
        cat > "$ICON_FILE" << 'SVGEOF'
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100">
  <circle cx="50" cy="50" r="50" fill="#1a1a1a"/>
  <text x="22" y="72" font-family="serif" font-size="58" fill="#1ED760">♪</text>
</svg>
SVGEOF
        ;;
    esac

    # Refresh hicolor icon cache so the desktop finds the icon by name
    gtk-update-icon-cache -f -t "$HOME/.local/share/icons/hicolor" 2>/dev/null || true
    info "Icon written: $ICON_FILE"
}

install_desktop_shortcut() {
    local APP_NAME="$1"        # e.g. "ncspot"
    local DISPLAY_NAME="$2"    # e.g. "ncspot"
    local GENERIC_NAME="$3"    # e.g. "Music Player"
    local COMMENT="$4"
    local EXEC_CMD="$5"        # full Exec= value

    # Write the app-specific SVG icon before creating the .desktop file
    write_icon "$APP_NAME"

    local CONTENT
    CONTENT="[Desktop Entry]
Version=1.0
Type=Application
Name=${DISPLAY_NAME}
GenericName=${GENERIC_NAME}
Comment=${COMMENT}
Exec=${EXEC_CMD}
Icon=${APP_NAME}
Terminal=false
Categories=Audio;Music;Player;AudioVideo;
Keywords=spotify;music;
StartupNotify=false"

    local SYSTEM_FILE="${DESKTOP_DIR_SYSTEM}/${APP_NAME}.desktop"
    local USER_FILE="${DESKTOP_DIR_USER}/${APP_NAME}.desktop"

    if echo "$CONTENT" | sudo tee "$SYSTEM_FILE" > /dev/null 2>&1; then
        sudo chmod 644 "$SYSTEM_FILE"
        info "Shortcut installed system-wide: $SYSTEM_FILE"
    else
        mkdir -p "$DESKTOP_DIR_USER"
        echo "$CONTENT" > "$USER_FILE"
        chmod 644 "$USER_FILE"
        info "Shortcut installed for current user: $USER_FILE"
    fi

    if command -v update-desktop-database &>/dev/null; then
        sudo update-desktop-database "$DESKTOP_DIR_SYSTEM" 2>/dev/null || \
        update-desktop-database "$DESKTOP_DIR_USER" 2>/dev/null || true
    fi
    gtk-update-icon-cache -f -t "$HOME/.local/share/icons/hicolor" 2>/dev/null || true
}

remove_desktop_shortcut() {
    local APP_NAME="$1"
    local REMOVED=false
    local SYSTEM_FILE="${DESKTOP_DIR_SYSTEM}/${APP_NAME}.desktop"
    local USER_FILE="${DESKTOP_DIR_USER}/${APP_NAME}.desktop"
    local ICON_FILE="${ICON_DIR}/${APP_NAME}.svg"
    if [[ -f "$SYSTEM_FILE" ]]; then
        sudo rm -f "$SYSTEM_FILE"; info "Removed: $SYSTEM_FILE"; REMOVED=true
    fi
    if [[ -f "$USER_FILE" ]]; then
        rm -f "$USER_FILE"; info "Removed: $USER_FILE"; REMOVED=true
    fi
    if [[ -f "$ICON_FILE" ]]; then
        rm -f "$ICON_FILE"; info "Removed icon: $ICON_FILE"
    fi
    if [[ "$REMOVED" == "false" ]]; then
        warn "No shortcut found for $APP_NAME — skipping."
    fi
    if command -v update-desktop-database &>/dev/null; then
        sudo update-desktop-database "$DESKTOP_DIR_SYSTEM" 2>/dev/null || \
        update-desktop-database "$DESKTOP_DIR_USER" 2>/dev/null || true
    fi
    gtk-update-icon-cache -f -t "$HOME/.local/share/icons/hicolor" 2>/dev/null || true
}

# =============================================================================
# VERSION CHECK HELPERS
# Queries the GitHub Releases API silently and compares against the locally
# installed dpkg version.  Output is captured into variables so the menu can
# display a clean status block before prompting the user.
#
# GitHub Releases API reference:
#   https://docs.github.com/en/rest/releases/releases#get-the-latest-release
#
# Strategy:
#   • Uses curl with a short timeout so a slow/absent network never hangs the menu.
#   • jq is used when available; falls back to pure-bash grep/sed for minimal installs.
#   • Locally installed version is read from dpkg — works whether the .deb was
#     installed by this script or any other package manager.
# =============================================================================

# gh_latest_tag OWNER/REPO
#   Prints the latest release tag (e.g. "v0.13.3") or "unknown" on failure.
gh_latest_tag() {
    local REPO="$1"
    local URL="https://api.github.com/repos/${REPO}/releases/latest"
    local RAW
    # --max-time 6  — give the API 6 s; more than enough on any reasonable link
    # --silent      — suppress curl progress output
    # --fail        — return non-zero on HTTP errors (rate-limit, 404, etc.)
    RAW=$(curl --silent --fail --max-time 6 \
               -H "Accept: application/vnd.github+json" \
               "$URL" 2>/dev/null) || { echo "unknown"; return; }

    if command -v jq &>/dev/null; then
        echo "$RAW" | jq -r '.tag_name // "unknown"'
    else
        # Pure-bash fallback: extract "tag_name":"v1.2.3" without jq
        echo "$RAW" | grep -o '"tag_name"[[:space:]]*:[[:space:]]*"[^"]*"' \
                    | head -1 \
                    | sed 's/.*"tag_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/'
    fi
}

# dpkg_installed_version PACKAGE_NAME
#   Prints the installed version (e.g. "0.13.3") or "not installed".
dpkg_installed_version() {
    local PKG="$1"
    local VER
    VER=$(dpkg-query -W -f='${Version}' "$PKG" 2>/dev/null) || { echo "not installed"; return; }
    [[ -z "$VER" ]] && echo "not installed" || echo "$VER"
}

# strip_v TAG
#   Strips a leading "v" and any Debian revision suffix so version strings
#   from GitHub ("v1.3.3") and cargo-deb ("1.3.3-1") compare cleanly.
#   Examples:  "v1.3.3" → "1.3.3"
#              "1.3.3-1" → "1.3.3"   (cargo-deb adds "-1" Debian revision)
#              "0.3.5+git123" → "0.3.5"
strip_v() {
    local V="${1#v}"   # strip leading v
    V="${V%%-*}"       # strip Debian revision suffix (e.g. -1, -2)
    echo "${V%%+*}"    # strip build metadata suffix (e.g. +git123)
}

# render_version_row  APP  OWNER/REPO  LABEL
#   Prints one formatted status row and sets the UPDATE_AVAILABLE_<APP> flag.
render_version_row() {
    local APP="$1"          # ncspot | spotifyd
    local REPO="$2"         # e.g. hrkfdn/ncspot
    local LABEL="$3"        # display label

    local INSTALLED LATEST INSTALLED_CLEAN LATEST_CLEAN
    INSTALLED=$(dpkg_installed_version "$APP")
    LATEST=$(gh_latest_tag "$REPO")

    INSTALLED_CLEAN=$(strip_v "$INSTALLED")
    LATEST_CLEAN=$(strip_v "$LATEST")

    # Pad label to fixed width for alignment
    printf "  %-10s" "$LABEL"

    if [[ "$INSTALLED" == "not installed" ]]; then
        printf "  installed: %-16s" "—"
    else
        printf "  installed: %-16s" "$INSTALLED_CLEAN"
    fi

    if [[ "$LATEST" == "unknown" ]]; then
        printf "  latest: %-12s\n" "(offline?)"
    elif [[ "$INSTALLED" == "not installed" ]]; then
        printf "  latest: %s\n" "$LATEST_CLEAN"
    elif [[ "$INSTALLED_CLEAN" == "$LATEST_CLEAN" ]]; then
        printf "  latest: %-12s  ${GREEN}✔ up to date${NC}\n" "$LATEST_CLEAN"
    else
        printf "  latest: %-12s  ${YELLOW}⚡ Update available${NC}\n" "$LATEST_CLEAN"
        # Flag used later if the user wants context
        declare -g "UPDATE_AVAILABLE_${APP^^}=true"
    fi
}

# render_status_row  APP  OWNER/REPO  LABEL  BINARY  DESKTOP  LAUNCHER  ICON
#   Combines version check with on-disk file checks into one status row.
#   Prints installed version, latest version, and whether all key files exist.
render_status_row() {
    local APP="$1"       # ncspot | spotifyd
    local REPO="$2"      # e.g. hrkfdn/ncspot
    local LABEL="$3"     # display label
    local BINARY="$4"    # path to check binary exists (via dpkg or path)
    local DESKTOP="$5"   # .desktop file path
    local LAUNCHER="$6"  # launcher script path (empty string if n/a)
    local ICON="$7"      # icon file path

    local INSTALLED LATEST INSTALLED_CLEAN LATEST_CLEAN
    INSTALLED=$(dpkg_installed_version "$APP")
    LATEST=$(gh_latest_tag "$REPO")
    INSTALLED_CLEAN=$(strip_v "$INSTALLED")
    LATEST_CLEAN=$(strip_v "$LATEST")

    # File presence checks
    local BIN_OK=false DESK_OK=false LAUNCH_OK=false ICON_OK=false ALL_OK=true
    dpkg -l "$APP" &>/dev/null && BIN_OK=true   || ALL_OK=false
    [[ -f "$DESKTOP"  ]] && DESK_OK=true         || ALL_OK=false
    [[ -z "$LAUNCHER" || -f "$LAUNCHER" ]] && LAUNCH_OK=true || ALL_OK=false
    [[ -f "$ICON"     ]] && ICON_OK=true          || ALL_OK=false

    # Version comparison
    local VER_STATUS=""
    if [[ "$INSTALLED" == "not installed" ]]; then
        VER_STATUS="${RED}not installed${NC}"
        ALL_OK=false
    elif [[ "$LATEST" == "unknown" ]]; then
        VER_STATUS="${CYAN}${INSTALLED_CLEAN}${NC}  (offline — can't check latest)"
    elif [[ "$INSTALLED_CLEAN" == "$LATEST_CLEAN" ]]; then
        VER_STATUS="${GREEN}${INSTALLED_CLEAN} ✔ up to date${NC}"
    else
        VER_STATUS="${YELLOW}${INSTALLED_CLEAN} — update available (${LATEST_CLEAN})${NC}"
        declare -g "UPDATE_AVAILABLE_${APP^^}=true"
    fi

    # Overall health indicator
    local HEALTH
    $ALL_OK && HEALTH="${GREEN}✔ healthy${NC}" || HEALTH="${RED}✘ incomplete${NC}"

    printf "  %-12s  %b\n" "$LABEL" "$HEALTH"
    printf "    version  : %b\n" "$VER_STATUS"
    printf "    binary   : %s\n" "$($BIN_OK   && echo '✔' || echo '✘ not installed (dpkg)')"
    printf "    shortcut : %s\n" "$($DESK_OK  && echo '✔' || echo "✘ missing: $DESKTOP")"
    [[ -n "$LAUNCHER" ]] && \
    printf "    launcher : %s\n" "$($LAUNCH_OK && echo '✔' || echo "✘ missing: $LAUNCHER")"
    printf "    icon     : %s\n" "$($ICON_OK  && echo '✔' || echo "✘ missing: $ICON")"
    echo ""
}

# =============================================================================
# MAIN MENU
# =============================================================================

# ── Installation status (runs before the menu is drawn) ──────────────────────
UPDATE_AVAILABLE_NCSPOT=false
UPDATE_AVAILABLE_SPOTIFYD=false

echo ""
divider
echo -e "${BOLD}  Spotiapps Suite — Raspberry Pi${NC}"
echo -e "  ncspot  •  spotifyd  •  Spotify Web"
divider
echo ""
echo -e "  ${BOLD}Apps${NC}"
echo ""
echo -e "  ${CYAN}ncspot${NC}"
echo -e "    Open source terminal based Spotify player with Vim keybindings."
echo -e "    ${YELLOW}* Requires Spotify Premium${NC}"
echo ""
echo -e "  ${CYAN}spotifyd${NC}"
echo -e "    Open source Spotify Connect daemon — makes your Pi appear as a"
echo -e "    speaker in every Spotify app on your network."
echo -e "    ${YELLOW}* Requires Spotify Premium${NC}"
echo ""
echo -e "  ${CYAN}Spotify Web Shortcut${NC}  ${GREEN}(official site version — highly recommended)${NC}"
echo -e "    A native Chromium Progressive Web App using the official"
echo -e "    https://open.spotify.com with optimized Chrome flags for"
echo -e "    optimal RAM and CPU use on Raspberry Pi. Essentially the"
echo -e "    native Spotify web app — simplest to install, works with"
echo -e "    free and Premium accounts, and compatible with any Raspberry"
echo -e "    Pi OS desktop with Chromium. CPU usage as low as 3–9% vs"
echo -e "    30–50% with the standard Chromium approach."
echo ""
divider
echo ""
echo -e "  ${BOLD}Installation Status${NC}  (checking versions and files…)"
echo ""
render_status_row \
    "ncspot" "hrkfdn/ncspot" "ncspot" \
    "" \
    "$HOME/.local/share/applications/ncspot.desktop" \
    "$HOME/.local/bin/ncspot-launch" \
    "$ICON_DIR/ncspot.svg"
render_status_row \
    "spotifyd" "Spotifyd/spotifyd" "spotifyd" \
    "" \
    "$HOME/.local/share/applications/spotifyd.desktop" \
    "$HOME/.local/bin/spotifyd-launch" \
    "$ICON_DIR/spotifyd.svg"
# Spotify Web — no dpkg version, check files directly
SW_DESK_OK=false; SW_ICON_OK=false; SW_HEALTH="${RED}✘ not installed${NC}"
[[ -f "$SW_DESKTOP_FILE" ]] && SW_DESK_OK=true
[[ -f "$SW_ICON_FILE"    ]] && SW_ICON_OK=true
{ $SW_DESK_OK && $SW_ICON_OK; } && SW_HEALTH="${GREEN}✔ installed${NC}"
printf "  %-12s  %b\n" "Spotify Web" "$SW_HEALTH"
printf "    shortcut : %s\n" "$($SW_DESK_OK && echo '✔' || echo "✘ missing: $SW_DESKTOP_FILE")"
printf "    icon     : %s\n" "$($SW_ICON_OK && echo '✔' || echo "✘ missing: $SW_ICON_FILE")"
echo ""
divider
echo ""
echo "  What would you like to do?"
echo ""
echo -e "  ${CYAN}1)${NC} Build / Update both ncspot and spotifyd"
echo -e "  ${CYAN}2)${NC} Build / Update ncspot only"
echo -e "  ${CYAN}3)${NC} Build / Update spotifyd only"
echo -e "  ${CYAN}4)${NC} Install Spotify Web shortcut"
echo -e "  ${CYAN}5)${NC} Uninstall ncspot only"
echo -e "  ${CYAN}6)${NC} Uninstall spotifyd only"
echo -e "  ${CYAN}7)${NC} Uninstall Spotify Web shortcut"
echo -e "  ${CYAN}8)${NC} Uninstall everything and restore Pi to original state"
echo -e "  ${CYAN}9)${NC} Exit"
echo ""
read -rp "$(echo -e "${CYAN}Enter choice [1-9]:${NC} ")" MAIN_CHOICE

BUILD_NCSPOT=false
BUILD_SPOTIFYD=false
INSTALL_SPOTIFY_WEB=false
UNINSTALL_NCSPOT=false
UNINSTALL_SPOTIFYD=false
UNINSTALL_SPOTIFY_WEB=false
UNINSTALL_MODE=false

case "$MAIN_CHOICE" in
    1) BUILD_NCSPOT=true;  BUILD_SPOTIFYD=true  ;;
    2) BUILD_NCSPOT=true                         ;;
    3) BUILD_SPOTIFYD=true                       ;;
    4) INSTALL_SPOTIFY_WEB=true                  ;;
    5) UNINSTALL_NCSPOT=true                     ;;
    6) UNINSTALL_SPOTIFYD=true                   ;;
    7) UNINSTALL_SPOTIFY_WEB=true                ;;
    8) UNINSTALL_MODE=true                       ;;
    9) echo "Goodbye!"; exit 0                   ;;
    *) error "Invalid choice. Run the script again and enter 1–9." ;;
esac

# =============================================================================
# UNINSTALL HELPERS — individual app uninstallers
# Called both from the individual menu options and from do_uninstall (full).
# =============================================================================

uninstall_ncspot() {
    echo ""
    divider
    echo -e "${BOLD}  Uninstall ncspot${NC}"
    divider
    echo ""
    echo -e "  ${RED}[Always removed]${NC}"
    echo "    • ncspot binary (dpkg)"
    echo "    • ncspot desktop shortcut + icon"
    echo "    • ncspot RAM launcher (~/.local/bin/ncspot-launch)"
    echo "    • ncspot RAM cache (/dev/shm/ncspot)"
    echo "    • ncspot build folder"
    echo ""
    echo -e "  ${YELLOW}[You will be asked]${NC}"
    echo "    • ncspot config (~/.config/ncspot/)"
    echo "    • ncspot OAuth credentials (~/.cache/ncspot-credentials/)"
    echo ""
    read -rp "$(echo -e "${RED}Proceed with ncspot uninstall? [y/N]:${NC} ")" CONFIRM_UN
    [[ ! "$CONFIRM_UN" =~ ^[Yy]$ ]] && { info "Cancelled. Nothing changed."; return; }

    step "Removing ncspot package"
    if dpkg -l "ncspot" &>/dev/null; then
        sudo dpkg --remove ncspot && info "ncspot removed." || warn "dpkg remove ncspot failed."
    else
        warn "ncspot not installed via dpkg — skipping."
    fi

    step "Removing ncspot desktop shortcut"
    remove_desktop_shortcut "ncspot"

    step "Removing ncspot build folder"
    local REMOVED_BUILD=false
    if [[ -d "$SPOTIAPPS_BUILD_ROOT/ncspot" ]]; then
        rm -rf "${SPOTIAPPS_BUILD_ROOT:?}/ncspot" && info "$SPOTIAPPS_BUILD_ROOT/ncspot removed."
        REMOVED_BUILD=true
    fi
    # Legacy pre-v1.6.0 layout: build folder created next to the script itself.
    local LEGACY_NCSPOT_DIR
    LEGACY_NCSPOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/ncspot"
    if [[ -d "$LEGACY_NCSPOT_DIR" ]]; then
        rm -rf "${LEGACY_NCSPOT_DIR:?}" && info "Legacy build folder removed: $LEGACY_NCSPOT_DIR"
        REMOVED_BUILD=true
    fi
    [[ "$REMOVED_BUILD" == "false" ]] && warn "ncspot build folder not found — skipping."
    rmdir "$SPOTIAPPS_BUILD_ROOT" 2>/dev/null || true

    step "ncspot launcher and RAM cache"
    local NCSPOT_LAUNCHER_PATH="$HOME/.local/bin/ncspot-launch"
    if [[ -f "$NCSPOT_LAUNCHER_PATH" ]]; then
        rm -f "$NCSPOT_LAUNCHER_PATH" && info "RAM launcher removed: $NCSPOT_LAUNCHER_PATH"
    fi
    rm -rf /dev/shm/ncspot 2>/dev/null && info "RAM cache cleared: /dev/shm/ncspot" || true

    step "ncspot config and credentials (optional)"
    for DIR_INFO in \
        "$HOME/.config/ncspot:ncspot config" \
        "$HOME/.cache/ncspot-credentials:ncspot OAuth credentials (needed to skip re-login after reinstall)"; do
        local DIR="${DIR_INFO%%:*}"; local LABEL="${DIR_INFO##*:}"
        if [[ -d "$DIR" ]]; then
            local SIZE; SIZE=$(du -sh "$DIR" 2>/dev/null | cut -f1 || echo "?")
            echo ""
            echo "  Found $LABEL at: $DIR  ($SIZE)"
            [[ "$DIR" == *credentials* ]] && \
                echo "  Note: removing this will require you to log in to Spotify again after reinstall."
            read -rp "$(echo -e "${CYAN}Remove $LABEL? [y/N]:${NC} ")" RM_DIR
            if [[ "$RM_DIR" =~ ^[Yy]$ ]]; then
                rm -rf "$DIR" && info "$LABEL removed."
            else
                info "$LABEL kept."
            fi
        else
            warn "No $LABEL found — skipping."
        fi
    done

    echo ""
    echo -e "${GREEN}${BOLD}  ✔  ncspot uninstalled.${NC}"
    echo ""
}

uninstall_spotifyd() {
    echo ""
    divider
    echo -e "${BOLD}  Uninstall spotifyd${NC}"
    divider
    echo ""
    echo -e "  ${RED}[Always removed]${NC}"
    echo "    • spotifyd binary (dpkg)"
    echo "    • spotifyd desktop shortcut + icon"
    echo "    • spotifyd RAM launcher (~/.local/bin/spotifyd-launch)"
    echo "    • spotifyd RAM cache (/dev/shm/spotifyd)"
    echo "    • spotifyd build folder"
    echo ""
    echo -e "  ${YELLOW}[You will be asked]${NC}"
    echo "    • spotifyd config (~/.config/spotifyd/)"
    echo ""
    read -rp "$(echo -e "${RED}Proceed with spotifyd uninstall? [y/N]:${NC} ")" CONFIRM_UN
    [[ ! "$CONFIRM_UN" =~ ^[Yy]$ ]] && { info "Cancelled. Nothing changed."; return; }

    step "Removing spotifyd package"
    if dpkg -l "spotifyd" &>/dev/null; then
        sudo dpkg --remove spotifyd && info "spotifyd removed." || warn "dpkg remove spotifyd failed."
    else
        warn "spotifyd not installed via dpkg — skipping."
    fi

    step "Removing spotifyd desktop shortcut"
    remove_desktop_shortcut "spotifyd"

    step "Removing spotifyd build folder"
    local REMOVED_BUILD=false
    if [[ -d "$SPOTIAPPS_BUILD_ROOT/spotifyd" ]]; then
        rm -rf "${SPOTIAPPS_BUILD_ROOT:?}/spotifyd" && info "$SPOTIAPPS_BUILD_ROOT/spotifyd removed."
        REMOVED_BUILD=true
    fi
    # Legacy pre-v1.6.0 layout: build folder created next to the script itself.
    local LEGACY_SPOTIFYD_DIR
    LEGACY_SPOTIFYD_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/spotifyd"
    if [[ -d "$LEGACY_SPOTIFYD_DIR" ]]; then
        rm -rf "${LEGACY_SPOTIFYD_DIR:?}" && info "Legacy build folder removed: $LEGACY_SPOTIFYD_DIR"
        REMOVED_BUILD=true
    fi
    [[ "$REMOVED_BUILD" == "false" ]] && warn "spotifyd build folder not found — skipping."
    rmdir "$SPOTIAPPS_BUILD_ROOT" 2>/dev/null || true

    step "spotifyd launcher and RAM cache"
    local SPOTIFYD_LAUNCHER_PATH="$HOME/.local/bin/spotifyd-launch"
    if [[ -f "$SPOTIFYD_LAUNCHER_PATH" ]]; then
        rm -f "$SPOTIFYD_LAUNCHER_PATH" && info "RAM launcher removed: $SPOTIFYD_LAUNCHER_PATH"
    fi
    rm -rf /dev/shm/spotifyd 2>/dev/null && info "RAM cache cleared: /dev/shm/spotifyd" || true

    step "spotifyd config (optional)"
    local DIR="$HOME/.config/spotifyd"
    if [[ -d "$DIR" ]]; then
        local SIZE; SIZE=$(du -sh "$DIR" 2>/dev/null | cut -f1 || echo "?")
        echo ""
        echo "  Found spotifyd config at: $DIR  ($SIZE)"
        read -rp "$(echo -e "${CYAN}Remove spotifyd config? [y/N]:${NC} ")" RM_DIR
        if [[ "$RM_DIR" =~ ^[Yy]$ ]]; then
            rm -rf "$DIR" && info "spotifyd config removed."
        else
            info "spotifyd config kept."
        fi
    else
        warn "No spotifyd config found — skipping."
    fi

    echo ""
    echo -e "${GREEN}${BOLD}  ✔  spotifyd uninstalled.${NC}"
    echo ""
}

# =============================================================================
# UNINSTALL — full suite
# =============================================================================
do_uninstall() {
    echo ""
    divider
    echo -e "${BOLD}  Full Uninstall — ncspot + spotifyd + Spotify Web${NC}"
    divider
    echo ""
    echo -e "  ${RED}[Always removed]${NC}"
    echo "    • ncspot binary (dpkg)"
    echo "    • spotifyd binary (dpkg)"
    echo "    • All desktop / launcher shortcuts"
    echo "    • ncspot RAM launcher (~/.local/bin/ncspot-launch)"
    echo "    • ncspot RAM cache (/dev/shm/ncspot)"
    echo "    • spotifyd RAM launcher (~/.local/bin/spotifyd-launch)"
    echo "    • spotifyd RAM cache (/dev/shm/spotifyd)"
    echo "    • Spotify Web shortcut + icon + RAM cache (/dev/shm/spotify-web-cache)"
    echo "    • Build folders (ncspot/ and spotifyd/)"
    echo "    • cargo-deb"
    echo ""
    echo -e "  ${YELLOW}[You will be asked]${NC}"
    echo "    • Rust toolchain (~/.cargo, ~/.rustup)"
    echo "    • ncspot config (~/.config/ncspot/)"
    echo "    • ncspot OAuth credentials (~/.cache/ncspot-credentials/)"
    echo "    • spotifyd config (~/.config/spotifyd/)"
    echo "    • Build-only apt packages"
    echo ""
    read -rp "$(echo -e "${RED}Are you sure you want to uninstall everything? [y/N]:${NC} ")" CONFIRM_UN
    [[ ! "$CONFIRM_UN" =~ ^[Yy]$ ]] && { info "Cancelled. Nothing changed."; exit 0; }

    # ── dpkg remove ───────────────────────────────────────────────────────────
    for PKG in ncspot spotifyd; do
        step "Removing $PKG package"
        if dpkg -l "$PKG" &>/dev/null; then
            sudo dpkg --remove "$PKG" && info "$PKG removed." || warn "dpkg remove $PKG failed — may not be installed."
        else
            warn "$PKG not installed via dpkg — skipping."
        fi
    done

    # ── Desktop shortcuts ─────────────────────────────────────────────────────
    step "Removing desktop shortcuts"
    remove_desktop_shortcut "ncspot"
    remove_desktop_shortcut "spotifyd"
    uninstall_spotify_web

    # ── Build folders ─────────────────────────────────────────────────────────
    local LEGACY_SCRIPT_DIR
    LEGACY_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    for DIR in ncspot spotifyd; do
        step "Removing build folder: $DIR"
        local FOUND=false
        if [[ -d "$SPOTIAPPS_BUILD_ROOT/$DIR" ]]; then
            rm -rf "${SPOTIAPPS_BUILD_ROOT:?}/$DIR" && info "$SPOTIAPPS_BUILD_ROOT/$DIR removed."
            FOUND=true
        fi
        # Legacy pre-v1.6.0 layout: build folder created next to the script itself.
        if [[ -d "$LEGACY_SCRIPT_DIR/$DIR" ]]; then
            rm -rf "${LEGACY_SCRIPT_DIR:?}/$DIR" && info "Legacy build folder removed: $LEGACY_SCRIPT_DIR/$DIR"
            FOUND=true
        fi
        [[ "$FOUND" == "false" ]] && warn "$DIR build folder not found — skipping."
    done
    # Clean up the now-empty build root (and its parent) if nothing is left in it.
    rmdir "$SPOTIAPPS_BUILD_ROOT" 2>/dev/null || true
    rmdir "$(dirname "$SPOTIAPPS_BUILD_ROOT")" 2>/dev/null || true

    # ── cargo-deb ─────────────────────────────────────────────────────────────
    step "Removing cargo-deb"
    source "$HOME/.cargo/env" 2>/dev/null || true
    if command -v cargo-deb &>/dev/null; then
        cargo uninstall cargo-deb 2>/dev/null && info "cargo-deb removed." || warn "cargo uninstall failed."
    else
        warn "cargo-deb not found — skipping."
    fi

    # ── Rust toolchain (optional) ─────────────────────────────────────────────
    step "Rust toolchain (optional)"
    if [[ -d "$HOME/.rustup" ]] || [[ -d "$HOME/.cargo" ]]; then
        echo ""
        echo "  The Rust toolchain (~/.cargo and ~/.rustup) is only needed to build"
        echo "  these apps. Safe to remove if you don't use Rust for anything else (~1-2 GB)."
        echo ""
        read -rp "$(echo -e "${CYAN}Remove the Rust toolchain? [y/N]:${NC} ")" RM_RUST
        if [[ "$RM_RUST" =~ ^[Yy]$ ]]; then
            if command -v rustup &>/dev/null; then
                source "$HOME/.cargo/env" 2>/dev/null || true
                rustup self uninstall -y && info "Rust toolchain removed."
            else
                rm -rf "$HOME/.cargo" "$HOME/.rustup" && info "Rust folders removed."
            fi
        else
            info "Rust toolchain kept."
        fi
    else
        warn "Rust toolchain not found — skipping."
    fi

    # ── ncspot config (optional) ──────────────────────────────────────────────
    step "ncspot config, credentials, and launcher (optional)"
    local NCSPOT_LAUNCHER_PATH="$HOME/.local/bin/ncspot-launch"
    if [[ -f "$NCSPOT_LAUNCHER_PATH" ]]; then
        rm -f "$NCSPOT_LAUNCHER_PATH" && info "RAM launcher removed: $NCSPOT_LAUNCHER_PATH"
    fi
    rm -rf /dev/shm/ncspot 2>/dev/null && info "RAM cache cleared: /dev/shm/ncspot" || true

    for DIR_INFO in \
        "$HOME/.config/ncspot:ncspot config" \
        "$HOME/.cache/ncspot-credentials:ncspot OAuth credentials (needed to skip re-login after reinstall)"; do
        DIR="${DIR_INFO%%:*}"; LABEL="${DIR_INFO##*:}"
        if [[ -d "$DIR" ]]; then
            SIZE=$(du -sh "$DIR" 2>/dev/null | cut -f1 || echo "?")
            echo ""
            echo "  Found $LABEL at: $DIR  ($SIZE)"
            [[ "$DIR" == *credentials* ]] && \
                echo "  Note: removing this will require you to log in to Spotify again after reinstall."
            read -rp "$(echo -e "${CYAN}Remove $LABEL? [y/N]:${NC} ")" RM_DIR
            if [[ "$RM_DIR" =~ ^[Yy]$ ]]; then
                rm -rf "$DIR" && info "$LABEL removed."
            else
                info "$LABEL kept."
            fi
        else
            warn "No $LABEL found — skipping."
        fi
    done

    # ── spotifyd config and launcher (optional) ───────────────────────────────
    step "spotifyd config and launcher (optional)"
    local SPOTIFYD_LAUNCHER_PATH="$HOME/.local/bin/spotifyd-launch"
    if [[ -f "$SPOTIFYD_LAUNCHER_PATH" ]]; then
        rm -f "$SPOTIFYD_LAUNCHER_PATH" && info "RAM launcher removed: $SPOTIFYD_LAUNCHER_PATH"
    fi
    rm -rf /dev/shm/spotifyd 2>/dev/null && info "RAM cache cleared: /dev/shm/spotifyd" || true

    DIR="$HOME/.config/spotifyd"
    if [[ -d "$DIR" ]]; then
        SIZE=$(du -sh "$DIR" 2>/dev/null | cut -f1 || echo "?")
        echo ""
        echo "  Found spotifyd config at: $DIR  ($SIZE)"
        read -rp "$(echo -e "${CYAN}Remove spotifyd config? [y/N]:${NC} ")" RM_DIR
        if [[ "$RM_DIR" =~ ^[Yy]$ ]]; then
            rm -rf "$DIR" && info "spotifyd config removed."
        else
            info "spotifyd config kept."
        fi
    else
        warn "No spotifyd config found — skipping."
    fi

    # ── Build-only apt packages ──────────────────────────────────────────────────
    # Build dependencies are kept on the system permanently. They are safe to leave
    # installed — many other applications may depend on them. If you want to remove
    # them manually later, you can do so with:
    #   sudo apt-get remove libncursesw5-dev libxcb1-dev libxcb-render0-dev \
    #       libxcb-shape0-dev libxcb-xfixes0-dev pkgconf
    info "Build packages are kept on your system (safe to leave installed)."
    info "libdbus-dev, libssl-dev, libpulse-dev/libasound2-dev also retained."

    echo ""
    divider
    echo -e "${GREEN}  Uninstall complete! Pi restored to pre-install state.${NC}"
    divider
    echo ""
    echo "  To reinstall, run this script again and choose option 1."
    echo ""
    exit 0
}

# =============================================================================
# HALF-INSTALL RECOVERY
# Checks if a package is in a broken dpkg state (half-installed, half-configured,
# triggers-awaited, etc.) and removes it cleanly before attempting a fresh install.
# A half-install happens when a previous dpkg -i was interrupted — power loss,
# Ctrl-C, or a crash mid-install. dpkg refuses to overwrite a broken package,
# so without this check the reinstall would fail immediately.
# Called automatically just before every dpkg -i — no manual steps needed.
# =============================================================================
clear_half_install() {
    local PKG="$1"
    local STATUS
    STATUS=$(dpkg-query -W -f='${Status}' "$PKG" 2>/dev/null || echo "")

    # dpkg status field format: "want flag status"
    # A healthy install is "install ok installed"
    # Broken states include: half-installed, half-configured, triggers-awaited,
    #                        triggers-pending, config-files (removed but config left)
    case "$STATUS" in
        *"half-installed"*|*"half-configured"*|*"triggers-awaited"*|*"triggers-pending"*)
            echo ""
            warn "$PKG is in a broken dpkg state: $STATUS"
            warn "Removing the broken package before reinstalling…"
            sudo dpkg --remove "$PKG" 2>/dev/null || \
                sudo dpkg --purge "$PKG" 2>/dev/null || true
            sudo dpkg --configure -a 2>/dev/null || true
            info "$PKG broken state cleared — proceeding with fresh install."
            echo ""
            ;;
        *"install ok installed"*)
            # Already cleanly installed — safe_uninstall_for_upgrade handles upgrades,
            # so nothing to do here.
            ;;
        *)
            # Not installed or unknown state — nothing to clear.
            ;;
    esac
}

# =============================================================================
# SAFE UNINSTALL BEFORE UPGRADE
# Called automatically by fetch_or_clone when a newer version is detected.
# Removes the binary, build folder, and shortcut before rebuilding to avoid
# stale Rust artifacts or broken dpkg state. Config files are always kept.
# =============================================================================
safe_uninstall_for_upgrade() {
    local APP="$1"            # ncspot | spotifyd
    local BUILD_ROOT_DIR="$2" # absolute path to fixed build root ($SPOTIAPPS_BUILD_ROOT)

    echo ""
    step "Clean uninstall of $APP before upgrade"
    echo ""
    echo -e "  ${YELLOW}A version change was detected. Running a clean uninstall first${NC}"
    echo -e "  ${YELLOW}to avoid stale build artifacts or broken dpkg state.${NC}"
    echo ""
    echo "  The following will be removed:"
    echo "    • $APP dpkg package (binary)"
    echo "    • $BUILD_ROOT_DIR/$APP build folder"
    echo "    • $APP desktop shortcut"
    echo ""
    echo "  The following will be KEPT:"
    echo "    • ~/.config/$APP/   (your config)"
    echo "    • Rust toolchain"
    echo ""

    # ── Remove dpkg package ───────────────────────────────────────────────────
    if dpkg -l "$APP" &>/dev/null; then
        info "Removing $APP package via dpkg..."
        sudo dpkg --remove "$APP" && info "$APP package removed." \
            || warn "dpkg remove $APP failed — may already be uninstalled."
    else
        info "$APP not currently installed via dpkg — skipping."
    fi

    # ── Remove build folder ───────────────────────────────────────────────────
    if [[ -d "$BUILD_ROOT_DIR/$APP" ]]; then
        info "Removing build folder: $BUILD_ROOT_DIR/$APP"
        rm -rf "${BUILD_ROOT_DIR:?}/$APP"
        info "Build folder removed."
    else
        info "No build folder found for $APP — skipping."
    fi

    # ── Remove desktop shortcut ───────────────────────────────────────────────
    remove_desktop_shortcut "$APP"

    echo ""
    info "Clean uninstall complete. Proceeding with fresh build of $APP."
    echo ""
}

# =============================================================================
# CLONE / UPDATE HELPER
# Returns 0 if a rebuild is needed, 1 if already up to date
# =============================================================================
fetch_or_clone() {
    local REPO_URL="$1"
    local DIR="$2"

    # Fixed $HOME-based build root (v1.6.0) — see SPOTIAPPS_BUILD_ROOT
    # declaration near the top of the script. No longer tied to the script's
    # own location, so it stays correct even if the script file is moved.
    mkdir -p "$SPOTIAPPS_BUILD_ROOT"
    local ABS_DIR="$SPOTIAPPS_BUILD_ROOT/$DIR"

    # ── One-time migration from the pre-v1.6.0 layout ────────────────────────
    # Versions through v1.5.2 cloned/built next to the script itself. If that
    # old folder exists and nothing has been cloned at the new fixed location
    # yet, move it rather than re-cloning/rebuilding from scratch — saves a
    # full Rust rebuild on Pi 4 hardware.
    if [[ ! -d "$ABS_DIR" ]]; then
        local LEGACY_SCRIPT_DIR LEGACY_DIR
        LEGACY_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
        LEGACY_DIR="$LEGACY_SCRIPT_DIR/$DIR"
        if [[ -d "$LEGACY_DIR/.git" && "$LEGACY_DIR" != "$ABS_DIR" ]]; then
            info "Found a pre-v1.6.0 $DIR build folder next to the script."
            info "Migrating it to $ABS_DIR (no rebuild needed)..."
            mv "$LEGACY_DIR" "$ABS_DIR"
            info "Migration complete."
        fi
    fi

    if [[ -d "$ABS_DIR/.git" ]]; then
        info "Existing $DIR repo found. Checking for updates..."
        cd "$ABS_DIR"
        if ! git fetch origin HEAD --quiet 2>/dev/null; then
            warn "Could not reach GitHub to check for updates (network issue?)."
            warn "Proceeding with the local copy of $DIR."
            cd "$SPOTIAPPS_BUILD_ROOT"
            return 0   # build with what we have rather than aborting
        fi

        local LOCAL_COMMIT REMOTE_COMMIT LOCAL_TAG REMOTE_TAG
        LOCAL_COMMIT=$(git rev-parse HEAD)
        REMOTE_COMMIT=$(git rev-parse FETCH_HEAD)
        LOCAL_TAG=$(git describe --tags --abbrev=0 2>/dev/null || echo "unknown")
        REMOTE_TAG=$(git describe --tags --abbrev=0 FETCH_HEAD 2>/dev/null || echo "unknown")

        if [[ "$LOCAL_COMMIT" == "$REMOTE_COMMIT" ]]; then
            echo ""
            echo -e "${GREEN}  $DIR is already up to date: $LOCAL_TAG (${LOCAL_COMMIT:0:7})${NC}"
            echo ""
            local EXISTING_DEB
            EXISTING_DEB=$(ls target/debian/${DIR}_*.deb 2>/dev/null | head -1 || true)
            if [[ -n "$EXISTING_DEB" ]]; then
                info "Existing .deb: $PWD/$EXISTING_DEB"
                cd "$SPOTIAPPS_BUILD_ROOT"
                return 1   # no rebuild needed
            else
                warn "No .deb found — will rebuild."
                git merge --ff-only FETCH_HEAD --quiet
            fi
        else
            echo ""
            echo -e "${YELLOW}  Update available for $DIR!${NC}"
            echo -e "  Current: $LOCAL_TAG  (${LOCAL_COMMIT:0:7})"
            echo -e "  Latest:  $REMOTE_TAG  (${REMOTE_COMMIT:0:7})"
            echo ""
            echo "  Recent changes:"
            echo "  ────────────────────────────────────────────"
            git log HEAD..FETCH_HEAD --oneline --no-decorate | head -15
            echo "  ────────────────────────────────────────────"
            echo ""
            read -rp "$(echo -e "${CYAN}  Rebuild $DIR with latest changes? [y/N]:${NC} ")" CONFIRM
            if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
                info "Update skipped for $DIR."
                cd "$SPOTIAPPS_BUILD_ROOT"
                return 1
            fi

            # ── Safe clean uninstall before upgrade ───────────────────────────
            # Step back to the build root before calling safe_uninstall_for_upgrade,
            # because that function will delete the build folder we are currently inside.
            # The build functions will re-clone via a second fetch_or_clone call below.
            local REPO_URL_SAVE="$REPO_URL"
            cd "$SPOTIAPPS_BUILD_ROOT"
            safe_uninstall_for_upgrade "$DIR" "$SPOTIAPPS_BUILD_ROOT"

            # Re-clone now that the build folder is gone, then return 0 so the
            # calling build function proceeds straight to cargo build.
            info "Re-cloning $DIR after clean uninstall..."
            git clone "$REPO_URL_SAVE" "$ABS_DIR"
            info "Re-clone complete."
            return 0
        fi
        cd "$SPOTIAPPS_BUILD_ROOT"
    else
        [[ -d "$ABS_DIR" ]] && { warn "$DIR exists but is not a git repo — removing..."; rm -rf "$ABS_DIR"; }
        info "Cloning $DIR from GitHub..."
        git clone "$REPO_URL" "$ABS_DIR"
        info "Clone complete."
    fi
    return 0   # rebuild needed
}

# =============================================================================
# BUILD ncspot
# Source: https://github.com/hrkfdn/ncspot
# Features ref: https://github.com/hrkfdn/ncspot/blob/main/Cargo.toml
# =============================================================================
build_ncspot() {
    divider
    echo -e "${BOLD}  Building ncspot${NC}"
    divider

    # Build folder lives at the fixed $HOME-based SPOTIAPPS_BUILD_ROOT (v1.6.0),
    # not relative to the caller's CWD or the script's own location. Remember
    # the caller's original CWD so it can be restored on every return path.
    local ORIG_PWD="$PWD"

    # Capture return code without tripping set -e:
    # fetch_or_clone returns 1 when the repo is already up to date (skip build).
    # A bare call would abort the script under `set -e`, so guard it explicitly.
    local SKIP=0
    fetch_or_clone "https://github.com/hrkfdn/ncspot.git" "ncspot" || SKIP=$?
    if [[ $SKIP -eq 1 ]]; then
        cd "$ORIG_PWD"
        return
    fi

    cd "$SPOTIAPPS_BUILD_ROOT/ncspot"

    echo ""
    echo -e "  ${CYAN}ncspot features being compiled:${NC}"
    echo "    mpris             — Media key support + D-Bus / playerctl control"
    echo "    $AUDIO_BACKEND    — Auto-detected audio backend"
    echo "    notify            — Now-playing desktop notifications"
    echo "    share_clipboard   — Copy track/playlist URLs to clipboard"
    echo "    crossterm_backend — Terminal rendering"
    echo ""

    # Build
    # --no-default-features for a clean explicit feature set (no backend conflicts)
    # cover feature intentionally omitted — not used, and it requires ueberzug
    # at runtime which renders poorly on the Pi's small touchscreen.
    # Feature reference: https://github.com/hrkfdn/ncspot/blob/main/Cargo.toml
    cargo build --release \
        --no-default-features \
        --features "mpris,${AUDIO_BACKEND},notify,share_clipboard,crossterm_backend"

    info "ncspot binary built: target/release/ncspot"

    # Package
    cargo deb --no-build
    info "ncspot .deb packaged."

    NCSPOT_DEB=$(ls target/debian/ncspot_*.deb 2>/dev/null | head -1)
    [[ -z "$NCSPOT_DEB" ]] && error "ncspot .deb not found after packaging."

    echo ""
    divider
    echo -e "${GREEN}  ncspot .deb ready: $PWD/$NCSPOT_DEB${NC}"
    divider
    echo ""

    read -rp "$(echo -e "${CYAN}Install ncspot now? [y/N]:${NC} ")" INSTALL_NCSPOT
    if [[ "$INSTALL_NCSPOT" =~ ^[Yy]$ ]]; then
        clear_half_install "ncspot"
        sudo dpkg -i "$NCSPOT_DEB"
        info "ncspot installed."

        # ── RAM cache strategy ────────────────────────────────────────────────
        # ncspot uses --basepath to redirect all runtime dirs to /dev/shm/ncspot.
        # Audio cache stays in RAM — zero SD card writes during playback.
        # OAuth credentials (~a few KB) are the only thing persisted to disk;
        # the launcher copies them into RAM on start and saves them back on exit.
        # Reference: https://github.com/hrkfdn/ncspot/blob/main/doc/users.md
        NCSPOT_CONF_DIR="$HOME/.config/ncspot"
        NCSPOT_CONF_FILE="$NCSPOT_CONF_DIR/config.toml"
        NCSPOT_CRED_DIR="$HOME/.cache/ncspot-credentials"   # persistent on disk (tiny)
        NCSPOT_RAM_DIR="/dev/shm/ncspot"                     # runtime basepath in RAM
        NCSPOT_LAUNCHER="$HOME/.local/bin/ncspot-launch"

        mkdir -p "$NCSPOT_CONF_DIR"
        mkdir -p "$NCSPOT_CRED_DIR"

        if [[ ! -f "$NCSPOT_CONF_FILE" ]]; then
            cat > "$NCSPOT_CONF_FILE" << 'CONF'
# ncspot configuration
# Full reference: https://github.com/hrkfdn/ncspot/blob/main/doc/users.md

# ── Audio ─────────────────────────────────────────────────────────────────────
bitrate = 320          # 96 / 160 / 320 kbps  (320 = highest quality)
gapless = true         # Gapless playback between tracks

# ── Audio cache (RAM) ─────────────────────────────────────────────────────────
# Audio buffering is redirected to /dev/shm by the ncspot-launch wrapper
# via --basepath /dev/shm/ncspot. These settings control that cache.
audio_cache = true     # Enable librespot audio buffer (improves seek responsiveness)
audio_cache_size = 512 # Cap at 512 MiB — safe on Pi 4 (4 GB RAM)

# ── Volume ────────────────────────────────────────────────────────────────────
volnorm = true         # Volume normalisation across tracks
volnorm_pregain = 0.0  # Normalisation pre-gain in dB (raise if output is too quiet)

# ── Display ───────────────────────────────────────────────────────────────────
use_nerdfont = false   # Set true if your terminal uses a Nerd Font
notify = true          # Desktop notifications for now-playing

# ── Playback defaults ─────────────────────────────────────────────────────────
shuffle = false
repeat = "off"         # "off" / "track" / "playlist"
playback_state = "Paused"
CONF
            info "ncspot config created at: $NCSPOT_CONF_FILE"
        else
            info "Existing ncspot config kept: $NCSPOT_CONF_FILE"
            # Ensure audio_cache and audio_cache_size are set for RAM mode
            if ! grep -q "^audio_cache" "$NCSPOT_CONF_FILE"; then
                echo "" >> "$NCSPOT_CONF_FILE"
                echo "# Added by installer — audio cache in RAM via ncspot-launch --basepath" >> "$NCSPOT_CONF_FILE"
                echo "audio_cache = true" >> "$NCSPOT_CONF_FILE"
                echo "audio_cache_size = 512" >> "$NCSPOT_CONF_FILE"
                info "Added audio_cache settings to existing config."
            fi
        fi

        # ── RAM launcher wrapper ───────────────────────────────────────────────
        # Launches ncspot with --basepath /dev/shm/ncspot so all runtime I/O
        # (audio buffer, socket, state) lives in RAM.
        # OAuth credentials (~a few KB) are seeded from disk into the RAM
        # basepath before launch and saved back on clean exit.
        # Reference: https://github.com/hrkfdn/ncspot/blob/main/doc/users.md
        mkdir -p "$HOME/.local/bin"
        cat > "$NCSPOT_LAUNCHER" << LAUNCHER
#!/usr/bin/env bash
# ncspot-launch — RAM basepath wrapper for ncspot
# Directs all runtime I/O (audio cache, socket, state) to /dev/shm.
# OAuth credentials are copied from disk into RAM on start and saved on exit.

RAM_DIR="${NCSPOT_RAM_DIR}"
CRED_DIR="${NCSPOT_CRED_DIR}"
CONF_DIR="${NCSPOT_CONF_DIR}"

# Create RAM basepath directory structure expected by --basepath
mkdir -p "\${RAM_DIR}/.cache/ncspot/librespot"
mkdir -p "\${RAM_DIR}/.config/ncspot"
mkdir -p "\${RAM_DIR}/.local/share/ncspot"
mkdir -p "\${RAM_DIR}/.local/state/ncspot"
chmod -R 700 "\${RAM_DIR}"

# Seed OAuth credentials from persistent disk store into RAM
if [[ -f "\${CRED_DIR}/credentials.json" ]]; then
    cp "\${CRED_DIR}/credentials.json" "\${RAM_DIR}/.cache/ncspot/librespot/credentials.json"
    echo "[ncspot-launch] OAuth credentials loaded into RAM."
else
    echo "[ncspot-launch] No saved credentials — ncspot will prompt for login."
fi

# Link config.toml from real config dir into RAM basepath so user edits persist
ln -sf "\${CONF_DIR}/config.toml" "\${RAM_DIR}/.config/ncspot/config.toml" 2>/dev/null || \
    cp "\${CONF_DIR}/config.toml" "\${RAM_DIR}/.config/ncspot/config.toml"

echo "[ncspot-launch] Audio cache in RAM: \${RAM_DIR}/.cache  (cap: 512 MiB)"
echo "[ncspot-launch] Starting ncspot…"
echo ""

# Save credentials back to disk on exit (any exit — clean, crash, or Ctrl-C)
save_credentials() {
    echo ""
    echo "[ncspot-launch] Saving OAuth credentials to disk…"
    mkdir -p "\${CRED_DIR}"
    chmod 700 "\${CRED_DIR}"
    if [[ -f "\${RAM_DIR}/.cache/ncspot/librespot/credentials.json" ]]; then
        cp "\${RAM_DIR}/.cache/ncspot/librespot/credentials.json" "\${CRED_DIR}/credentials.json"
        echo "[ncspot-launch] Credentials saved to: \${CRED_DIR}"
    fi
    # Wipe RAM basepath — audio cache gone, credentials safely on disk
    rm -rf "\${RAM_DIR}"
    echo "[ncspot-launch] RAM cache cleared."
}
trap save_credentials EXIT

# Launch ncspot with RAM as the basepath
# --basepath redirects all .cache/.config/.local dirs under /dev/shm/ncspot
exec ncspot --basepath "\${RAM_DIR}" "\$@"
LAUNCHER
        chmod +x "$NCSPOT_LAUNCHER"
        info "RAM launcher installed: $NCSPOT_LAUNCHER"

        # ── Desktop shortcut ──────────────────────────────────────────────────
        # Calls the RAM launcher wrapper instead of ncspot directly.
        install_desktop_shortcut \
            "ncspot" \
            "ncspot" \
            "Music Player" \
            "Terminal Spotify client — Vim keybindings, MPRIS" \
            "x-terminal-emulator -e ${NCSPOT_LAUNCHER}"

        echo ""
        echo -e "${GREEN}  ncspot ready!${NC}"
        echo "    • Launch from terminal:   ncspot-launch"
        echo "    • Launch from app menu:   Sound & Video → ncspot"
        echo "    • Media keys:             MPRIS active via D-Bus"
        echo "    • RAM audio cache:        /dev/shm/ncspot  (512 MiB cap, cleared on exit)"
        echo "    • OAuth credentials:      $NCSPOT_CRED_DIR  (saved on exit)"
        echo "    • Config:                 $NCSPOT_CONF_FILE"
        echo "    • Config reference:       https://github.com/hrkfdn/ncspot/blob/main/doc/users.md"
    else
        echo ""
        echo "  To install later:  sudo dpkg -i $PWD/$NCSPOT_DEB"
        echo "  Note: RAM launcher, config, and desktop shortcut are created automatically on install."
    fi

    cd "$ORIG_PWD"
}

# =============================================================================
# BUILD spotifyd
# Source: https://github.com/Spotifyd/spotifyd
# Config ref: https://spotifyd.github.io/spotifyd/config/File.html
# Cargo features: https://github.com/Spotifyd/spotifyd/blob/master/Cargo.toml
#
# Features:
#   $AUDIO_BACKEND — matches same backend chosen for ncspot (PulseAudio/ALSA)
#   dbus_mpris     — MPRIS D-Bus support: media keys, playerctl integration
#
# Spotify Connect is always active in spotifyd — no extra flag needed.
# Once running, the Pi appears as a speaker in every Spotify app on the network.
# =============================================================================
build_spotifyd() {
    divider
    echo -e "${BOLD}  Building spotifyd${NC}"
    divider

    # Build folder lives at the fixed $HOME-based SPOTIAPPS_BUILD_ROOT (v1.6.0),
    # not relative to the caller's CWD or the script's own location. Remember
    # the caller's original CWD so it can be restored on every return path.
    local ORIG_PWD="$PWD"

    # Capture return code without tripping set -e (see build_ncspot for details).
    local SKIP=0
    fetch_or_clone "https://github.com/Spotifyd/spotifyd.git" "spotifyd" || SKIP=$?
    if [[ $SKIP -eq 1 ]]; then
        cd "$ORIG_PWD"
        return
    fi

    cd "$SPOTIAPPS_BUILD_ROOT/spotifyd"

    echo ""
    echo -e "  ${CYAN}spotifyd features being compiled:${NC}"
    echo "    $AUDIO_BACKEND — Auto-detected audio backend"
    echo "    dbus_mpris     — MPRIS D-Bus + media key support"
    echo ""
    echo -e "  ${CYAN}Spotify Connect:${NC}"
    echo "    Always active — your Pi will appear as a speaker in every"
    echo "    Spotify app on the same network once spotifyd is running."
    echo "    Reference: https://github.com/Spotifyd/spotifyd"
    echo ""

    # Build
    # Feature reference: https://github.com/Spotifyd/spotifyd/blob/master/Cargo.toml
    cargo build --release \
        --no-default-features \
        --features "${AUDIO_BACKEND},dbus_mpris"

    info "spotifyd binary built: target/release/spotifyd"

    # Package
    cargo deb --no-build
    info "spotifyd .deb packaged."

    SPOTIFYD_DEB=$(ls target/debian/spotifyd_*.deb 2>/dev/null | head -1)
    [[ -z "$SPOTIFYD_DEB" ]] && error "spotifyd .deb not found after packaging."

    echo ""
    divider
    echo -e "${GREEN}  spotifyd .deb ready: $PWD/$SPOTIFYD_DEB${NC}"
    divider
    echo ""

    read -rp "$(echo -e "${CYAN}Install spotifyd now? [y/N]:${NC} ")" INSTALL_SPOTIFYD
    if [[ "$INSTALL_SPOTIFYD" =~ ^[Yy]$ ]]; then
        clear_half_install "spotifyd"
        sudo dpkg -i "$SPOTIFYD_DEB"
        info "spotifyd installed."

        # ── Create config file if it doesn't exist ────────────────────────────
        # Reference: https://spotifyd.github.io/spotifyd/config/File.html
        #
        # Discovery (Zeroconf) mode — no login needed:
        #   Once spotifyd is running, open the Spotify app on any device on your
        #   network, tap the speaker/device icon, and select this Pi. Spotify
        #   authenticates automatically via the Connect network handshake.
        #   Nothing is stored — each session re-handshakes, so there are no
        #   credentials to persist and nothing sensitive written to disk.
        #
        # RAM cache:
        #   The audio buffer is pointed at /dev/shm (RAM), so playback never
        #   writes to the SD card. The cache is created fresh on launch and
        #   cleared on exit by the spotifyd-launch wrapper.
        #
        # NOTE: Username/password authentication was removed by Spotify in 2024.
        SPOTIFYD_CONF_DIR="$HOME/.config/spotifyd"
        SPOTIFYD_CONF_FILE="$SPOTIFYD_CONF_DIR/spotifyd.conf"
        SPOTIFYD_RAM_DIR="/dev/shm/spotifyd"                     # runtime RAM cache
        SPOTIFYD_LAUNCHER="$HOME/.local/bin/spotifyd-launch"

        if [[ ! -f "$SPOTIFYD_CONF_FILE" ]]; then
            mkdir -p "$SPOTIFYD_CONF_DIR"
            PI_HOSTNAME=$(hostname)
            cat > "$SPOTIFYD_CONF_FILE" << CONF
# spotifyd configuration
# Full config reference: https://spotifyd.github.io/spotifyd/config/File.html
#
# Discovery mode (no login needed):
#   Run spotifyd, open the Spotify app on any device on your network,
#   tap the speaker/device icon, and select this Pi. Spotify authenticates
#   automatically over the network — no credentials are stored.
#
# NOTE: Username/password authentication was removed by Spotify in 2024.
#       Do NOT add username= or password= lines — they no longer work.

[global]
# The name this Pi appears as in Spotify Connect device lists on your network.
device_name = "${PI_HOSTNAME}-spotifyd"

# Audio backend — auto-detected to match your Pi's audio system.
# Bookworm (PipeWire): pulse   |   Older Pi OS: pulse   |   Minimal: alsa
backend = "${AUDIO_BACKEND//_backend/}"

# Streaming bitrate: 96, 160, or 320 kbps  (320 = highest quality)
bitrate = 320

# RAM cache — audio buffer lives entirely in /dev/shm (never written to SD card).
# Created fresh on launch and cleared on exit by the spotifyd-launch wrapper.
cache_path = "${SPOTIFYD_RAM_DIR}"

# Volume control: softvol (software), alsa (hardware mixer), or none
volume_controller = "softvol"

# Zeroconf port for Spotify Connect discovery.
# Leave commented to use a random port (works for most setups).
# zeroconf_port = 4070
CONF
            info "spotifyd config created at: $SPOTIFYD_CONF_FILE"
        else
            info "Existing spotifyd config kept: $SPOTIFYD_CONF_FILE"
            if grep -q "cache_path" "$SPOTIFYD_CONF_FILE"; then
                sed -i "s|cache_path\s*=.*|cache_path = \"${SPOTIFYD_RAM_DIR}\"|" "$SPOTIFYD_CONF_FILE"
                info "Updated cache_path in existing config to RAM location."
            fi
        fi

        # ── RAM launcher wrapper script ────────────────────────────────────────
        # Creates the /dev/shm audio cache at startup and clears it on exit.
        # Discovery mode means there are no credentials to manage.
        mkdir -p "$HOME/.local/bin"
        cat > "$SPOTIFYD_LAUNCHER" << LAUNCHER
#!/usr/bin/env bash
# spotifyd-launch — RAM cache wrapper for spotifyd (Discovery mode)
# Keeps the audio buffer in /dev/shm (RAM) so playback never touches the
# SD card. The cache is created fresh on start and wiped on exit.

RAM_DIR="${SPOTIFYD_RAM_DIR}"

# Create fresh RAM cache dir
mkdir -p "\${RAM_DIR}"
chmod 700 "\${RAM_DIR}"

echo "[spotifyd-launch] Audio cache running in RAM: \${RAM_DIR}"
echo "[spotifyd-launch] Discovery mode — open the Spotify app on any device"
echo "[spotifyd-launch] on your network and select this Pi as the speaker."
echo "[spotifyd-launch] Starting spotifyd…"
echo ""

# Wipe RAM cache on any exit (clean, crash, or Ctrl-C)
cleanup() {
    echo ""
    rm -rf "\${RAM_DIR}"
    echo "[spotifyd-launch] RAM cache cleared."
}
trap cleanup EXIT

exec spotifyd --no-daemon "\$@"
LAUNCHER
        chmod +x "$SPOTIFYD_LAUNCHER"
        info "RAM launcher installed: $SPOTIFYD_LAUNCHER"

        # ── Desktop shortcut ──────────────────────────────────────────────────
        # Calls the RAM launcher wrapper instead of spotifyd directly.
        install_desktop_shortcut \
            "spotifyd" \
            "Spotifyd (Spotify Connect)" \
            "Spotify Connect Speaker" \
            "Make this Pi a Spotify Connect speaker visible on your network" \
            "x-terminal-emulator -e ${SPOTIFYD_LAUNCHER}"

        echo ""
        echo -e "${GREEN}  spotifyd ready!${NC}"
        echo "    • Launch from app menu:   Sound & Video → Spotifyd (Spotify Connect)"
        echo "    • Launch from terminal:   spotifyd-launch"
        echo "    • RAM cache:              /dev/shm/spotifyd  (cleared on exit)"
        echo "    • No login needed:        open Spotify on any device on your"
        echo "                              network and select this Pi as a speaker"
        echo "    • Config file:            $SPOTIFYD_CONF_FILE"
    else
        echo ""
        echo "  To install later:  sudo dpkg -i $PWD/$SPOTIFYD_DEB"
        echo "  Note: desktop shortcut and config are created automatically on install."
    fi

    cd "$ORIG_PWD"
}

# =============================================================================
# RUN THE SELECTED ACTION
# =============================================================================
[[ "$UNINSTALL_MODE"        == "true" ]] && do_uninstall
[[ "$UNINSTALL_NCSPOT"      == "true" ]] && uninstall_ncspot
[[ "$UNINSTALL_SPOTIFYD"    == "true" ]] && uninstall_spotifyd
[[ "$UNINSTALL_SPOTIFY_WEB" == "true" ]] && uninstall_spotify_web
[[ "$INSTALL_SPOTIFY_WEB"   == "true" ]] && install_spotify_web

# Only run shared build setup when actually building ncspot or spotifyd
if [[ "$BUILD_NCSPOT" == "true" || "$BUILD_SPOTIFYD" == "true" ]]; then

# ── Platform check ────────────────────────────────────────────────────────────
step "Platform check"
ARCH=$(uname -m)
info "Detected architecture: $ARCH"
[[ "$ARCH" != "aarch64" && "$ARCH" != "armv7l" ]] && \
    warn "Designed for arm64/armhf. Detected $ARCH — continuing anyway."

# ── Auto-detect audio system ──────────────────────────────────────────────────
#
# Raspberry Pi OS Bookworm / Trixie: PipeWire (exposes PulseAudio-compatible interface)
# Older Pi OS / Bullseye:            PulseAudio
# Minimal installs:                  ALSA fallback
#
# References:
#   https://www.raspberrypi.com/news/bookworm-the-new-version-of-raspberry-pi-os/
#   https://github.com/hrkfdn/ncspot/blob/main/Cargo.toml
#   https://github.com/Spotifyd/spotifyd/blob/master/Cargo.toml

step "Detecting active audio system"
AUDIO_BACKEND=""
AUDIO_DEP=""

if systemctl --user is-active --quiet pipewire-pulse 2>/dev/null || \
   pactl info 2>/dev/null | grep -qi "pipewire"; then
    info "PipeWire detected — using pulseaudio_backend."
    AUDIO_BACKEND="pulseaudio_backend"
    AUDIO_DEP="libpulse-dev"
elif systemctl --user is-active --quiet pulseaudio 2>/dev/null || \
     pactl info 2>/dev/null | grep -qi "pulseaudio"; then
    info "PulseAudio detected — using pulseaudio_backend."
    AUDIO_BACKEND="pulseaudio_backend"
    AUDIO_DEP="libpulse-dev"
else
    warn "No PipeWire/PulseAudio detected — falling back to alsa_backend."
    warn "Check your audio setup with:  aplay -l"
    AUDIO_BACKEND="alsa_backend"
    AUDIO_DEP="libasound2-dev"
fi
info "Audio backend: $AUDIO_BACKEND"

# ── System dependencies ───────────────────────────────────────────────────────
#
# playerctl: runtime dependency for MPRIS control (media keys, playerctl CLI,
#   desktop environment integration). Without it, ncspot's mpris feature compiles
#   correctly but has nothing to receive commands from at runtime.
#   Reference: https://github.com/altdesktop/playerctl
step "Installing system dependencies"
sudo apt-get update -qq
sudo apt-get install -y \
    build-essential curl git python3 pkgconf \
    libdbus-1-dev libncursesw5-dev libssl-dev \
    libxcb1-dev libxcb-render0-dev libxcb-shape0-dev libxcb-xfixes0-dev \
    desktop-file-utils \
    playerctl \
    "$AUDIO_DEP"
info "System dependencies ready."

# ── Rust toolchain ────────────────────────────────────────────────────────────
step "Rust toolchain"
if ! command -v cargo &>/dev/null; then
    info "Installing Rust via rustup..."
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --no-modify-path
    source "$HOME/.cargo/env"
    info "Rust installed: $(rustc --version)"
else
    source "$HOME/.cargo/env" 2>/dev/null || true
    info "Rust already installed: $(rustc --version)"
    info "Updating Rust toolchain..."
    rustup update stable --no-self-update
fi

# ── cargo-deb ─────────────────────────────────────────────────────────────────
# Reference: https://github.com/hrkfdn/ncspot/blob/main/doc/package_maintainers.md
step "cargo-deb"
if ! command -v cargo-deb &>/dev/null; then
    cargo install cargo-deb && info "cargo-deb installed."
else
    cargo install cargo-deb --force && info "cargo-deb updated."
fi

# ── Run the builds ────────────────────────────────────────────────────────────
[[ "$BUILD_NCSPOT"   == "true" ]] && build_ncspot
[[ "$BUILD_SPOTIFYD" == "true" ]] && build_spotifyd

fi  # end build guard

# ── Final summary — only shown after a build or install action ────────────────
if [[ "$BUILD_NCSPOT" == "true" || "$BUILD_SPOTIFYD" == "true" || "$INSTALL_SPOTIFY_WEB" == "true" ]]; then
echo ""
divider
echo -e "${BOLD}  All done!${NC}"
divider
echo ""
if [[ "$INSTALL_SPOTIFY_WEB" == "true" ]]; then
    echo -e "  ${CYAN}Spotify Web${NC} — Chromium PWA shortcut"
    echo "              App menu: Sound & Video → Spotify Web"
    echo "              Cache runs in RAM (/dev/shm/spotify-web-cache)"
fi
if [[ "$BUILD_NCSPOT" == "true" ]]; then
    echo -e "  ${CYAN}ncspot${NC}    — Terminal Spotify client"
    echo "              Launch: ncspot-launch  |  App menu: Sound & Video → ncspot"
    echo "              Audio cache runs in RAM (/dev/shm/ncspot)"
fi
if [[ "$BUILD_SPOTIFYD" == "true" ]]; then
    echo -e "  ${CYAN}spotifyd${NC}  — Spotify Connect speaker daemon"
    echo "              Launch: spotifyd-launch  |  App menu: Sound & Video → Spotifyd"
    echo "              Audio cache runs in RAM (/dev/shm/spotifyd)"
    echo ""
    echo -e "  ${CYAN}No login needed (Discovery mode):${NC}"
    echo "    Launch spotifyd, then open the Spotify app on any device on your"
    echo "    network and select this Pi from the speaker list."
fi
echo ""
echo "  References:"
echo "    ncspot source:        https://github.com/hrkfdn/ncspot"
echo "    ncspot features:      https://github.com/hrkfdn/ncspot/blob/main/Cargo.toml"
echo "    spotifyd source:      https://github.com/Spotifyd/spotifyd"
echo "    spotifyd features:    https://github.com/Spotifyd/spotifyd/blob/master/Cargo.toml"
echo "    spotifyd config:      https://spotifyd.github.io/spotifyd/config/File.html"
echo "    spotifyd auth:        https://docs.spotifyd.rs/configuration/auth.html"
echo "    Pi OS Trixie release: https://www.raspberrypi.com/news/raspberry-pi-os-trixie/"
echo "    MPRIS spec:           https://specifications.freedesktop.org/mpris-spec/latest/"
fi
