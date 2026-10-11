#!/bin/bash
# macOS Bash 3.2 compatible

set -u

DIR="$(cd "$(dirname "$0")" && pwd)"
ADB="${ADB:-/opt/homebrew/bin/adb}"
LOG="$DIR/debloat-$(date +%Y%m%d-%H%M%S).log"

if [ ! -x "$ADB" ]; then
  echo "ADB not found or not executable: $ADB" >&2
  echo "Set ADB=/path/to/adb and rerun." >&2
  exit 1
fi

for name in \
  FULL_DEBLOAT_PACKAGES \
  SAMSUNG_ONLY_PACKAGES \
  GOOGLE_ONLY_PACKAGES \
  CARRIER_ONLY_PACKAGES \
  RESTORE_ALL_PACKAGES
do
  if [ ! -f "$DIR/$name" ]; then
    echo "Missing package list: $DIR/$name" >&2
    exit 1
  fi
done

"$ADB" start-server </dev/null >/dev/null

device_count=0
serial=""

while IFS= read -r line; do
  case "$line" in
    ""|List\ of\ devices\ attached*) continue ;;
  esac

  id="${line%%[[:space:]]*}"
  rest="${line#"$id"}"
  state="$(printf '%s\n' "$rest" | awk '{print $1}')"

  if [ "$state" = "device" ]; then
    serial="$id"
    device_count=$((device_count + 1))
  fi
done <<EOF
$("$ADB" devices </dev/null)
EOF

if [ "$device_count" -ne 1 ]; then
  echo "Expected exactly one authorized ADB device; found $device_count."
  "$ADB" devices </dev/null
  echo "Unlock the phone, enable USB debugging, and approve the prompt."
  exit 1
fi

manufacturer="$("$ADB" -s "$serial" shell getprop ro.product.manufacturer </dev/null | tr -d '\r')"
model="$("$ADB" -s "$serial" shell getprop ro.product.model </dev/null | tr -d '\r')"
printf 'Connected device: %s %s (%s)\n' "$manufacturer" "$model" "$serial"

case "$manufacturer" in
  *[Ss][Aa][Mm][Ss][Uu][Nn][Gg]*) ;;
  *)
    echo "Device did not identify itself as Samsung; stopping."
    exit 1
    ;;
esac

echo
echo "1) Full debloat"
echo "2) Samsung-only"
echo "3) Google-only"
echo "4) Carrier-only"
echo "5) Restore listed packages"
printf "Choose 1-5: "
IFS= read -r choice

case "$choice" in
  1) list="$DIR/FULL_DEBLOAT_PACKAGES"; mode="Full debloat"; action="remove" ;;
  2) list="$DIR/SAMSUNG_ONLY_PACKAGES"; mode="Samsung-only debloat"; action="remove" ;;
  3) list="$DIR/GOOGLE_ONLY_PACKAGES"; mode="Google-only debloat"; action="remove" ;;
  4) list="$DIR/CARRIER_ONLY_PACKAGES"; mode="Carrier-only debloat"; action="remove" ;;
  5) list="$DIR/RESTORE_ALL_PACKAGES"; mode="Restore listed packages"; action="restore" ;;
  *) echo "Invalid choice."; exit 1 ;;
esac

package_count="$(awk '
  /^[[:space:]]*#/ || /^[[:space:]]*$/ { next }
  { count++ }
  END { print count+0 }
' "$list")"

echo
echo "$mode: $package_count package entries."
echo "Using local list: $list"
echo "Log: $LOG"
echo
cat "$list"
echo
printf "Type YES to proceed: "
IFS= read -r confirm
[ "$confirm" = "YES" ] || { echo "Cancelled."; exit 0; }

attempted=0
changed=0
already_absent=0
failed=0

while IFS= read -r package || [ -n "$package" ]; do
  package="${package%%#*}"
  package="$(printf '%s' "$package" | tr -d '[:space:]')"
  [ -n "$package" ] || continue

  attempted=$((attempted + 1))

  if [ "$action" = "remove" ]; then
    printf 'Uninstalling for user 0: %s ... ' "$package"
    output="$("$ADB" -s "$serial" shell pm uninstall --user 0 "$package" </dev/null 2>&1)"
    status=$?

    if [ "$status" -eq 0 ] && printf '%s' "$output" | grep -q 'Success'; then
      echo "removed"
      changed=$((changed + 1))
      printf 'REMOVED\t%s\n' "$package" >> "$LOG"
    elif printf '%s' "$output" | grep -qi 'not installed for 0'; then
      echo "already absent for user 0"
      already_absent=$((already_absent + 1))
      printf 'ABSENT\t%s\n' "$package" >> "$LOG"
    else
      echo "FAILED: $output"
      failed=$((failed + 1))
      printf 'FAILED\t%s\t%s\n' "$package" "$output" >> "$LOG"
    fi
  else
    printf 'Restoring: %s ... ' "$package"
    output="$("$ADB" -s "$serial" shell cmd package install-existing --user 0 "$package" </dev/null 2>&1)"
    status=$?

    if [ "$status" -eq 0 ] && printf '%s' "$output" | grep -qi 'installed'; then
      echo "restored"
      changed=$((changed + 1))
      printf 'RESTORED\t%s\n' "$package" >> "$LOG"
    else
      echo "FAILED: $output"
      failed=$((failed + 1))
      printf 'FAILED\t%s\t%s\n' "$package" "$output" >> "$LOG"
    fi
  fi
done < "$list"

echo
echo "Finished: attempted=$attempted, changed/restored=$changed, already absent=$already_absent, failed=$failed"
echo "Results logged to: $LOG"
