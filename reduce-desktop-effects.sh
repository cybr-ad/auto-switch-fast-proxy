#!/usr/bin/env bash
# Reduce desktop animations and decorative effects on Parrot OS.
# Does not uninstall packages, remove desktop environments, or require sudo.
set -Eeuo pipefail

CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"

usage() {
  cat <<'USAGE'
Usage:
  ./reduce-desktop-effects.sh
  ./reduce-desktop-effects.sh --restore /path/to/desktop-effects-backup-YYYYMMDD-HHMMSS

The normal run saves the previous relevant settings before changing them.
If running inside VirtualBox, it also checks Guest Additions and can offer to install
Parrot's recommended guest packages and start clipboard/display helpers.
Supported desktop environments: KDE Plasma, MATE, XFCE, and GNOME.
USAGE
}

reload_kde() {
  if command -v qdbus6 >/dev/null 2>&1; then
    qdbus6 org.kde.KWin /KWin reconfigure >/dev/null 2>&1 || true
  elif command -v qdbus >/dev/null 2>&1; then
    qdbus org.kde.KWin /KWin reconfigure >/dev/null 2>&1 || true
  fi
}

is_virtualbox_guest() {
  local info="" file virt=""
  for file in /sys/class/dmi/id/sys_vendor /sys/class/dmi/id/product_name /sys/class/dmi/id/board_vendor; do
    if [[ -r "$file" ]]; then info+=" $(cat -- "$file" 2>/dev/null || true)"; fi
  done
  if [[ "$info" =~ [Vv]irtual[Bb]ox ]]; then
    return 0
  fi
  if command -v systemd-detect-virt >/dev/null 2>&1; then
    virt="$(systemd-detect-virt --vm 2>/dev/null || true)"
    [[ "$virt" == "oracle" || "$virt" == "virtualbox" ]] && return 0
  fi
  return 1
}

vboxclient_running() {
  local mode="$1"
  pgrep -u "$(id -u)" -f "[V]BoxClient.*--${mode}" >/dev/null 2>&1
}

start_vboxclient() {
  local mode="$1"
  if vboxclient_running "$mode"; then
    echo "  VBoxClient --$mode is already running."
    return 0
  fi
  nohup VBoxClient "--$mode" >/dev/null 2>&1 &
  sleep 1
  if vboxclient_running "$mode"; then
    echo "  Started VBoxClient --$mode."
  else
    echo "  Could not confirm VBoxClient --$mode started; check Guest Additions and logs."
  fi
}

fix_virtualbox_integration() {
  local status help_output answer
  if ! is_virtualbox_guest; then
    echo "VirtualBox integration: no VirtualBox guest detected; skipped."
    return 0
  fi

  echo
  echo "VirtualBox guest detected: checking Guest Additions for clipboard and display resizing."
  local missing=0 package
  for package in virtualbox-guest-utils virtualbox-guest-x11; do
    status="$(dpkg-query -W -f='${Status}' "$package" 2>/dev/null || true)"
    if [[ "$status" != "install ok installed" ]]; then missing=1; fi
  done

  if (( missing )); then
    echo "Guest Additions packages are missing or not fully installed."
    read -r -p "Install virtualbox-guest-utils and virtualbox-guest-x11 using APT? [y/N] " answer
    case "$answer" in
      y|Y|yes|YES)
        if ! command -v apt-get >/dev/null 2>&1; then
          echo "ERROR: APT is not available; install the Guest Additions packages manually."
          return 0
        fi
        if sudo apt-get update && sudo apt-get install -y virtualbox-guest-utils virtualbox-guest-x11; then
          echo "Guest Additions packages installed. A reboot is recommended after this script."
        else
          echo "WARNING: package installation did not complete. Check the APT error output."
          return 0
        fi
        ;;
      *)
        echo "Skipped package installation. Clipboard and dynamic resizing may remain unavailable."
        return 0
        ;;
    esac
  else
    echo "Guest Additions packages are installed."
  fi

  if ! command -v VBoxClient >/dev/null 2>&1; then
    echo "WARNING: VBoxClient is not available even though package checks completed."
    echo "Try: sudo apt install --reinstall virtualbox-guest-utils virtualbox-guest-x11"
    return 0
  fi

  if [[ -n "${DISPLAY:-}${WAYLAND_DISPLAY:-}" ]]; then
    echo "Starting current-session clipboard/display helpers where supported..."
    start_vboxclient clipboard
    help_output="$(VBoxClient --help 2>&1 || true)"
    if grep -q -- '--vmsvga' <<<"$help_output"; then
      start_vboxclient vmsvga
      if grep -q -- '--vmsvga-session' <<<"$help_output"; then
        start_vboxclient vmsvga-session
      fi
    elif grep -q -- '--display' <<<"$help_output"; then
      start_vboxclient display
    else
      echo "  No supported VBoxClient display option detected; package autostart/reboot may be needed."
    fi
  else
    echo "No graphical-session variables found; log in to the Parrot desktop before testing clipboard."
  fi

  cat <<'VBOXNOTE'

