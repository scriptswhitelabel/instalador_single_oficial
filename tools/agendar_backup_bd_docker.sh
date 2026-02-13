#!/bin/bash

# Agendar e executar backup diário do Postgres em Docker (modo Alta Performance).
# Um pg_dump por banco, salvo em /home/deploy/backup-bd-docker.

GREEN='\033[1;32m'
BLUE='\033[1;34m'
WHITE='\033[1;37m'
RED='\033[1;31m'
YELLOW='\033[1;33m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALADOR_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
ARQUIVO_VARIAVEIS="${INSTALADOR_DIR}/VARIAVEIS_INSTALACAO"
BACKUP_DIR="/home/deploy/backup-bd-docker"
CONFIG_RETENCAO="${BACKUP_DIR}/.retencao_dias"
DB_HOST="127.0.0.1"
DB_PORT="7532"
CRON_SCRIPT_PATH="${SCRIPT_DIR}/agendar_backup_bd_docker.sh"

if [ "$EUID" -ne 0 ]; then
  echo
  printf "${WHITE} >> Este script precisa ser executado como root.${WHITE}\n"
  exit 1
fi

banner() {
  printf " ${BLUE}\n"
  printf "  Backup Banco Alta Performance (Docker)\n"
  printf " ${WHITE}\n"
}

# Lê dias de retenção (arquivo em BACKUP_DIR ou padrão 7)
ler_retencao_dias() {
  if [ -f "${CONFIG_RETENCAO}" ]; then
    read -r ret < "${CONFIG_RETENCAO}" 2>/dev/null
    if [[ "${ret}" =~ ^[0-9]+$ ]] && [ "${ret}" -ge 1 ]; then
      echo "${ret}"
      return
    fi
  fi
  echo "7"
}

# Executa apenas o backup (chamado pelo cron ou com --backup)
executar_backup() {
  RETENCAO_DIAS=$(ler_retencao_dias)
  if [ ! -f "${ARQUIVO_VARIAVEIS}" ]; then
    echo "VARIAVEIS_INSTALACAO não encontrado. Backup cancelado." >> "${BACKUP_DIR}/backup.log" 2>&1
    return 1
  fi
  # shellcheck source=/dev/null
  source "${ARQUIVO_VARIAVEIS}" 2>/dev/null
  if [ "${ALTA_PERFORMANCE}" != "1" ]; then
    echo "$(date): Instalação não é Alta Performance. Backup cancelado." >> "${BACKUP_DIR}/backup.log" 2>&1
    return 0
  fi
  if [ -z "${empresa}" ] || [ -z "${senha_deploy}" ]; then
    echo "$(date): empresa ou senha_deploy não definidos." >> "${BACKUP_DIR}/backup.log" 2>&1
    return 1
  fi

  mkdir -p "${BACKUP_DIR}"
  chown deploy:deploy "${BACKUP_DIR}"
  DATA=$(date +%Y-%m-%d_%H-%M-%S)
  export PGPASSWORD="${senha_deploy}"

  # Listar bancos (exclui templates) - usar conexão direta ao Postgres (porta 7532)
  BANCOS=$(psql -h "${DB_HOST}" -p "${DB_PORT}" -U "${empresa}" -d postgres -t -A -c "SELECT datname FROM pg_database WHERE datistemplate = false AND datname IS NOT NULL ORDER BY datname;" 2>> "${BACKUP_DIR}/backup.log")
  if [ -z "${BANCOS}" ]; then
    echo "$(date): Nenhum banco listado ou falha de conexão em ${DB_HOST}:${DB_PORT}" >> "${BACKUP_DIR}/backup.log" 2>&1
    unset PGPASSWORD
    return 1
  fi

  for DB in ${BANCOS}; do
    DB_CLEAN=$(echo "${DB}" | tr -d '\r\n')
    [ -z "${DB_CLEAN}" ] && continue
    ARQUIVO="${BACKUP_DIR}/backup-${DB_CLEAN}-${DATA}.sql.gz"
    TMP_SQL=$(mktemp)
    if pg_dump -h "${DB_HOST}" -p "${DB_PORT}" -U "${empresa}" -d "${DB_CLEAN}" -F p > "${TMP_SQL}" 2>> "${BACKUP_DIR}/backup.log"; then
      if [ -s "${TMP_SQL}" ]; then
        gzip -c "${TMP_SQL}" > "${ARQUIVO}"
        chown deploy:deploy "${ARQUIVO}"
        echo "$(date): OK ${DB_CLEAN} -> ${ARQUIVO} ($(stat -c%s "${ARQUIVO}" 2>/dev/null || echo 0) bytes)" >> "${BACKUP_DIR}/backup.log" 2>&1
      else
        echo "$(date): AVISO ${DB_CLEAN} - pg_dump retornou 0 bytes. Verifique permissões e conexão." >> "${BACKUP_DIR}/backup.log" 2>&1
      fi
    else
      echo "$(date): ERRO ao fazer dump de ${DB_CLEAN} (ver mensagens acima no log)" >> "${BACKUP_DIR}/backup.log" 2>&1
    fi
    rm -f "${TMP_SQL}"
  done

  # Remover backups mais antigos que RETENCAO_DIAS
  find "${BACKUP_DIR}" -maxdepth 1 -name "backup-*.sql.gz" -mtime +${RETENCAO_DIAS} -delete 2>/dev/null
  unset PGPASSWORD
  return 0
}

