#!/usr/bin/env bash
set -euo pipefail

# ========= НАСТРОЙКИ =========
NEW_USER="hosty"

SSH_PORT_NEW="22122"
SSH_PORT_OLD="22"

SWAP_FILE="/swap"
SWAP_SIZE="1G"

JOURNALD_MAX_USE="500M"
JOURNALD_MAX_FILE_SEC="2week"

UFW_EXTRA_PORTS=(80 443 2087 2096)

# Сертификаты: источник (-0001) -> целевая папка (без -0001)
CERT_SOURCE_PORT="22122"
CERT_SOURCE_USER="root"
CERT_SOURCE_PASS="${COMMON_PASS}"
CERT_SOURCE_DIR="/etc/letsencrypt/live/mutabor-sec.ru-0001"

CERT_DEST_DIR="/etc/letsencrypt/live/mutabor-sec.ru"

# ========= ВСПОМОГАТЕЛЬНЫЕ =========
need_root() {
  if [[ "${EUID}" -ne 0 ]]; then
    echo "Запусти от root: sudo bash $0"
    exit 1
  fi
}

has_cmd() { command -v "$1" >/dev/null 2>&1; }

ensure_line_kv() {
  local file="$1" key="$2" value="$3"
  mkdir -p "$(dirname "$file")"
  touch "$file"
  if grep -qE "^\s*${key}\s*=" "$file"; then
    sed -i -E "s|^\s*${key}\s*=.*|${key}=${value}|g" "$file"
  else
    echo "${key}=${value}" >> "$file"
  fi
}

ensure_sshd_kv() {
  local key="$1" value="$2"
  local file="/etc/ssh/sshd_config"
  touch "$file"
  if grep -qE "^\s*#?\s*${key}\s+" "$file"; then
    sed -i -E "s|^\s*#?\s*${key}\s+.*|${key} ${value}|g" "$file"
  else
    echo "${key} ${value}" >> "$file"
  fi
}

restart_service() {
  local svc="$1"
  systemctl restart "$svc" || true
}

# ========= ОСНОВНОЕ =========
need_root

echo "==> Обновление системы"
apt update
DEBIAN_FRONTEND=noninteractive apt upgrade -y

echo "==> Установка пакетов"
apt install -y sudo ufw zsh software-properties-common neovim curl wget net-tools snapd rsync sshpass

echo "==> Создание пользователя ${NEW_USER} (если нет)"
if id "${NEW_USER}" >/dev/null 2>&1; then
  echo "Пользователь ${NEW_USER} уже существует — ок"
else
  useradd -m -G sudo -s /bin/bash "${NEW_USER}"
fi

echo "==> Установка паролей root и ${NEW_USER}"
echo "root:${COMMON_PASS}" | chpasswd
echo "${NEW_USER}:${COMMON_PASS}" | chpasswd

echo "==> Swap: ${SWAP_SIZE} в файле ${SWAP_FILE}"
if swapon --show | awk '{print $1}' | grep -qx "${SWAP_FILE}"; then
  echo "Swap уже активен (${SWAP_FILE}) — пропускаю"
else
  if [[ ! -f "${SWAP_FILE}" ]]; then
    fallocate -l "${SWAP_SIZE}" "${SWAP_FILE}"
    chmod 600 "${SWAP_FILE}"
    mkswap "${SWAP_FILE}"
  fi
  swapon "${SWAP_FILE}"
fi

if ! grep -qE "^\s*${SWAP_FILE}\s+none\s+swap\s+" /etc/fstab; then
  echo "${SWAP_FILE} none swap sw 0 0" >> /etc/fstab
fi

echo "==> Настройка journald"
JOURNALD_CONF="/etc/systemd/journald.conf"
ensure_line_kv "${JOURNALD_CONF}" "SystemMaxUse" "${JOURNALD_MAX_USE}"
ensure_line_kv "${JOURNALD_CONF}" "MaxFileSec" "${JOURNALD_MAX_FILE_SEC}"
restart_service systemd-journald

echo "==> UFW: разрешаем SSH старый+новый, включаем firewall"
ufw allow "${SSH_PORT_OLD}/tcp" || true
ufw allow "${SSH_PORT_NEW}/tcp" || true
ufw --force enable
restart_service ufw

echo "==> SSH: Port=${SSH_PORT_NEW}, PermitRootLogin=no, PubkeyAuthentication=yes"
ensure_sshd_kv "Port" "${SSH_PORT_NEW}"
ensure_sshd_kv "PermitRootLogin" "no"
ensure_sshd_kv "PubkeyAuthentication" "yes"
restart_service ssh
restart_service sshd

echo "==> UFW: удаляем 22/tcp и открываем дополнительные порты"
ufw delete allow "${SSH_PORT_OLD}/tcp" || true
for p in "${UFW_EXTRA_PORTS[@]}"; do
  ufw allow "${p}" || true
done
ufw reload
ufw status verbose || true

echo "==> Установка 3x-ui"
bash < <(curl -Ls https://raw.githubusercontent.com/mhsanaei/3x-ui/master/install.sh)

echo "==> Подготовка каталогов сертификатов"
mkdir -p "/etc/letsencrypt/live"
mkdir -p "${CERT_DEST_DIR}"

echo "==> Подтягиваем сертификаты: ${CERT_SOURCE_USER}@${CERT_SOURCE_HOST}:${CERT_SOURCE_DIR}/ -> ${CERT_DEST_DIR}/"
# Отключаем strict host checking, чтобы скрипт не ждал подтверждения fingerprint
export SSHPASS="${CERT_SOURCE_PASS}"
sshpass -e rsync -av --delete \
  -e "ssh -p ${CERT_SOURCE_PORT} -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null" \
  "${CERT_SOURCE_USER}@${CERT_SOURCE_HOST}:${CERT_SOURCE_DIR}/" \
  "${CERT_DEST_DIR}/"

echo "==> Проставляем безопасные права на ключи"
chown -R root:root "${CERT_DEST_DIR}"
chmod 700 "${CERT_DEST_DIR}"
chmod 600 "${CERT_DEST_DIR}/privkey.pem" || true
chmod 644 "${CERT_DEST_DIR}/fullchain.pem" "${CERT_DEST_DIR}/chain.pem" "${CERT_DEST_DIR}/cert.pem" || true

echo
echo "ГОТОВО."
echo "- SSH порт: ${SSH_PORT_NEW}"
echo "- Пароль root и ${NEW_USER} установлен"
echo "- Сертификаты в: ${CERT_DEST_DIR}"
echo
echo "Проверь вход по SSH на новом порту:"
echo "ssh -p ${SSH_PORT_NEW} ${NEW_USER}@<server_ip>"

echo "==> Добавляем ночной перезапуск в 02:00 (root cron)"

CRON_JOB="0 2 * * * /sbin/shutdown -r now"

# Проверяем, есть ли уже такая запись
( crontab -l 2>/dev/null | grep -F "$CRON_JOB" ) && \
  echo "Cron уже содержит задачу — пропускаю" || \
  ( crontab -l 2>/dev/null; echo "$CRON_JOB" ) | crontab -

echo "Cron настроен:"
crontab -l

# ====== REBOOT (опционально) ======
DO_REBOOT="${DO_REBOOT:-0}"

if [[ "${DO_REBOOT}" == "1" ]]; then
  echo "==> Перезагрузка через 5 секунд (DO_REBOOT=1)"
  sleep 5
  /usr/sbin/reboot
else
  echo "==> Перезагрузка не выполнена. Чтобы перезагрузить автоматически: DO_REBOOT=1"
fi