IMPORTANT: Also enable these options in the VirtualBox window on the HOST:
  Devices > Shared Clipboard > Bidirectional
  View > Auto-resize Guest Display
If Shared Clipboard is unavailable, power off the VM and check:
  VM Settings > General > Advanced > Shared Clipboard > Bidirectional
Reboot Parrot after installing Guest Additions. In a Linux terminal, paste with
Ctrl+Shift+V or right-click > Paste (Ctrl+V usually does not paste in terminals).
VBOXNOTE
  return 0
}

restore_file() {
  local name="$1" backup_dir="$2" target="$CONFIG_HOME/$1"
  if [[ -f "$backup_dir/$name.absent" ]]; then
    rm -f -- "$target"
  elif [[ -f "$backup_dir/$name" ]]; then
    mkdir -p -- "$(dirname -- "$target")"
    cp -a -- "$backup_dir/$name" "$target"
  fi
}

restore_gsetting() {
  local schema="$1" key="$2" file="$3"
  if [[ -f "$file" ]] && command -v gsettings >/dev/null 2>&1; then
    gsettings set "$schema" "$key" "$(cat -- "$file")"
  fi
}

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
  usage
  exit 0
fi

if [[ "${1:-}" == "--restore" ]]; then
  BACKUP_DIR="${2:-}"
  if [[ -z "$BACKUP_DIR" || ! -d "$BACKUP_DIR" || ! -f "$BACKUP_DIR/desktop" ]]; then
    echo "ERROR: supply a valid backup directory created by this script." >&2
    usage >&2
    exit 2
  fi
  DESKTOP="$(cat -- "$BACKUP_DIR/desktop")"
  case "$DESKTOP" in
    KDE)
      restore_file kdeglobals "$BACKUP_DIR"
      restore_file kwinrc "$BACKUP_DIR"
      reload_kde
      ;;
    MATE)
      restore_gsetting org.mate.interface enable-animations "$BACKUP_DIR/mate-interface-animations.value"
      restore_gsetting org.mate.Marco.general compositing-manager "$BACKUP_DIR/marco-compositing.value"
      ;;
    XFCE)
      if [[ -f "$BACKUP_DIR/xfce-compositing.absent" ]]; then
        xfconf-query -c xfwm4 -p /general/use_compositing -r >/dev/null 2>&1 || true
      elif [[ -f "$BACKUP_DIR/xfce-compositing.value" ]]; then
        xfconf-query -c xfwm4 -p /general/use_compositing -s "$(cat -- "$BACKUP_DIR/xfce-compositing.value")"
      fi
      ;;
    GNOME)
      restore_gsetting org.gnome.desktop.interface enable-animations "$BACKUP_DIR/gnome-animations.value"
      ;;
    *)
      echo "ERROR: unknown desktop environment recorded in backup: $DESKTOP" >&2
      exit 2
      ;;
  esac
  echo "Restored saved settings from: $BACKUP_DIR"
  echo "Log out and back in if any visual change does not appear immediately."
  exit 0
fi

# Detect the desktop session currently in use, not merely installed packages.
SESSION_HINT="${XDG_CURRENT_DESKTOP:-} ${XDG_SESSION_DESKTOP:-} ${DESKTOP_SESSION:-}"
shopt -s nocasematch
if [[ "$SESSION_HINT" == *KDE* || "$SESSION_HINT" == *PLASMA* ]]; then
  DESKTOP="KDE"
elif [[ "$SESSION_HINT" == *MATE* ]]; then
  DESKTOP="MATE"
elif [[ "$SESSION_HINT" == *XFCE* ]]; then
  DESKTOP="XFCE"
elif [[ "$SESSION_HINT" == *GNOME* ]]; then
  DESKTOP="GNOME"
else
  echo "ERROR: couldn't identify your active desktop environment." >&2
  echo 'Run: echo "$XDG_CURRENT_DESKTOP / $DESKTOP_SESSION"' >&2
  echo "This script supports KDE Plasma, MATE, XFCE, and GNOME." >&2
  exit 1
