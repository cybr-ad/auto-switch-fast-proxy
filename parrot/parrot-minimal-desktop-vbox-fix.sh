#!/usr/bin/env bash
# Reduce visual effects and repair common VirtualBox Guest Additions issues on Parrot OS.
# Does not remove desktop environments or security tools. No sudo needed unless repairing packages.
set -Eeuo pipefail
CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"

usage() {
  cat <<'EOF'
Usage:
  ./parrot-minimal-desktop-vbox-fix.sh
  ./parrot-minimal-desktop-vbox-fix.sh --restore /path/to/backup-folder

The script backs up affected desktop settings. On a VirtualBox guest, it can
reinstall Parrot's Guest Additions packages after asking first.
EOF
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
  if [[ "$info" =~ [Vv]irtual[Bb]ox || "$info" =~ [Ii]nnotek ]]; then return 0; fi
  if command -v systemd-detect-virt >/dev/null 2>&1; then
    virt="$(systemd-detect-virt --vm 2>/dev/null || true)"
    [[ "$virt" == "oracle" || "$virt" == "virtualbox" ]] && return 0
  fi
  return 1
}

save_file() {
  local name="$1" source="$CONFIG_HOME/$1"
  if [[ -f "$source" ]]; then cp -a -- "$source" "$BACKUP_DIR/$name"
  else : > "$BACKUP_DIR/$name.absent"
  fi
}

save_gsetting() {
  local schema="$1" key="$2" filename="$3"
  if command -v gsettings >/dev/null 2>&1 && gsettings get "$schema" "$key" >"$BACKUP_DIR/$filename.value" 2>/dev/null; then
    return 0
  fi
  rm -f -- "$BACKUP_DIR/$filename.value"
  echo "NOTE: $schema $key isn't available; skipping it."
}

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then usage; exit 0; fi

if [[ "${1:-}" == "--restore" ]]; then
  BACKUP_DIR="${2:-}"
  if [[ -z "$BACKUP_DIR" || ! -d "$BACKUP_DIR" || ! -f "$BACKUP_DIR/desktop" ]]; then
    echo "ERROR: supply a valid backup folder created by this script." >&2
    usage >&2; exit 2
  fi
  DESKTOP="$(cat -- "$BACKUP_DIR/desktop")"
  case "$DESKTOP" in
    KDE) restore_file kdeglobals "$BACKUP_DIR"; restore_file kwinrc "$BACKUP_DIR"; reload_kde ;;
    MATE) restore_gsetting org.mate.interface enable-animations "$BACKUP_DIR/mate-animations.value" ;;
    GNOME) restore_gsetting org.gnome.desktop.interface enable-animations "$BACKUP_DIR/gnome-animations.value" ;;
    XFCE)
      if command -v xfconf-query >/dev/null 2>&1; then
        if [[ -f "$BACKUP_DIR/xfce-compositing.absent" ]]; then
          xfconf-query -c xfwm4 -p /general/use_compositing -r >/dev/null 2>&1 || true
        elif [[ -f "$BACKUP_DIR/xfce-compositing.value" ]]; then
          xfconf-query -c xfwm4 -p /general/use_compositing -s "$(cat -- "$BACKUP_DIR/xfce-compositing.value")"
        fi
      fi
      ;;
    *) echo "ERROR: Unknown desktop in backup: $DESKTOP" >&2; exit 2 ;;
  esac
  echo "Desktop settings restored from: $BACKUP_DIR"
  echo "Package changes (if any) are not undone by restore."
  exit 0
fi

SESSION_HINT="${XDG_CURRENT_DESKTOP:-} ${XDG_SESSION_DESKTOP:-} ${DESKTOP_SESSION:-}"
shopt -s nocasematch
if [[ "$SESSION_HINT" == *KDE* || "$SESSION_HINT" == *PLASMA* ]]; then DESKTOP="KDE"
elif [[ "$SESSION_HINT" == *MATE* ]]; then DESKTOP="MATE"
elif [[ "$SESSION_HINT" == *XFCE* ]]; then DESKTOP="XFCE"
elif [[ "$SESSION_HINT" == *GNOME* ]]; then DESKTOP="GNOME"
else
  shopt -u nocasematch
  echo "ERROR: could not identify the desktop session: $SESSION_HINT" >&2
  echo "This script supports KDE Plasma, MATE, XFCE, and GNOME." >&2
  exit 1
fi
shopt -u nocasematch

STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP_DIR="$CONFIG_HOME/parrot-desktop-vbox-backup-$STAMP"
mkdir -p -- "$BACKUP_DIR"
printf '%s\n' "$DESKTOP" > "$BACKUP_DIR/desktop"
echo "Desktop detected: $DESKTOP"
echo "Backups: $BACKUP_DIR"

