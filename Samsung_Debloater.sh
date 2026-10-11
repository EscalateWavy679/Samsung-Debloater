#!/usr/bin/env bash
# caution: this was ported from the windows batch script by vibecoding. completely untested. do not use this ever.
set -euo pipefail

# Put this script beside the repo's *_PACKAGES files.
DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

# Use Homebrew ADB explicitly. Change this if yours is elsewhere.
ADB="${ADB:-/opt/homebrew/bin/adb}"

if [[ ! -x "$ADB" ]]; then
  echo "ADB not found or not executable: $ADB" >&2
  echo 'Set ADB=/path/to/adb and rerun.' >&2
  exit 1
fi

for file in \
  FULL_DEBLOAT_PACKAGES \
  SAMSUNG_ONLY_PACKAGES \
  GOOGLE_ONLY_PACKAGES \
  CARRIER_ONLY_PACKAGES \
  RESTORE_ALL_PACKAGES
do
  if [[ ! -f "$DIR/$file" ]]; then
    echo "Required package-list file missing: $DIR/$file" >&2
    exit 1
  fi
done

"$ADB" start-server >/dev/null

# Require exactly one authorized device.
mapfile -t devices < <("$ADB" devices | awk 'NR > 1 && $2 == "device" {print $1}')
if (( ${#devices[@]} != 1 )); then
  echo "Expected exactly one authorized ADB device; found ${#devices[@]}."
  "$ADB" devices
  echo "Unlock the phone, enable USB debugging, and approve the prompt."
  exit 1
fi
serial="${devices[0]}"

manufacturer="$("$ADB" -s "$serial" shell getprop ro.product.manufacturer | tr -d '\r')"
model="$("$ADB" -s "$serial" shell getprop ro.product.model | tr -d '\r')"

printf 'Connected device: %s %s (%s)\n' "$manufacturer" "$model" "$serial"
if [[ "${manufacturer,,}" != *samsung* ]]; then
  echo "This does not identify itself as Samsung; stopping."
  exit 1
fi

echo
echo "1) Full debloat"
echo "2) Samsung-only"
echo "3) Google-only"
echo "4) Carrier-only"
echo "5) Restore listed packages"
read -r -p "Choose 1–5: " choice

case "$choice" in
  1) list="$DIR/FULL_DEBLOAT_PACKAGES"; mode="Full debloat"; action="remove" ;;
  2) list="$DIR/SAMSUNG_ONLY_PACKAGES"; mode="Samsung-only debloat"; action="remove" ;;
  3) list="$DIR/GOOGLE_ONLY_PACKAGES"; mode="Google-only debloat"; action="remove" ;;
  4) list="$DIR/CARRIER_ONLY_PACKAGES"; mode="Carrier-only debloat"; action="remove" ;;
  5) list="$DIR/RESTORE_ALL_PACKAGES"; mode="Restore listed packages"; action="restore" ;;
  *) echo "Invalid choice."; exit 1 ;;
esac

echo
echo "$mode will affect packages listed in:"
echo "$list"
read -r -p "Type YES to continue: " confirm
[[ "$confirm" == "YES" ]] || { echo "Cancelled."; exit 0; }

while IFS= read -r package || [[ -n "$package" ]]; do
  # Ignore blank lines and comments.
  package="${package%%#*}"
  package="${package//[[:space:]]/}"
  [[ -n "$package" ]] || continue

  if [[ "$action" == "remove" ]]; then
    printf 'Uninstalling for user 0: %s ... ' "$package"
    if "$ADB" -s "$serial" shell pm uninstall --user 0 "$package"; then
      echo "done"
    else
      echo "failed"
    fi
  else
    printf 'Restoring: %s ... ' "$package"
    if "$ADB" -s "$serial" shell cmd package install-existing --user 0 "$package"; then
      echo "done"
    else
      echo "failed"
    fi
  fi
done < "$list"

echo "Finished. Reboot the phone and check the features you use."
