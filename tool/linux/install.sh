#!/bin/sh
# Установка Nexus для текущего пользователя (без прав администратора):
# программа — в ~/.local/share/nexus-app, ярлык в меню приложений
# и обработчик ссылок nexus:// Nexus создаёт сам при первом запуске.
set -e
SRC=$(cd "$(dirname "$0")" && pwd)
DEST="${XDG_DATA_HOME:-$HOME/.local/share}/nexus-app"
if [ "$SRC" != "$DEST" ]; then
  mkdir -p "$DEST"
  cp -a "$SRC/." "$DEST/"
fi
chmod 755 "$DEST/nexus" "$DEST/nexus-core"
mkdir -p "$HOME/.local/bin"
ln -sf "$DEST/nexus" "$HOME/.local/bin/nexus"
echo "Nexus установлен в $DEST"
for lib in libgtk-3.so.0 libayatana-appindicator3.so.1; do
  if ! ldconfig -p 2>/dev/null | grep -q "$lib"; then
    echo "Нужна библиотека $lib — установите её пакетным менеджером"
    echo "  (Ubuntu/Debian: sudo apt install libgtk-3-0 libayatana-appindicator3-1)"
  fi
done
nohup "$DEST/nexus" >/dev/null 2>&1 &
