#!/bin/bash

# Backup diário Postgres nativo: um dump por instância em /home/deploy/backup-<empresa>/
# Várias instâncias no mesmo servidor Postgres — cada banco na pasta da sua empresa.

GREEN='\033[1;32m'
BLUE='\033[1;34m'
WHITE='\033[1;37m'
RED='\033[1;31m'
YELLOW='\033[1;33m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALADOR_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
ARQUIVO_VARIAVEIS="${INSTALADOR_DIR}/VARIAVEIS_INSTALACAO"
DB_HOST_DEFAULT="127.0.0.1"
DB_PORT_DEFAULT="5432"
CRON_SCRIPT_PATH="${SCRIPT_DIR}/agendar_backup_bd_nativo.sh"

if [ "$EUID" -ne 0 ]; then
  echo
  printf "${WHITE} >> Este script precisa ser executado como root.${WHITE}\n"
  exit 1
fi

banner() {
  printf " ${BLUE}\n"
  printf "  Backup Banco Nativo (PostgreSQL)\n"
  printf " ${WHITE}\n"
}

ler_retencao_dias() {
  local dir="${1:-}"
  local cfg="${dir}/.retencao_dias"
  if [ -f "${cfg}" ]; then
    local ret
    read -r ret < "${cfg}" 2>/dev/null
    if [[ "${ret}" =~ ^[0-9]+$ ]] && [ "${ret}" -ge 1 ]; then
      echo "${ret}"
      return
    fi
  fi
  echo "7"
}

postgres_nativo_ativo() {
  systemctl is-active --quiet postgresql 2>/dev/null
}

mf_env_backend_valor() {
  local env_file="$1"
  local chave="$2"
  [ -f "$env_file" ] || return 1
  local linha
  linha=$(grep -m1 "^${chave}=" "$env_file" 2>/dev/null || true)
  [ -n "$linha" ] || return 1
  local valor="${linha#*=}"
  valor="${valor%$'\r'}"
  valor="${valor#\"}"; valor="${valor%\"}"
  valor="${valor#\'}"; valor="${valor%\'}"
  printf '%s' "$valor"
}

# Lista empresas com backend instalado (principal + VARIAVEIS_INSTALACAO_INSTANCIA_*)
backup_detectar_empresas() {
  BACKUP_EMPRESAS=()
  local temp_empresa="" arquivo

  if [ -f "${ARQUIVO_VARIAVEIS}" ]; then
    # shellcheck source=/dev/null
    source "${ARQUIVO_VARIAVEIS}" 2>/dev/null
    temp_empresa="${empresa:-}"
    if [ -n "$temp_empresa" ] && [ -d "/home/deploy/${temp_empresa}/backend" ]; then
      BACKUP_EMPRESAS+=("$temp_empresa")
    fi
  fi

  shopt -s nullglob
  for arquivo in "${INSTALADOR_DIR}"/VARIAVEIS_INSTALACAO_INSTANCIA_*; do
    [ -f "$arquivo" ] || continue
    # shellcheck source=/dev/null
    source "$arquivo" 2>/dev/null
    temp_empresa="${empresa:-}"
    if [ -n "$temp_empresa" ] && [ -d "/home/deploy/${temp_empresa}/backend" ]; then
      local ja=0 e
      for e in "${BACKUP_EMPRESAS[@]}"; do
        [ "$e" = "$temp_empresa" ] && ja=1 && break
      done
      [ "$ja" -eq 0 ] && BACKUP_EMPRESAS+=("$temp_empresa")
    fi
  done
  shopt -u nullglob
}

