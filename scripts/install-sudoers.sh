#!/bin/bash
# SleepGuard: pmset の disablesleep 切り替えだけをパスワードなしで許可する。
# root で実行すること（アプリのメニューから実行するか sudo bash install-sudoers.sh [ユーザー名]）。
set -euo pipefail

if [ "$(id -u)" -ne 0 ]; then
  echo "root で実行してください: sudo bash $0" >&2
  exit 1
fi

# 許可する相手は「アプリを使っている本人」＝アプリから明示的に渡される。
# 手動実行時は sudo を叩いた人、それも無ければコンソールのログインユーザー。
USER_NAME="${1:-${SUDO_USER:-$(stat -f %Su /dev/console)}}"

case "$USER_NAME" in
  ""|root) echo "対象ユーザーを特定できませんでした" >&2; exit 1 ;;
esac
if ! /usr/bin/id "$USER_NAME" >/dev/null 2>&1; then
  echo "存在しないユーザーです: $USER_NAME" >&2; exit 1
fi

# sudoers.d はファイル名に '.' を含むものを読み飛ばすので英数字系だけに落とす
SAFE_NAME="$(printf '%s' "$USER_NAME" | tr -c 'A-Za-z0-9_-' '_')"
TARGET="/etc/sudoers.d/sleepguard-$SAFE_NAME"

TMP="$(mktemp /tmp/sleepguard-sudoers.XXXXXX)"
trap 'rm -f "$TMP"' EXIT

cat > "$TMP" <<SUDOERS
# SleepGuard — clamshell sleep toggle (https://github.com/Hiroki-Soeno/sleepguard)
$USER_NAME ALL=(root) NOPASSWD: /usr/bin/pmset -a disablesleep 1, /usr/bin/pmset -a disablesleep 0
SUDOERS

# 構文チェックを通ったものだけ設置する（壊すと sudo 全体が死ぬので必須）
/usr/sbin/visudo -cf "$TMP"

/usr/bin/install -m 0440 -o root -g wheel "$TMP" "$TARGET"
# 旧形式（ユーザー名なしの1ファイル）が残っていたら片付ける
rm -f /etc/sudoers.d/sleepguard
echo "installed: $TARGET ($USER_NAME)"
