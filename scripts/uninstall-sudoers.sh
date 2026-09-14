#!/bin/bash
# SleepGuard: パスワード不要の設定を取り消す。
# root で実行すること（アプリのメニューから実行するか sudo bash uninstall-sudoers.sh [ユーザー名]）。
set -euo pipefail
[ "$(id -u)" -eq 0 ] || { echo "root で実行してください: sudo bash $0" >&2; exit 1; }

USER_NAME="${1:-${SUDO_USER:-$(stat -f %Su /dev/console)}}"
SAFE_NAME="$(printf '%s' "$USER_NAME" | tr -c 'A-Za-z0-9_-' '_')"

rm -f "/etc/sudoers.d/sleepguard-$SAFE_NAME" /etc/sudoers.d/sleepguard
echo "removed: /etc/sudoers.d/sleepguard-$SAFE_NAME"