backup_credenciais_empresa() {
  local emp="$1"
  local env_file="/home/deploy/${emp}/backend/.env"
  local usuario senha host port

  usuario=$(mf_env_backend_valor "$env_file" "DB_USER" || true)
  senha=$(mf_env_backend_valor "$env_file" "DB_PASS" || true)
  host=$(mf_env_backend_valor "$env_file" "DB_HOST" || true)
  port=$(mf_env_backend_valor "$env_file" "DB_PORT" || true)

  if [ -f "${ARQUIVO_VARIAVEIS}" ]; then
    # shellcheck source=/dev/null
    source "${ARQUIVO_VARIAVEIS}" 2>/dev/null
    [ -z "$senha" ] && senha="${senha_deploy:-}"
    [ -z "$usuario" ] && usuario="${empresa}"
  fi

  host="${host:-$DB_HOST_DEFAULT}"
  [ "$host" = "localhost" ] && host="$DB_HOST_DEFAULT"
  port="${port:-$DB_PORT_DEFAULT}"
  usuario="${usuario:-$emp}"

  printf '%s|%s|%s|%s' "$usuario" "$senha" "$host" "$port"
}

backup_nome_banco_empresa() {
  local emp="$1"
  local env_file="/home/deploy/${emp}/backend/.env"
  local db
  db=$(mf_env_backend_valor "$env_file" "DB_NAME" || true)
  db="${db:-$emp}"
  printf '%s' "$db"
}

backup_nome_banco_api_oficial() {
  local emp="$1"
  local env_file="/home/deploy/${emp}/api_oficial/.env"
  mf_env_backend_valor "$env_file" "DATABASE_NAME" || true
}

# Dump de um banco → /home/deploy/backup-<empresa>/backup-<dbname>-<data>.sql.gz
backup_dump_banco() {
  local emp="$1"
  local db_name="$2"
  local usuario_db="$3"
  local senha_db="$4"
  local db_host="$5"
  local db_port="$6"
  local backup_dir="$7"
  local log_file="$8"
  local data="$9"

  [ -z "$db_name" ] && return 1
  if [[ ! "$db_name" =~ ^[a-zA-Z0-9_]+$ ]]; then
    echo "$(date): ERRO [${emp}] nome de banco inválido: ${db_name}" >>"${log_file}" 2>&1
    return 1
  fi

  local arquivo="${backup_dir}/backup-${db_name}-${data}.sql.gz"
  local tmp_sql
  tmp_sql=$(mktemp)

  if ! PGPASSWORD="${senha_db}" psql -h "${db_host}" -p "${db_port}" -U "${usuario_db}" -d postgres -t -A -c \
    "SELECT 1 FROM pg_database WHERE datname = '${db_name}';" 2>>"${log_file}" | grep -q 1; then
    echo "$(date): AVISO [${emp}] banco '${db_name}' não existe no Postgres — ignorado." >>"${log_file}" 2>&1
    rm -f "${tmp_sql}"
    return 0
  fi

  if PGPASSWORD="${senha_db}" pg_dump -h "${db_host}" -p "${db_port}" -U "${usuario_db}" -d "${db_name}" -F p >"${tmp_sql}" 2>>"${log_file}"; then
    gzip -c "${tmp_sql}" >"${arquivo}"
    chown deploy:deploy "${arquivo}" 2>/dev/null || true
    if [ -s "${arquivo}" ]; then
      echo "$(date): OK [${emp}] ${db_name} -> ${arquivo} ($(stat -c%s "${arquivo}" 2>/dev/null || echo 0) bytes)" >>"${log_file}" 2>&1
    else
      echo "$(date): AVISO [${emp}] ${db_name} — dump vazio" >>"${log_file}" 2>&1
    fi
  else
    echo "$(date): ERRO [${emp}] dump de ${db_name}" >>"${log_file}" 2>&1
  fi
  rm -f "${tmp_sql}"
}

