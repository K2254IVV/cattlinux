#!/bin/bash

# Проверка на root
if [ "$(id -u)" -ne 0 ]; then
    echo "✖ Ошибка: Скрипт требует прав root. Запустите через sudo!" >&2
    exit 1
fi

# Установка пакетов (если их нет)
echo "⌛ Установка необходимых пакетов..."
pacman -Sy --noconfirm curl imagemagick

# Скачивание и замена /etc/os-release
echo "⌛ Обновление /etc/os-release..."
curl -o /etc/os-release https://raw.githubusercontent.com/K2254IVV/cattlinux/main/files/os-release --fail || {
    echo "✖ Ошибка загрузки os-release!" >&2
    exit 1
}

# Скачивание обоев
echo "⌛ Загрузка обоев..."
mkdir -p /usr/share/backgrounds
curl -o /usr/share/backgrounds/wallpaper1.png https://raw.githubusercontent.com/K2254IVV/cattlinux/main/files/wallpapers/wallpaper1.png --fail || echo "⚠ Не удалось загрузить wallpaper1" >&2
curl -o /usr/share/backgrounds/wallpaper2.png https://raw.githubusercontent.com/K2254IVV/cattlinux/main/files/wallpapers/wallpaper2.png --fail || echo "⚠ Не удалось загрузить wallpaper2" >&2

# Установка neofetch
echo "⌛ Установка neofetch..."
if ! command -v neofetch &>/dev/null; then
    curl -o /bin/neofetch https://raw.githubusercontent.com/dylanaraps/neofetch/master/neofetch --fail && \
    chmod +x /bin/neofetch || {
        echo "✖ Ошибка установки neofetch!" >&2
        exit 1
    }
else
    echo "ℹ neofetch уже установлен"
fi

# Настройка Weston (для пользователя catt)
echo "⌛ Настройка Weston..."
mkdir -p ~/catt/.config
cat > ~/.config/weston.ini << 'WESTON_EOF'
[core]
shell=desktop-shell.so
xwayland=true

[shell]
background-image=/usr/share/backgrounds/wallpaper1.png
background-type=scale
panel-position=bottom
focus-animation=dim-layer
num-workspaces=6
locking=false
cursor-theme=Adwaita
cursor-size=24

[keyboard]
repeat_delay=300
repeat_rate=20

[launcher]
icon=/usr/share/icons/AdwaitaLegacy/22x22/legacy/applications-development.png
path=/usr/bin/kitty

[launcher]
icon=/usr/share/icons/AdwaitaLegacy/22x22/legacy/web-browser.png
path=/usr/bin/firefox

[launcher]
icon=/usr/share/icons/AdwaitaLegacy/22x22/legacy/accessories-text-editor.png
path=/usr/bin/kate

[launcher]
icon=/usr/share/icons/AdwaitaLegacy/22x22/legacy/accessories-calculator.png
path=/usr/bin/kcalc

[pointer]
acceleration_factor=1.5
WESTON_EOF

# Права на файлы
chown -R catt:catt /home/catt

echo "╔══════════════════════════════════════════════╗"
echo "║          НАСТРОЙКА УСПЕШНО ЗАВЕРШЕНА        ║"
echo "╠══════════════════════════════════════════════╣"
echo "║ Изменения:                                   ║"
echo "║ - Обновлён /etc/os-release                   ║"
echo "║ - Скачаны обои в /usr/share/backgrounds/     ║"
echo "║ - Установлен neofetch                        ║"
echo "║ - Настроен Weston (~/.config/weston.ini)     ║"
echo "╚══════════════════════════════════════════════╝"
