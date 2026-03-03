#!/usr/bin/env bash
set -euo pipefail

# ====== НАСТРОЙКИ ======
SRC_HOST="138.124.4.132"
SRC_PORT="22122"
SRC_USER="root"
SRC_DIR="/etc/letsencrypt/live/mutabor-sec.ru-0001"

DST_DIR="/etc/letsencrypt/live/mutabor-sec.ru"

# Если хочешь после обновления перезапускать сервисы — раскомментируй нужное:
# RESTART_SERVICES=(nginx x-ui 3x-ui)

# ====== ПРОВЕРКИ ======
if [[ "${EUID}" -ne 0 ]]; then
  echo "Запусти от root: sudo bash $0"
  exit 1
fi

apt update -y >/dev/null 2>&1 || true
DEBIAN_FRONTEND=noninteractive apt install -y rsync sshpass >/dev/null

mkdir -p "/etc/letsencrypt/live"
mkdir -p "${DST_DIR}"

echo "==> Копируем сертификаты ${SRC_USER}@${SRC_HOST}:${SRC_DIR}/ -> ${DST_DIR}/"

export SSHPASS="${SRC_PASS}"
sshpass -e rsync -avL --delete \
  -e "ssh -p ${SRC_PORT} -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null" \
  "${SRC_USER}@${SRC_HOST}:${SRC_DIR}/" \
  "${DST_DIR}/"

echo "==> Проверяем наличие файлов"
for f in cert.pem chain.pem fullchain.pem privkey.pem; do
  if [[ ! -f "${DST_DIR}/${f}" ]]; then
    echo "ОШИБКА: не найден ${DST_DIR}/${f}"
    exit 2
  fi
done

echo "==> Выставляем права"
chown -R root:root "${DST_DIR}"
chmod 700 "${DST_DIR}"
chmod 600 "${DST_DIR}/privkey.pem"
chmod 644 "${DST_DIR}/cert.pem" "${DST_DIR}/chain.pem" "${DST_DIR}/fullchain.pem"

echo "==> Готово: сертификаты обновлены в ${DST_DIR}"

# Если нужно — рестарт сервисов:
# for s in "${RESTART_SERVICES[@]}"; do
#   systemctl restart "$s" || true
# done

# ====== REBOOT (опционально) ======
DO_REBOOT="${DO_REBOOT:-0}"

if [[ "${DO_REBOOT}" == "1" ]]; then
  echo "==> Перезагрузка через 5 секунд (DO_REBOOT=1)"
  sleep 5
  /usr/sbin/reboot
else
  echo "==> Перезагрузка не выполнена. Чтобы перезагрузить автоматически: DO_REBOOT=1"
fi
