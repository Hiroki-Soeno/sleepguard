#!/bin/bash
# SleepGuard: pmset の disablesleep 切り替えだけをパスワードなしで許可する。
# root で実行すること（アプリのメニューから実行するか sudo bash install-sudoers.sh）。
set -euo pipefail

if [ "$(id -u)" -ne 0 ]; then
  echo "root で実行してください: sudo bash $0" >&2
  exit 1
fi

TARGET=/etc/sudoers.d/sleepguard
USER_NAME="${SUDO_USER:-$(stat -f %Su /dev/console)}"

case "$USER_NAME" in
  ""|root) echo "対象ユーザーを特定できませんでした" >&2; exit 1 ;;
esac

TMP="$(mktemp /tmp/sleepguard-sudoers.XXXXXX)"
trap 'rm -f "$TMP"' EXIT

cat > "$TMP" <<SUDOERS
# SleepGuard — clamshell sleep toggle (https://qiita.com/shge/items/ae2f725be8009f786122)
$USER_NAME ALL=(root) NOPASSWD: /usr/bin/pmset -a disablesleep 1, /usr/bin/pmset -a disablesleep 0
SUDOERS

# 構文チェックを通ったものだけ設置する（壊すと sudo 全体が死ぬので必須）
/usr/sbin/visudo -cf "$TMP"

/usr/bin/install -m 0440 -o root -g wheel "$TMP" "$TARGET"
echo "installed: $TARGET ($USER_NAME)"