# Uma instância: pasta /home/deploy/backup-<empresa>/ com o(s) banco(s) dela
backup_executar_empresa() {
  local emp="$1"
  local cred db_main db_of data retencao
  local usuario_db senha_db db_host db_port

  cred=$(backup_credenciais_empresa "$emp")
  usuario_db="${cred%%|*}"; cred="${cred#*|}"
  senha_db="${cred%%|*}"; cred="${cred#*|}"
  db_host="${cred%%|*}"; db_port="${cred#*|}"

  if [ -z "$senha_db" ]; then
    echo "$(date): ERRO [${emp}] senha do banco vazia" >>"${LOG_GLOBAL}" 2>&1
    return 1
  fi

  local backup_dir="/home/deploy/backup-${emp}"
  mkdir -p "${backup_dir}"
  chown deploy:deploy "${backup_dir}" 2>/dev/null || true
  local log_file="${backup_dir}/backup.log"
  data=$(date +%Y-%m-%d_%H-%M-%S)
  retencao=$(ler_retencao_dias "${backup_dir}")

  db_main=$(backup_nome_banco_empresa "$emp")
  echo "$(date): --- Backup instância ${emp} (banco ${db_main}) -> ${backup_dir} ---" >>"${log_file}" 2>&1
  backup_dump_banco "$emp" "$db_main" "$usuario_db" "$senha_db" "$db_host" "$db_port" "$backup_dir" "$log_file" "$data"

  db_of=$(backup_nome_banco_api_oficial "$emp")
  if [ -n "$db_of" ] && [ "$db_of" != "$db_main" ]; then
    backup_dump_banco "$emp" "$db_of" "$usuario_db" "$senha_db" "$db_host" "$db_port" "$backup_dir" "$log_file" "$data"
  fi

  find "${backup_dir}" -maxdepth 1 -name "backup-*.sql.gz" -mtime +"${retencao}" -delete 2>/dev/null
  return 0
}

