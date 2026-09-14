#!/bin/bash
set -euo pipefail
[ "$(id -u)" -eq 0 ] || { echo "root で実行してください: sudo bash $0" >&2; exit 1; }
rm -f /etc/sudoers.d/sleepguard
echo "removed: /etc/sudoers.d/sleepguard"
