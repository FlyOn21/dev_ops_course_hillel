#!/bin/bash
timstamp() { date +"%Y%m%d%H%M%S"; }
MACHINE="noble1"
OUTPUT_FILE="./output_data/nspawn_${MACHINE}_$(timstamp).txt"

{
  echo "=== Container Management Log for $MACHINE ==="
  echo ""

  echo "--- machinectl status ---"
  sudo machinectl status "${MACHINE}" 2>&1

  echo ""
  echo "--- systemd-nspawn service status ---"
  systemctl status "${MACHINE}.service" 2>&1

  echo ""
  echo "--- systemctl cat service ---"
  systemctl cat "${MACHINE}.service" 2>&1

  echo ""
  echo "--- machinectl list ---"
  machinectl list 2>&1

} | tee "$OUTPUT_FILE"

echo ""
echo "Output saved to: $OUTPUT_FILE"