# Agendar no cron e configurar ambiente
agendar() {
  banner
  printf "${WHITE} >> Backup diário do banco Alta Performance (Docker)${WHITE}\n"
  echo

  if [ ! -f "${ARQUIVO_VARIAVEIS}" ]; then
    printf "${RED} >> Arquivo ${ARQUIVO_VARIAVEIS} não encontrado.${WHITE}\n"
    printf "${YELLOW} >> Execute primeiro uma instalação (normal ou Alta Performance).${WHITE}\n"
    sleep 3
    return 1
  fi

  # shellcheck source=/dev/null
  source "${ARQUIVO_VARIAVEIS}" 2>/dev/null
  if [ "${ALTA_PERFORMANCE}" != "1" ]; then
    printf "${RED} >> Esta opção é apenas para instalação em modo Alta Performance.${WHITE}\n"
    printf "${YELLOW} >> No seu VARIAVEIS_INSTALACAO, ALTA_PERFORMANCE não está definido como 1.${WHITE}\n"
    sleep 3
    return 1
  fi

  if [ -z "${empresa}" ] || [ -z "${senha_deploy}" ]; then
    printf "${RED} >> Variáveis empresa ou senha_deploy não encontradas em VARIAVEIS_INSTALACAO.${WHITE}\n"
    sleep 3
    return 1
  fi

  command -v psql >/dev/null 2>&1 || {
    printf "${WHITE} >> Instalando postgresql-client...${WHITE}\n"
    apt-get update -qq && apt-get install -y postgresql-client >/dev/null 2>&1
  }
  command -v psql >/dev/null 2>&1 || {
    printf "${RED} >> Não foi possível instalar postgresql-client.${WHITE}\n"
    sleep 3
    return 1
  }

  mkdir -p "${BACKUP_DIR}"
  chown deploy:deploy "${BACKUP_DIR}"
  printf "${GREEN} >> Pasta de backup: ${BACKUP_DIR}${WHITE}\n"

  export PGPASSWORD="${senha_deploy}"
  if ! psql -h "${DB_HOST}" -p "${DB_PORT}" -U "${empresa}" -d postgres -c "SELECT 1;" >/dev/null 2>&1; then
    unset PGPASSWORD
    printf "${RED} >> Não foi possível conectar ao Postgres em ${DB_HOST}:${DB_PORT}.${WHITE}\n"
    printf "${YELLOW} >> Verifique se o stack Alta Performance está rodando (docker ps).${WHITE}\n"
    sleep 3
    return 1
  fi
  unset PGPASSWORD
  printf "${GREEN} >> Conexão com Postgres Docker OK.${WHITE}\n"
  echo

  # Perguntar quantos dias reter os backups
  RETENCAO_ATUAL=$(ler_retencao_dias)
  printf "${WHITE} >> Quantos dias deseja reter os backups? (padrão ${RETENCAO_ATUAL}):${WHITE}\n"
  read -p "> " retenciao_digitado
  retenciao_digitado=${retenciao_digitado:-$RETENCAO_ATUAL}
  if [[ "${retenciao_digitado}" =~ ^[0-9]+$ ]] && [ "${retenciao_digitado}" -ge 1 ]; then
    RETENCAO_DIAS=${retenciao_digitado}
    mkdir -p "${BACKUP_DIR}"
    echo "${RETENCAO_DIAS}" > "${CONFIG_RETENCAO}"
    chown deploy:deploy "${CONFIG_RETENCAO}" 2>/dev/null
    printf "${GREEN} >> Retenção configurada: ${RETENCAO_DIAS} dias.${WHITE}\n"
  else
    RETENCAO_DIAS=${RETENCAO_ATUAL}
    printf "${YELLOW} >> Valor inválido. Usando retenção atual: ${RETENCAO_DIAS} dias.${WHITE}\n"
  fi
  echo

  CRON_LINHA="0 2 * * * ${CRON_SCRIPT_PATH} --backup >> ${BACKUP_DIR}/backup.log 2>&1"
  if crontab -l 2>/dev/null | grep -q "agendar_backup_bd_docker.sh --backup"; then
    printf "${YELLOW} >> Backup diário já está agendado no cron (2h da manhã).${WHITE}\n"
  else
    (crontab -l 2>/dev/null; echo "${CRON_LINHA}") | crontab -
    printf "${GREEN} >> Backup diário agendado no cron (todos os dias às 2h).${WHITE}\n"
  fi
  printf "${WHITE} >> Arquivos: um .sql.gz por banco em ${BACKUP_DIR}${WHITE}\n"
  printf "${WHITE} >> Retenção: ${RETENCAO_DIAS} dias (arquivo ${CONFIG_RETENCAO})${WHITE}\n"
  echo
  printf "${WHITE} >> Deseja executar o backup agora? (S/N):${WHITE}\n"
  read -p "> " exec_now
  exec_now=$(echo "${exec_now}" | tr '[:upper:]' '[:lower:]')
  if [ "${exec_now}" = "s" ]; then
    printf "${WHITE} >> Executando backup...${WHITE}\n"
    executar_backup
    printf "${GREEN} >> Backup concluído. Verifique ${BACKUP_DIR}${WHITE}\n"
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
