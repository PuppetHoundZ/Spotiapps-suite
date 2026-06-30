# Spotiapps Suite — Raspberry Pi

A single self-contained bash script that installs and manages three Spotify apps on Raspberry Pi OS Trixie: **ncspot**, **spotifyd**, and a tuned **Spotify Web** Chromium shortcut. Menu-driven, clean uninstalls, no system breakage.

> Built and tested on a Raspberry Pi 4 (Pi OS Trixie, Debian 13 arm64) with a 7" 800×480 touchscreen and 1080p HDMI output.

## What it manages

| App | What it is | Source |
|---|---|---|
| **ncspot** | Terminal Spotify client — Vim keybindings, MPRIS media key support | [hrkfdn/ncspot](https://github.com/hrkfdn/ncspot) |
| **spotifyd** | Spotify Connect daemon — makes your Pi appear as a speaker in any Spotify app on your network | [Spotifyd/spotifyd](https://github.com/Spotifyd/spotifyd) |
| **Spotify Web** | Chromium PWA shortcut to open.spotify.com — isolated profile, RAM cache, tuned flags | — |

ncspot and spotifyd are compiled from source via Rust/Cargo and packaged as `.deb` files. All three apps get desktop/app-menu shortcuts with embedded SVG icons.

## Requirements

- Raspberry Pi OS Trixie (Debian 13) with desktop
- Internet connection
- ~2 GB free disk space (Rust toolchain + build artifacts — ncspot/spotifyd only)
- Spotify **Premium** required for ncspot and spotifyd
- Spotify Web works with both free and Premium accounts

## Install

```bash
chmod +x Spotiapps_suite.sh
./Spotiapps_suite.sh
```

The script opens a menu:

```
1) Build / Update both ncspot and spotifyd
2) Build / Update ncspot only
3) Build / Update spotifyd only
4) Install Spotify Web shortcut
5) Uninstall ncspot only
6) Uninstall spotifyd only
7) Uninstall Spotify Web shortcut
8) Uninstall everything and restore Pi to original state
9) Exit
```

The menu also shows a live status block (installed/missing) for each app before you choose.

## Where things live

The script file itself can be stored, renamed, and moved anywhere you like (a synced folder, a USB stick, wherever) — it doesn't need to sit next to anything else. Everything it creates always lands in fixed, predictable locations:

| What | Where |
|---|---|
| ncspot / spotifyd source + build | `~/.local/share/spotiapps-suite/build/` |
| ncspot / spotifyd binaries | installed via `dpkg` |
| ncspot config | `~/.config/ncspot/` |
| ncspot OAuth credentials | `~/.cache/ncspot-credentials/` |
| spotifyd config | `~/.config/spotifyd/` |
| Spotify Web Chromium profile | `~/.config/webapps/spotify-web/` |
| Audio cache (ncspot/spotifyd, runtime) | `/dev/shm/` (RAM, cleared on exit) |
| Spotify Web disk cache | `/dev/shm/spotify-web-cache` (RAM) |
| App menu shortcuts | `~/.local/share/applications/` |
| Icons | `~/.local/share/icons/hicolor/scalable/apps/` |
| Optional pinned desktop launcher (Spotify Web) | `~/Desktop/` (prompted on install) |

## Audio

Raspberry Pi OS Trixie uses **PipeWire**, which exposes a PulseAudio-compatible interface. The script auto-detects PipeWire / PulseAudio / ALSA at build time and picks the right backend automatically — no manual configuration needed.

ncspot and spotifyd only ever run in your user session, launched on demand. Nothing is installed as a system service and nothing auto-starts at boot.

## Spotify Connect (spotifyd)

spotifyd implements the full Spotify Connect (SPIRC) protocol. Once running, your Pi shows up as a speaker in the Spotify app on any device on the same network — no login required on the Pi itself (discovery mode).

## MPRIS (ncspot)

ncspot compiles with the `mpris` feature, enabling D-Bus media control — media keys, `playerctl`, and desktop environment integration. Requires the `playerctl` package, which the script installs automatically.

## Clean uninstall philosophy

Uninstalling an app always removes its binary, build folder, desktop shortcut, icon, and RAM cache. Config files and credentials are optional — you're asked before they're removed, so reinstalling later can pick up where you left off.

Shared system dependencies (build tools, Rust toolchain, audio libraries, etc.) are **never** removed automatically — they're left in place to avoid breaking anything else on your Pi that might depend on them. The full "uninstall everything" option will offer to remove the Rust toolchain and `cargo-deb`, but only if you confirm.

## References

- ncspot source: https://github.com/hrkfdn/ncspot
- ncspot features (Cargo.toml): https://github.com/hrkfdn/ncspot/blob/main/Cargo.toml
- spotifyd source: https://github.com/Spotifyd/spotifyd
- spotifyd features (Cargo.toml): https://github.com/Spotifyd/spotifyd/blob/master/Cargo.toml
- spotifyd config reference: https://spotifyd.github.io/spotifyd/config/File.html
- spotifyd auth: https://docs.spotifyd.rs/configuration/auth.html
- MPRIS spec: https://specifications.freedesktop.org/mpris-spec/latest/
- Raspberry Pi OS Trixie release notes: https://www.raspberrypi.com/news/raspberry-pi-os-trixie/

## Disclaimer

This script is provided as-is, free of charge, as part of an open source community effort for Raspberry Pi users. It is not affiliated with or endorsed by the ncspot project, spotifyd project, Raspberry Pi Ltd, or Spotify AB. Use it at your own risk. No warranty is expressed or implied.

If it helps you — great. If you improve it — share it back.