case "$DESKTOP" in
  KDE)
    if command -v kwriteconfig6 >/dev/null 2>&1; then KWRITE="kwriteconfig6"
    elif command -v kwriteconfig5 >/dev/null 2>&1; then KWRITE="kwriteconfig5"
    else echo "ERROR: kwriteconfig6/5 is missing; no KDE settings changed." >&2; exit 1
    fi
    save_file kdeglobals
    save_file kwinrc
    "$KWRITE" --file kdeglobals --group KDE --key AnimationDurationFactor 0
    for effect in blurEnabled contrastEnabled translucencyEnabled wobblywindowsEnabled magiclampEnabled; do
      "$KWRITE" --file kwinrc --group Plugins --key "$effect" false
    done
    reload_kde
    echo "KDE animations and selected visual effects reduced; compositor remains enabled."
    ;;
  MATE)
    save_gsetting org.mate.interface enable-animations mate-animations
    if [[ -f "$BACKUP_DIR/mate-animations.value" ]]; then
      gsettings set org.mate.interface enable-animations false
    fi
    echo "MATE interface animations disabled where supported."
    ;;
  XFCE)
    if ! command -v xfconf-query >/dev/null 2>&1; then echo "ERROR: xfconf-query is missing." >&2; exit 1; fi
    if xfconf-query -c xfwm4 -p /general/use_compositing >"$BACKUP_DIR/xfce-compositing.value" 2>/dev/null; then :
    else rm -f -- "$BACKUP_DIR/xfce-compositing.value"; : > "$BACKUP_DIR/xfce-compositing.absent"; fi
    # Disable decorative compositing but don't alter window borders or remove xfwm4.
    xfconf-query -c xfwm4 -p /general/use_compositing -s false 2>/dev/null || \
      xfconf-query -c xfwm4 -p /general/use_compositing -n -t bool -s false
    echo "XFCE compositing effects disabled. Restore from the backup if you see tearing."
    ;;
  GNOME)
    save_gsetting org.gnome.desktop.interface enable-animations gnome-animations
    if [[ -f "$BACKUP_DIR/gnome-animations.value" ]]; then
      gsettings set org.gnome.desktop.interface enable-animations false
    fi
    echo "GNOME interface animations disabled where supported."
    ;;
esac

if is_virtualbox_guest; then
  echo
  echo "VirtualBox guest detected. Guest Additions provide dynamic screen resizing and clipboard integration."
  missing=0
  for package in virtualbox-guest-utils virtualbox-guest-x11; do
    status="$(dpkg-query -W -f='${Status}' "$package" 2>/dev/null || true)"
    [[ "$status" == "install ok installed" ]] || missing=1
  done
  if (( missing )); then
    echo "One or more Guest Additions packages are missing; repair is recommended."
  else
    echo "Guest Additions packages appear installed, but graphics errors were reported."
  fi
  read -r -p "Install/reinstall virtualbox-guest-utils and virtualbox-guest-x11 now? [y/N] " answer
  case "$answer" in
    y|Y|yes|YES)
      if sudo apt-get update && sudo apt-get install --reinstall -y virtualbox-guest-utils virtualbox-guest-x11; then
        echo "Guest Additions repaired/reinstalled. Reboot Parrot after the script finishes."
      else
        echo "WARNING: Guest Additions repair failed. Read the package-manager errors above." >&2
      fi
      ;;
    *) echo "Skipped Guest Additions package repair; resizing may still not work." ;;
  esac
  if command -v VBoxClient >/dev/null 2>&1 && [[ -n "${DISPLAY:-}${WAYLAND_DISPLAY:-}" ]]; then
    if ! pgrep -u "$(id -u)" -f '[V]BoxClient.*--clipboard' >/dev/null 2>&1; then
      nohup VBoxClient --clipboard >/dev/null 2>&1 &
      echo "Requested start of the VirtualBox clipboard helper for this session."
    else
      echo "VirtualBox clipboard helper appears to be running."
    fi
  fi
else
  echo "No VirtualBox guest detected; skipping Guest Additions package actions."
fi

cat <<EOF

Finished. This script cannot change settings in the Windows-host VirtualBox application.
On the Windows host, with the VM running, check:
  Devices > Shared Clipboard > Bidirectional
  View > Auto-resize Guest Display (enabled/checked)

For your current graphics warnings, keep 3D Acceleration disabled while testing.
Power off the VM before changing its Graphics Controller. Since VMSVGA triggered a
vmwgfx unsupported-hypervisor warning, keep VBoxSVGA selected for this test.
After Guest Additions repair, reboot Parrot and test resizing the VirtualBox window.

To restore backed-up desktop settings only:
  "$0" --restore "$BACKUP_DIR"
EOF
