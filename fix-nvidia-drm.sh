#!/usr/bin/env bash
set -euo pipefail

# Omarchy на гибридном ноутбуке (Intel iGPU + NVIDIA dGPU).
# Причина "Omarchy не запускается без modprobe.blacklist=nvidia_drm":
# Omarchy кладёт nvidia_drm в initramfs, он забирает DRM-устройство
# раньше i915, и Hyprland поднимается на NVIDIA без подключённых мониторов.
#
# Решение: убрать nvidia_drm из ранней загрузки и грузить его позже
# (после i915) через modules-load.d. iGPU остаётся primary (card0),
# а дискретка полностью рабочая (offload/CUDA).

MKINITCPIO_CONF="/etc/mkinitcpio.conf.d/nvidia.conf"
MKINITCPIO_MAIN="/etc/mkinitcpio.conf"
MODULES_LOAD="/etc/modules-load.d/nvidia-drm.conf"

log()  { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[!]\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31m[x]\033[0m %s\n' "$*" >&2; exit 1; }

# --- root ---
if [[ $EUID -ne 0 ]]; then
  exec sudo -E bash "$0" "$@"
fi

REVERT=0
[[ "${1:-}" == "--revert" ]] && REVERT=1

# --- выбрать конфиг mkinitcpio с записью nvidia_drm ---
CONF=""
for f in "$MKINITCPIO_CONF" "$MKINITCPIO_MAIN"; do
  if [[ -f "$f" ]] && grep -q 'nvidia_drm' "$f"; then
    CONF="$f"; break
  fi
done
# Если nvidia_drm уже убран, но drop-in существует — работаем с ним.
if [[ -z "$CONF" && -f "$MKINITCPIO_CONF" ]]; then
  CONF="$MKINITCPIO_CONF"
fi

if [[ $REVERT -eq 1 ]]; then
  log "Откат к исходному состоянию"
  if [[ "$CONF" == "$MKINITCPIO_CONF" ]]; then
    backup="$(ls -1t "${CONF}.bak."* 2>/dev/null | head -n1 || true)"
    if [[ -n "$backup" ]]; then
      cp -a "$backup" "$CONF"
      log "Восстановлен $CONF из $backup"
    else
      warn "Бэкап ${CONF}.bak.* не найден, правлю строку вручную"
      if grep -q '^MODULES+=' "$CONF"; then
        sed -i -E 's/^(MODULES\+=\([^)]*)\)/\1 nvidia_drm)/' "$CONF"
      fi
    fi
  fi
  if [[ -f "$MODULES_LOAD" ]]; then
    rm -f "$MODULES_LOAD"
    log "Удалён $MODULES_LOAD"
  fi
  log "Пересборка boot-образов"
  command -v limine-update >/dev/null 2>&1 && limine-update || warn "limine-update не найден"
  command -v limine-snapper-sync >/dev/null 2>&1 && limine-snapper-sync || true
  log "Откат завершён. Перезагрузитесь."
  exit 0
fi

[[ -n "$CONF" ]] || die "Не найден конфиг mkinitcpio с nvidia_drm ($MKINITCPIO_CONF / $MKINITCPIO_MAIN)"

# --- 1. Убрать nvidia_drm из initramfs ---
if grep -q 'nvidia_drm' "$CONF"; then
  backup="${CONF}.bak.$(date +%Y%m%d-%H%M%S)"
  cp -a "$CONF" "$backup"
  log "Бэкап: $backup"
  sed -i -E 's/^(MODULES\+=[^)]*)[[:space:]]+nvidia_drm/\1/' "$CONF"
  if grep -q 'nvidia_drm' "$CONF"; then
    warn "Не удалось убрать nvidia_drm автоматически, проверьте $CONF вручную"
  else
    log "nvidia_drm убран из $CONF"
  fi
else
  log "nvidia_drm уже отсутствует в $CONF"
fi

# --- 2. Грузить nvidia_drm в рантайме (после i915) ---
echo 'nvidia_drm' > "$MODULES_LOAD"
log "Создан/обновлён $MODULES_LOAD"

# --- 3. Пересобрать boot-образы ---
log "Пересборка boot-образов (limine)"
command -v limine-update >/dev/null 2>&1 && limine-update || warn "limine-update не найден — соберите образы вручную"
command -v limine-snapper-sync >/dev/null 2>&1 && limine-snapper-sync || warn "limine-snapper-sync не найден"

# --- 4. Итог ---
cat <<EOF

$(printf '\033[1;32mГотово.\033[0m Перезагрузитесь и проверьте:')

  cat /proc/cmdline                       # без modprobe.blacklist=nvidia_drm
  ls -l /dev/dri                          # card0=i915, card1=nvidia + render-ноды
  hyprctl monitors                        # встроенный eDP на месте
  nvidia-smi                              # дискретка отвечает, offload работает

Откат:  sudo bash $0 --revert
EOF
