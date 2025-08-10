#!/bin/bash

# Проверка на root
if [ "$(id -u)" -ne 0 ]; then
    echo "Этот скрипт должен запускаться с правами root" >&2
    exit 1
fi

# Парсинг аргументов
while [[ $# -gt 0 ]]; do
    case $1 in
        --disk)
            TARGET_DISK="$2"
            shift
            shift
            ;;
        *)
            echo "Неизвестный аргумент: $1" >&2
            exit 1
            ;;
    esac
done

if [ -z "$TARGET_DISK" ]; then
    echo "Использование: $0 --disk /dev/sdX" >&2
    exit 1
fi

# Проверка диска
if [ ! -b "$TARGET_DISK" ]; then
    echo "Устройство $TARGET_DISK не найдено или не является блочным устройством" >&2
    exit 1
fi

# Подтверждение
echo "ВНИМАНИЕ: Это приведёт к полному уничтожению данных на $TARGET_DISK!"
read -p "Продолжить установку на $TARGET_DISK? (y/N) " confirm
if [[ "${confirm,,}" != "y" ]]; then
    echo "Отмена установки"
    exit 0
fi

# Функция для обработки ошибок
error_exit() {
    echo "Ошибка: $1" >&2
    exit 1
}

# Разметка диска
echo "Создание разделов на $TARGET_DISK..."
parted -s "$TARGET_DISK" mklabel gpt || error_exit "Не удалось создать таблицу разделов"
parted -s "$TARGET_DISK" mkpart primary fat32 1MiB 513MiB || error_exit "Не удалось создать EFI раздел"
parted -s "$TARGET_DISK" set 1 esp on || error_exit "Не удалось установить флаг ESP"
parted -s "$TARGET_DISK" mkpart primary ext4 513MiB 100% || error_exit "Не удалось создать корневой раздел"

# Форматирование разделов
echo "Форматирование разделов..."
mkfs.fat -F32 "${TARGET_DISK}1" || error_exit "Не удалось отформатировать EFI раздел"
mkfs.ext4 -F "${TARGET_DISK}2" || error_exit "Не удалось отформатировать корневой раздел"

# Монтирование
echo "Монтирование разделов..."
mount "${TARGET_DISK}2" /mnt || error_exit "Не удалось смонтировать корневой раздел"
mkdir -p /mnt/boot/efi || error_exit "Не удалось создать директорию EFI"
mount "${TARGET_DISK}1" /mnt/boot/efi || error_exit "Не удалось смонтировать EFI раздел"

# Установка базовой системы
echo "Установка базовых пакетов..."
pacstrap /mnt base base-devel linux linux-firmware || error_exit "Не удалось установить базовые пакеты"

# Генерация fstab
echo "Генерация fstab..."
genfstab -U /mnt >> /mnt/etc/fstab || error_exit "Не удалось сгенерировать fstab"

# Установка пакетов
echo "Установка дополнительных пакетов..."
arch-chroot /mnt bash -c '
    pacman -Sy --noconfirm \
        coreutils nano systemd dhcpcd iproute2 iwd networkmanager \
        flatpak bash pacman python3 make gcc curl grub efibootmgr \
        lightdm weston xwayland kitty firefox kate kcalc \
        adwaita-icon-theme adwaita-legacy-icon-theme \
        imagemagick bash-completion \
        || exit 1
' || error_exit "Не удалось установить дополнительные пакеты"

# Установка neofetch
echo "Установка neofetch..."
arch-chroot /mnt bash -c '
    curl -o /bin/neofetch \
    "https://raw.githubusercontent.com/dylanaraps/neofetch/refs/heads/master/neofetch" \
    && chmod +x /bin/neofetch \
    || exit 1
' || error_exit "Не удалось установить neofetch"

# Настройка системы
echo "Настройка системы..."

# Установка os-release
arch-chroot /mnt bash -c '
    curl -o /etc/os-release \
    "https://raw.githubusercontent.com/K2254IVV/cattlinux/refs/heads/main/files/os-release" \
    || exit 1
' || error_exit "Не удалось установить os-release"

# Создание директории для обоев
arch-chroot /mnt bash -c '
    mkdir -p /usr/share/backgrounds || exit 1