# Cron: backup de todas as instâncias detectadas
executar_backup() {
  export PATH="/usr/bin:/usr/local/bin:${PATH}"
  LOG_GLOBAL="/var/log/backup-bd-nativo.log"

  cd "${INSTALADOR_DIR}" || {
    echo "$(date): ERRO ao acessar ${INSTALADOR_DIR}" >>"${LOG_GLOBAL}"
    return 1
  }

  if [ -f "${ARQUIVO_VARIAVEIS}" ]; then
    # shellcheck source=/dev/null
    source "${ARQUIVO_VARIAVEIS}" 2>/dev/null
    if [ "${ALTA_PERFORMANCE:-0}" = "1" ]; then
      echo "$(date): Alta Performance — backup nativo ignorado." >>"${LOG_GLOBAL}"
      return 0
    fi
  fi

  if ! postgres_nativo_ativo; then
    echo "$(date): PostgreSQL nativo inativo." >>"${LOG_GLOBAL}"
    return 1
  fi

  backup_detectar_empresas
  if [ ${#BACKUP_EMPRESAS[@]} -eq 0 ]; then
    echo "$(date): Nenhuma instância com /home/deploy/<empresa>/backend encontrada." >>"${LOG_GLOBAL}"
    return 1
  fi

  echo "$(date): Iniciando backup nativo (${#BACKUP_EMPRESAS[@]} instância(s))." >>"${LOG_GLOBAL}"
  local emp
  for emp in "${BACKUP_EMPRESAS[@]}"; do
    backup_executar_empresa "$emp" || true
  done
  echo "$(date): Backup nativo finalizado." >>"${LOG_GLOBAL}"
  return 0
}

agendar() {
  banner
  printf "${WHITE} >> Backup diário do Postgres nativo (várias instâncias)${WHITE}\n"
  echo

  if [ ! -f "${ARQUIVO_VARIAVEIS}" ]; then
    printf "${RED} >> Arquivo ${ARQUIVO_VARIAVEIS} não encontrado.${WHITE}\n"
    sleep 3
    return 1
  fi

  # shellcheck source=/dev/null
  source "${ARQUIVO_VARIAVEIS}" 2>/dev/null
  if [ "${ALTA_PERFORMANCE:-0}" = "1" ]; then
    printf "${RED} >> Apenas para instalação nativa (ALTA_PERFORMANCE=1 neste servidor).${WHITE}\n"
    sleep 3
    return 1
  fi

  if ! postgres_nativo_ativo; then
    printf "${RED} >> PostgreSQL nativo não está ativo.${WHITE}\n"
    sleep 3
    return 1
  fi

  command -v psql >/dev/null 2>&1 || {
    apt-get update -qq && apt-get install -y postgresql-client >/dev/null 2>&1
  }
  command -v psql >/dev/null 2>&1 || {
    printf "${RED} >> Instale postgresql-client.${WHITE}\n"
    sleep 3
    return 1
  fi

  backup_detectar_empresas
  if [ ${#BACKUP_EMPRESAS[@]} -eq 0 ]; then
    printf "${RED} >> Nenhuma instância detectada.${WHITE}\n"
    sleep 3
    return 1
  fi

  printf "${GREEN} >> Instâncias que serão backupeadas (banco → pasta):${WHITE}\n"
  echo
  local emp db_main db_of cred
  for emp in "${BACKUP_EMPRESAS[@]}"; do
    db_main=$(backup_nome_banco_empresa "$emp")
    db_of=$(backup_nome_banco_api_oficial "$emp")
    printf "   ${BLUE}${emp}${WHITE} → ${YELLOW}/home/deploy/backup-${emp}/${WHITE}\n"
    printf "      Banco MultiFlow: ${db_main}\n"
    [ -n "$db_of" ] && [ "$db_of" != "$db_main" ] && printf "      Banco API Oficial: ${db_of}\n"
    cred=$(backup_credenciais_empresa "$emp")
    local u="${cred%%|*}" s="${cred#*|}"; s="${s%%|*}"
    if [ -z "$s" ]; then
      printf "${RED}      AVISO: sem senha no .env — configure antes do agendamento.${WHITE}\n"
    fi
  done
  echo

  printf "${WHITE} >> Quantos dias reter os backups em cada pasta backup-<empresa>? (padrão 7):${WHITE}\n"
  read -p "> " retencao_digitado
  retencao_digitado=${retencao_digitado:-7}
  if ! [[ "${retencao_digitado}" =~ ^[0-9]+$ ]] || [ "${retencao_digitado}" -lt 1 ]; then
    retencao_digitado=7
  fi
  for emp in "${BACKUP_EMPRESAS[@]}"; do
    mkdir -p "/home/deploy/backup-${emp}"
    echo "${retencao_digitado}" >"/home/deploy/backup-${emp}/.retencao_dias"
    chown deploy:deploy "/home/deploy/backup-${emp}" "/home/deploy/backup-${emp}/.retencao_dias" 2>/dev/null || true
  done
  printf "${GREEN} >> Retenção: ${retencao_digitado} dias em cada pasta.${WHITE}\n"
  echo

  CRON_LINHA="0 2 * * * ${CRON_SCRIPT_PATH} --backup >> /var/log/backup-bd-nativo.log 2>&1"
  if crontab -l 2>/dev/null | grep -q "agendar_backup_bd_nativo.sh --backup"; then
    printf "${YELLOW} >> Cron já configurado (2h). Um job faz backup de todas as instâncias.${WHITE}\n"
  else
    (crontab -l 2>/dev/null; echo "${CRON_LINHA}") | crontab -
    printf "${GREEN} >> Cron agendado (diário 2h) — todas as instâncias.${WHITE}\n"
  fi
  printf "${WHITE} >> Log geral: /var/log/backup-bd-nativo.log${WHITE}\n"
  printf "${WHITE} >> Log por instância: /home/deploy/backup-<empresa>/backup.log${WHITE}\n"
  echo

  printf "${WHITE} >> Executar backup agora? (S/N):${WHITE}\n"
  read -p "> " exec_now
  exec_now=$(echo "${exec_now}" | tr '[:upper:]' '[:lower:]')
  if [ "${exec_now}" = "s" ]; then
    executar_backup
    printf "${GREEN} >> Concluído. Verifique /home/deploy/backup-<empresa>/ em cada instância.${WHITE}\n"
  fi
  echo
  sleep 2
  return 0
}

case "${1:-}" in
  --backup)
    executar_backup
    ;;
  *)
    agendar
    ;;
esac