fi
shopt -u nocasematch

STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP_DIR="$CONFIG_HOME/desktop-effects-backup-$STAMP"
mkdir -p -- "$BACKUP_DIR"
printf '%s\n' "$DESKTOP" > "$BACKUP_DIR/desktop"

save_file() {
  local name="$1" source="$CONFIG_HOME/$1"
  if [[ -f "$source" ]]; then
    cp -a -- "$source" "$BACKUP_DIR/$name"
  else
    : > "$BACKUP_DIR/$name.absent"
  fi
}

save_gsetting() {
  local schema="$1" key="$2" filename="$3"
  if command -v gsettings >/dev/null 2>&1 && gsettings get "$schema" "$key" >"$BACKUP_DIR/$filename.value" 2>/dev/null; then
    return 0
  fi
  rm -f -- "$BACKUP_DIR/$filename.value"
  echo "NOTE: $schema $key isn't available here; skipping it."
}

echo "Active desktop: $DESKTOP"
echo "Saving settings to: $BACKUP_DIR"

case "$DESKTOP" in
  KDE)
    if command -v kwriteconfig6 >/dev/null 2>&1; then
      KWRITE="kwriteconfig6"
    elif command -v kwriteconfig5 >/dev/null 2>&1; then
      KWRITE="kwriteconfig5"
    else
      echo "ERROR: kwriteconfig6/kwriteconfig5 not found; no settings changed." >&2
      exit 1
    fi
    save_file kdeglobals
    save_file kwinrc
    "$KWRITE" --file kdeglobals --group KDE --key AnimationDurationFactor 0
    # Disable selected decorative effects; Plasma's compositor remains enabled.
    for effect in blurEnabled contrastEnabled translucencyEnabled wobblywindowsEnabled magiclampEnabled; do
      "$KWRITE" --file kwinrc --group Plugins --key "$effect" false
    done
    reload_kde
    echo "Disabled/shortened Plasma animations and selected blur/transparency/window effects."
    echo "The compositor was left enabled to avoid breaking normal Wayland desktop rendering."
    ;;
  MATE)
    command -v gsettings >/dev/null 2>&1 || { echo "ERROR: gsettings not found; no settings changed." >&2; exit 1; }
    save_gsetting org.mate.interface enable-animations mate-interface-animations
    save_gsetting org.mate.Marco.general compositing-manager marco-compositing
    if [[ -f "$BACKUP_DIR/mate-interface-animations.value" ]]; then
      gsettings set org.mate.interface enable-animations false
    fi
    if [[ -f "$BACKUP_DIR/marco-compositing.value" ]]; then
      gsettings set org.mate.Marco.general compositing-manager false
    fi
    echo "Disabled MATE interface animations and, when available, Marco compositing."
    ;;
  XFCE)
    command -v xfconf-query >/dev/null 2>&1 || { echo "ERROR: xfconf-query not found; no settings changed." >&2; exit 1; }
    if xfconf-query -c xfwm4 -p /general/use_compositing >"$BACKUP_DIR/xfce-compositing.value" 2>/dev/null; then
      :
    else
      rm -f -- "$BACKUP_DIR/xfce-compositing.value"
      : > "$BACKUP_DIR/xfce-compositing.absent"
    fi
    if [[ -f "$BACKUP_DIR/xfce-compositing.value" ]]; then
      xfconf-query -c xfwm4 -p /general/use_compositing -s false
    else
      xfconf-query -c xfwm4 -p /general/use_compositing -n -t bool -s false
    fi
    echo "Disabled XFCE window compositing (shadows/transparency may disappear; tearing may occur on some graphics hardware)."
    ;;
  GNOME)
    command -v gsettings >/dev/null 2>&1 || { echo "ERROR: gsettings not found; no settings changed." >&2; exit 1; }
    save_gsetting org.gnome.desktop.interface enable-animations gnome-animations
    if [[ -f "$BACKUP_DIR/gnome-animations.value" ]]; then
      gsettings set org.gnome.desktop.interface enable-animations false
    fi
    echo "Disabled GNOME interface animations."
    ;;
esac

# Repair VirtualBox integration only when this OS is detected as a VirtualBox guest.
fix_virtualbox_integration

cat <<EOF

Finished. No desktop environment was removed. Guest Additions installation, if selected,
was the only package change offered by this script.
Backup: $BACKUP_DIR
To undo these changes, run:
  "$0" --restore "$BACKUP_DIR"
Log out and back in if some effects remain visible.
EOF