' || error_exit "Не удалось создать директорию для обоев"

# Загрузка обоев
echo "Загрузка обоев..."
arch-chroot /mnt bash -c '
    curl -o /usr/share/backgrounds/wallpaper1.png \
    "https://raw.githubusercontent.com/K2254IVV/cattlinux/refs/heads/main/files/wallpapers/wallpaper1.png" \
    || exit 1
    
    curl -o /usr/share/backgrounds/wallpaper2.png \
    "https://raw.githubusercontent.com/K2254IVV/cattlinux/refs/heads/main/files/wallpapers/wallpaper2.png" \
    || exit 1
' || error_exit "Не удалось загрузить обои"

# Создание пользователя
echo "Создание пользователя catt..."
arch-chroot /mnt bash -c '
    useradd -m -G wheel -s /bin/bash catt || exit 1
    echo "Установите пароль для пользователя catt:"
    passwd catt || exit 1
' || error_exit "Не удалось создать пользователя"

# Настройка sudo
echo "Настройка sudo..."
arch-chroot /mnt bash -c '
    echo "%wheel ALL=(ALL) ALL" >> /etc/sudoers || exit 1
' || error_exit "Не удалось настроить sudo"

# Установка GRUB
echo "Установка GRUB..."
arch-chroot /mnt bash -c '
    grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=CattLinux || exit 1
    grub-mkconfig -o /boot/grub/grub.cfg || exit 1
' || error_exit "Не удалось установить GRUB"

# Включение сервисов
echo "Включение сервисов..."
arch-chroot /mnt bash -c '
    systemctl enable lightdm || exit 1
    systemctl enable NetworkManager || exit 1
    systemctl enable getty@tty1 || exit 1
' || error_exit "Не удалось включить сервисы"

# Создание конфига Weston
echo "Создание конфига Weston..."
arch-chroot /mnt bash -c '
    mkdir -p /home/catt/.config || exit 1
    cat > /home/catt/.config/weston.ini << "EOL"
[core]
shell=desktop-shell.so
xwayland=true

[shell]
background-image=/usr/share/backgrounds/wallpaper1.png
background-type=scale
panel-position=bottom
focus-animation=dim-layer
#binding-modifier=ctrl
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
EOL
    chown -R catt:catt /home/catt/.config || exit 1
' || error_exit "Не удалось создать конфиг Weston"

# Создание скрипта для смены обоев
echo "Создание скрипта для смены обоев..."
arch-chroot /mnt bash -c '
    cat > /usr/local/bin/change-wallpaper << "EOL"
#!/usr/bin/env python3

import os
import configparser
from pathlib import Path

WALLPAPERS = [
    "/usr/share/backgrounds/wallpaper1.png",
    "/usr/share/backgrounds/wallpaper2.png"
]

CONFIG_PATH = os.path.expanduser("~/.config/weston.ini")

def change_wallpaper(wallpaper_path):
    config = configparser.ConfigParser()
    config.read(CONFIG_PATH)
    
    if "shell" not in config:
        config["shell"] = {}
    
    config["shell"]["background-image"] = wallpaper_path
    
    with open(CONFIG_PATH, "w") as configfile:
        config.write(configfile)
    
    print(f"Обои изменены на {wallpaper_path}")
    print("Перезапустите Weston для применения изменений")

if __name__ == "__main__":
    print("Доступные обои:")
    for i, wp in enumerate(WALLPAPERS, 1):
        print(f"{i}. {Path(wp).name}")
    
    try:
        choice = int(input("Выберите обои (1-2): "))
        if 1 <= choice <= len(WALLPAPERS):
            change_wallpaper(WALLPAPERS[choice-1])
        else:
            print("Неверный выбор")
    except ValueError:
        print("Введите число")
EOL

    chmod +x /usr/local/bin/change-wallpaper || exit 1
    chown catt:catt /usr/local/bin/change-wallpaper || exit 1
' || error_exit "Не удалось создать скрипт для смены обоев"

echo "Установка завершена успешно!"
echo "Вы можете перезагрузиться в новую систему командой:"
echo "systemctl reboot"
