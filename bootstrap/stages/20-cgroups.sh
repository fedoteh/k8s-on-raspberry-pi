#!/usr/bin/env bash
set -euo pipefail

FILE="/boot/firmware/cmdline.txt"
NEEDLES=("cgroup_enable=cpuset" "cgroup_enable=memory" "cgroup_memory=1")

line="$(cat "$FILE")"
changed=0

for n in "${NEEDLES[@]}"; do
  if ! grep -qF "$n" <<<"$line"; then
    line="$line $n"
    changed=1
  fi
done

if [[ $changed -eq 1 ]]; then
  echo "$line" > "$FILE"
  echo "Updated $FILE. Reboot required."
else
  echo "No change needed."
fi
