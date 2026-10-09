# Omarchy на гибридном ноутбуке (Intel iGPU + NVIDIA)

Фикс запуска Omarchy/Hyprland, когда система стартует **только** с параметром
`modprobe.blacklist=nvidia_drm`, введённым вручную в меню Limine.

## Проблема

На гибридном ноутбуке (Intel Alder Lake-P iGPU + NVIDIA RTX 4050):

- Omarchy при установке пишет `/etc/mkinitcpio.conf.d/nvidia.conf`:
  ```
  MODULES+=(nvidia nvidia_modeset nvidia_uvm nvidia_drm)
  ```
- `nvidia_drm` (`modeset=1`) грузится **ещё в initramfs** и забирает DRM-устройство
  раньше `i915`. Hyprland/Aquamarine поднимается на NVIDIA, где подключённых
  мониторов нет → сессия «не запускается».
- Блэклист убирает `nvidia_drm`, экран отдаётся `i915`, всё поднимается — но
  дискретка теряет render-ноду, offload/игры не работают.

## Решение

Убрать `nvidia_drm` из ранней загрузки, но грузить его **позже** (после `i915`)
через `modules-load.d`. Порядок карт фиксируется: `card0 = i915` (экран),
`card1 = NVIDIA` (offload). Полная функциональность NVIDIA сохраняется.

## Что делает скрипт

1. В `/etc/mkinitcpio.conf.d/nvidia.conf` оставляет
   `MODULES+=(nvidia nvidia_modeset nvidia_uvm)` (с бэкапом рядом).
2. Создаёт `/etc/modules-load.d/nvidia-drm.conf` с `nvidia_drm`.
3. Пересобирает boot-образы: `limine-update` + `limine-snapper-sync`.
4. Печатает команды для проверки после перезагрузки.

## Запуск

```bash
cd ~/Projects/omarchy-nvidia-hybrid-fix
sudo bash fix-nvidia-drm.sh
```

Скрипт сам запрашивает `sudo`, если запущен без него.

## Проверка после перезагрузки

```bash
cat /proc/cmdline      # без modprobe.blacklist=nvidia_drm
ls -l /dev/dri         # card0=i915, card1=nvidia, renderD128/129
hyprctl monitors       # встроенный eDP на месте
nvidia-smi             # дискретка отвечает, offload работает
```

## Откат

```bash
sudo bash fix-nvidia-drm.sh --revert
```

Восстановит исходный `nvidia.conf` из бэкапа, удалит
`/etc/modules-load.d/nvidia-drm.conf` и пересоберёт boot-образы.

Аварийный вариант, если система не поднимается: загрузиться из снапшота в меню
Limine и добавить блэклист в дроп-ин
`/etc/limine-entry-tool.d/nvidia-drm-blacklist.conf`:

```
KERNEL_CMDLINE[default]+=" modprobe.blacklist=nvidia_drm"
```

## Примечание

Правки в `/etc/mkinitcpio.conf.d` и `/etc/modules-load.d` — системные, требуют
`sudo`. Работоспособность подтверждается только после перезагрузки.
