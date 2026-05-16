#!/bin/bash
# Backup do banco de uma instância em /home/deploy/backup-<empresa>/
# Uso: source "$(dirname ...)/tools/mf_backup_banco_empresa.sh"
#      mf_backup_banco_empresa "web01" && echo "$MF_BACKUP_ARQUIVO"

mf_backup_banco_empresa() {
  local empresa="$1"
  local env_file="/home/deploy/${empresa}/backend/.env"
  MF_BACKUP_ARQUIVO=""

  [ -n "$empresa" ] || return 1
  [ -f "$env_file" ] || return 1

  local db_user db_pass db_name db_host db_port backup_dir data
  db_user=$(grep -m1 '^DB_USER=' "$env_file" 2>/dev/null | cut -d '=' -f2- | tr -d '\r')
  db_pass=$(grep -m1 '^DB_PASS=' "$env_file" 2>/dev/null | cut -d '=' -f2- | tr -d '\r')
  db_name=$(grep -m1 '^DB_NAME=' "$env_file" 2>/dev/null | cut -d '=' -f2- | tr -d '\r')
  db_host=$(grep -m1 '^DB_HOST=' "$env_file" 2>/dev/null | cut -d '=' -f2- | tr -d '\r')
  db_port=$(grep -m1 '^DB_PORT=' "$env_file" 2>/dev/null | cut -d '=' -f2- | tr -d '\r')

  db_user="${db_user:-$empresa}"
  db_name="${db_name:-$empresa}"
  db_host="${db_host:-127.0.0.1}"
  [ "$db_host" = "localhost" ] && db_host="127.0.0.1"
  db_port="${db_port:-5432}"

  [ -n "$db_pass" ] || return 1
  [[ "$db_name" =~ ^[a-zA-Z0-9_]+$ ]] || return 1

  backup_dir="/home/deploy/backup-${empresa}"
  mkdir -p "${backup_dir}"
  chown deploy:deploy "${backup_dir}" 2>/dev/null || true

  data=$(date +%Y-%m-%d_%H-%M-%S)
  MF_BACKUP_ARQUIVO="${backup_dir}/backup-${db_name}-${data}.sql"

  export PGPASSWORD="${db_pass}"
  if ! pg_dump -h "${db_host}" -p "${db_port}" -U "${db_user}" -d "${db_name}" -F p >"${MF_BACKUP_ARQUIVO}" 2>/dev/null; then
    unset PGPASSWORD
    rm -f "${MF_BACKUP_ARQUIVO}"
    return 1
  fi
  unset PGPASSWORD
  chown deploy:deploy "${MF_BACKUP_ARQUIVO}" 2>/dev/null || true
  [ -s "${MF_BACKUP_ARQUIVO}" ] || return 1
  return 0
}
