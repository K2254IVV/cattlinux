#!/bin/bash

# Проверка на root
if [ "$(id -u)" -ne 0 ]; then
    echo "✖ Ошибка: Скрипт требует прав root. Запустите через sudo!" >&2
    exit 1
fi

# Парсинг аргументов
TARGET_DISK=""
while [[ $# -gt 0 ]]; do
    case $1 in
        --disk)
            TARGET_DISK="$2"
            shift 2
            ;;
        *)
            echo "✖ Неизвестный аргумент: $1" >&2
            exit 1
            ;;
    esac
done

# Проверка диска
if [ -z "$TARGET_DISK" ]; then
    echo "ℹ Использование: $0 --disk /dev/sdX"
    echo "Доступные диски:"
    lsblk -d -o NAME,SIZE,MODEL | grep -v "NAME"
    exit 1
fi

if [ ! -b "$TARGET_DISK" ]; then
    echo "✖ Ошибка: $TARGET_DISK не существует или не блочное устройство!" >&2
    exit 1
fi

# Проверка что это не текущий загрузочный диск
if findmnt -n -o SOURCE -T / | grep -q "^$TARGET_DISK"; then
    echo "✖ Критическая ошибка: $TARGET_DISK содержит текущую систему!" >&2
    exit 1
fi

# Подтверждение
echo "╔══════════════════════════════════════════════╗"
echo "║           ВНИМАНИЕ: ОПАСНАЯ ОПЕРАЦИЯ        ║"
echo "╠══════════════════════════════════════════════╣"
echo "║ Будет полностью уничтожен диск: $TARGET_DISK"
lsblk "$TARGET_DISK"
echo "╚══════════════════════════════════════════════╝"

read -p "⚠ Подтвердите форматирование (введите 'CATT' для продолжения): " confirm
if [[ "${confirm}" != "CATT" ]]; then
    echo "Отмена установки"
    exit 0
fi

# Функция очистки при ошибках
cleanup() {
    echo "⌛ Очистка..."
    umount -R /mnt 2>/dev/null
    swapoff "${TARGET_DISK}*" 2>/dev/null
}

# Ловим прерывания
trap cleanup EXIT INT TERM

# Разметка диска
echo "⌛ Создание разделов..."
wipefs -a "$TARGET_DISK" || { echo "✖ Ошибка wipefs"; exit 1; }
parted -s "$TARGET_DISK" mklabel gpt || { echo "✖ Ошибка mklabel"; exit 1; }
parted -s "$TARGET_DISK" mkpart primary fat32 1MiB 513MiB || { echo "✖ Ошибка EFI раздела"; exit 1; }
parted -s "$TARGET_DISK" set 1 esp on || { echo "✖ Ошибка ESP флага"; exit 1; }
parted -s "$TARGET_DISK" mkpart primary ext4 513MiB 100% || { echo "✖ Ошибка корневого раздела"; exit 1; }

# Форматирование
echo "⌛ Форматирование..."
mkfs.fat -F32 "${TARGET_DISK}1" || { echo "✖ Ошибка форматирования EFI"; exit 1; }
mkfs.ext4 -F "${TARGET_DISK}2" || { echo "✖ Ошибка форматирования root"; exit 1; }

# Монтирование
echo "⌛ Монтирование..."
mount "${TARGET_DISK}2" /mnt || { echo "✖ Ошибка монтирования root"; exit 1; }
mkdir -p /mnt/boot/efi || { echo "✖ Ошибка создания /boot/efi"; exit 1; }
mount "${TARGET_DISK}1" /mnt/boot/efi || { echo "✖ Ошибка монтирования EFI"; exit 1; }

# Установка базовой системы
echo "⌛ Установка базовых пакетов..."
pacman -Sy archlinux-keyring --noconfirm || { echo "✖ Ошибка обновления ключей"; exit 1; }
pacstrap /mnt base base-devel linux linux-firmware || { echo "✖ Ошибка pacstrap"; exit 1; }

# Настройка системы
echo "⌛ Настройка системы..."
genfstab -U /mnt >> /mnt/etc/fstab || { echo "✖ Ошибка fstab"; exit 1; }

# Chroot установка
echo "⌛ Установка в chroot..."
cat << 'CHROOT_EOF' | arch-chroot /mnt bash || { echo "✖ Ошибка chroot"; exit 1; }
# Внутри chroot
set -e

# Настройка времени
ln -sf /usr/share/zoneinfo/Europe/Moscow /etc/localtime
hwclock --systohc

# Локали
echo "en_US.UTF-8 UTF-8" >> /etc/locale.gen
echo "ru_RU.UTF-8 UTF-8" >> /etc/locale.gen
locale-gen
echo "LANG=en_US.UTF-8" > /etc/locale.conf

# Имя хоста
echo "cattlinux" > /etc/hostname

# Пользователь
useradd -m -G wheel -s /bin/bash catt
echo "Установите пароль для пользователя catt:"
passwd catt

# Sudo
echo "%wheel ALL=(ALL) ALL" >> /etc/sudoers

# Обновление ключей
pacman-key --init
pacman-key --populate archlinux

# Установка пакетов
pacman -Sy --noconfirm \
    coreutils nano systemd dhcpcd iproute2 iwd networkmanager \
    grub efibootmgr lightdm weston xwayland \
    kitty firefox kate kcalc \
    adwaita-icon-theme adwaita-legacy-icon-theme \
    imagemagick bash-completion

# Установка neofetch
curl -o /bin/neofetch https://raw.githubusercontent.com/dylanaraps/neofetch/master/neofetch
chmod +x /bin/neofetch

# Получение конфигов
mkdir -p /usr/share/backgrounds
curl -o /usr/share/backgrounds/wallpaper1.png https://raw.githubusercontent.com/K2254IVV/cattlinux/main/files/wallpapers/wallpaper1.png
curl -o /usr/share/backgrounds/wallpaper2.png https://raw.githubusercontent.com/K2254IVV/cattlinux/main/files/wallpapers/wallpaper2.png
curl -o /etc/os-release https://raw.githubusercontent.com/K2254IVV/cattlinux/main/files/os-release

# GRUB
grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=CattLinux
grub-mkconfig -o /boot/grub/grub.cfg

# Сервисы
systemctl enable lightdm
systemctl enable NetworkManager

# Weston config
mkdir -p /home/catt/.config
cat > /home/catt/.config/weston.ini << 'WESTON_EOF'
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

chown -R catt:catt /home/catt
CHROOT_EOF

# Завершение
echo "╔══════════════════════════════════════════════╗"
echo "║          УСТАНОВКА УСПЕШНО ЗАВЕРШЕНА        ║"
echo "╠══════════════════════════════════════════════╣"
echo "║ Для входа используйте:                       ║"
echo "║ Логин: catt                                  ║"
echo "║ Пароль: который вы установили               ║"
echo "║                                              ║"
echo "║ Перезагрузитесь командой: systemctl reboot   ║"
echo "╚══════════════════════════════════════════════╝"
