#!/bin/bash

# Aplica perfil de tuning ao PostgreSQL nativo (instalação padrão, não Alta Performance).

GREEN='\033[1;32m'
BLUE='\033[1;34m'
WHITE='\033[1;37m'
RED='\033[1;31m'
YELLOW='\033[1;33m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALADOR_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
ARQUIVO_VARIAVEIS="${INSTALADOR_DIR}/VARIAVEIS_INSTALACAO"
CONF_BASENAME="99-instalador-postgres-tuning.conf"

if [ "$EUID" -ne 0 ]; then
  echo
  printf "${WHITE} >> Este script precisa ser executado como root.${WHITE}\n"
  exit 1
fi

banner() {
  printf " ${BLUE}\n"
  printf "  Otimizar Postgres Nativo\n"
  printf " ${WHITE}\n"
}

detectar_pg_main_dir() {
  local versao
  if [ ! -d /etc/postgresql ]; then
    return 1
  fi
  while IFS= read -r versao; do
    [ -z "${versao}" ] && continue
    if [ -d "/etc/postgresql/${versao}/main" ]; then
      echo "/etc/postgresql/${versao}/main"
      return 0
    fi
  done < <(ls -1 /etc/postgresql 2>/dev/null | sort -V -r)
  return 1
}

validar_instalacao_nativa() {
  if [ -f "${ARQUIVO_VARIAVEIS}" ]; then
    # shellcheck source=/dev/null
    source "${ARQUIVO_VARIAVEIS}" 2>/dev/null
    if [ "${ALTA_PERFORMANCE}" = "1" ]; then
      printf "${RED} >> Esta opção é apenas para instalação nativa (PostgreSQL no sistema).${WHITE}\n"
      printf "${YELLOW} >> No seu VARIAVEIS_INSTALACAO, ALTA_PERFORMANCE está definido como 1.${WHITE}\n"
      sleep 3
      return 1
    fi
  fi

  if ! command -v psql >/dev/null 2>&1; then
    printf "${RED} >> PostgreSQL nativo não encontrado (psql ausente).${WHITE}\n"
    sleep 3
    return 1
  fi

  if ! systemctl is-active --quiet postgresql 2>/dev/null; then
    printf "${RED} >> Serviço PostgreSQL nativo não está ativo.${WHITE}\n"
    printf "${YELLOW} >> Verifique com: systemctl status postgresql${WHITE}\n"
    sleep 3
    return 1
  fi

  return 0
}

aplicar_perfil() {
  local perfil="$1"
  local pg_main_dir="$2"
  local conf_dir="${pg_main_dir}/conf.d"
  local conf_file="${conf_dir}/${CONF_BASENAME}"
  local backup_file=""
  local perfil_descricao=""
  local shared_buffers=""
  local effective_cache_size=""
  local work_mem=""
  local maintenance_work_mem=""
  local max_connections=""
  local max_worker_processes=""
  local max_parallel_workers=""
  local max_parallel_workers_per_gather=""
  local max_parallel_maintenance_workers=""
  local max_wal_size=""
  local min_wal_size=""
  local autovacuum_max_workers=""

  case "${perfil}" in
    1)
      perfil_descricao="VPS 4 Core x 8 GB RAM"
      shared_buffers="1536MB"
      effective_cache_size="4GB"
      work_mem="8MB"
      maintenance_work_mem="256MB"
      max_connections="100"
      max_worker_processes="4"
      max_parallel_workers="3"
      max_parallel_workers_per_gather="2"
      max_parallel_maintenance_workers="2"
      max_wal_size="2GB"
      min_wal_size="256MB"
      autovacuum_max_workers="2"
      ;;
    2)
      perfil_descricao="VPS 6 Core x 16 GB RAM"
      shared_buffers="3GB"
      effective_cache_size="8GB"
      work_mem="12MB"
      maintenance_work_mem="512MB"
      max_connections="100"
      max_worker_processes="6"
      max_parallel_workers="4"
      max_parallel_workers_per_gather="2"
      max_parallel_maintenance_workers="2"
      max_wal_size="2GB"
      min_wal_size="512MB"
      autovacuum_max_workers="2"
      ;;
    3)
      perfil_descricao="VPS 8 Core x 32 GB RAM"
      shared_buffers="6GB"
      effective_cache_size="16GB"
      work_mem="16MB"
      maintenance_work_mem="1GB"
      max_connections="120"
      max_worker_processes="8"
      max_parallel_workers="6"
      max_parallel_workers_per_gather="3"
      max_parallel_maintenance_workers="3"
      max_wal_size="4GB"
      min_wal_size="1GB"
      autovacuum_max_workers="3"
      ;;
    *)
      return 1
      ;;
  esac

  mkdir -p "${conf_dir}"
  if [ -f "${conf_file}" ]; then
    backup_file="${conf_file}.bak.$(date +%Y%m%d_%H%M%S)"
    cp -a "${conf_file}" "${backup_file}"
    printf "${YELLOW} >> Backup da configuração anterior: ${backup_file}${WHITE}\n"
  fi

  cat > "${conf_file}" <<EOF
# Gerado por tools/otimizar_postgres_nativo.sh em $(date '+%Y-%m-%d %H:%M:%S')
# Perfil: ${perfil_descricao}
# Ajustes para VPS compartilhada com aplicação, Redis, Nginx e demais serviços.

shared_buffers = ${shared_buffers}
effective_cache_size = ${effective_cache_size}
work_mem = ${work_mem}
maintenance_work_mem = ${maintenance_work_mem}
huge_pages = try

max_connections = ${max_connections}

max_wal_size = ${max_wal_size}
min_wal_size = ${min_wal_size}
checkpoint_completion_target = 0.9
wal_compression = on

max_worker_processes = ${max_worker_processes}
max_parallel_workers = ${max_parallel_workers}
max_parallel_workers_per_gather = ${max_parallel_workers_per_gather}
max_parallel_maintenance_workers = ${max_parallel_maintenance_workers}

random_page_cost = 1.1
effective_io_concurrency = 200
maintenance_io_concurrency = 50

autovacuum_max_workers = ${autovacuum_max_workers}
autovacuum_naptime = 60s
autovacuum_vacuum_scale_factor = 0.05
autovacuum_analyze_scale_factor = 0.02

default_statistics_target = 100

log_checkpoints = on
log_lock_waits = on
log_temp_files = 10MB
log_min_duration_statement = 500ms
EOF

  chown root:postgres "${conf_file}" 2>/dev/null || true
  chmod 640 "${conf_file}" 2>/dev/null || true

  printf "${GREEN} >> Perfil aplicado: ${perfil_descricao}${WHITE}\n"
  printf "${GREEN} >> Arquivo criado: ${conf_file}${WHITE}\n"
  printf "${WHITE} >> Reiniciando PostgreSQL para carregar memória e paralelismo...${WHITE}\n"
  if systemctl restart postgresql; then
    sleep 2
    if systemctl is-active --quiet postgresql; then
      printf "${GREEN} >> PostgreSQL reiniciado com sucesso.${WHITE}\n"
    else
      printf "${RED} >> PostgreSQL não subiu após o restart. Verifique: journalctl -u postgresql -n 50${WHITE}\n"
      return 1
    fi
  else
    printf "${RED} >> Falha ao reiniciar o PostgreSQL.${WHITE}\n"
    return 1
  fi

  return 0
}

main() {
  local pg_main_dir=""
  local conf_dir=""
  local opcao=""

  banner
  printf "${WHITE} >> Esta ferramenta adiciona melhorias ao PostgreSQL nativo para melhor desempenho.${WHITE}\n"
  printf "${WHITE} >> Será criado (ou atualizado) um arquivo em conf.d do PostgreSQL, com backup da versão anterior.${WHITE}\n"
  echo

  if ! validar_instalacao_nativa; then
    return 1
  fi

  pg_main_dir=$(detectar_pg_main_dir) || {
    printf "${RED} >> Não foi possível localizar /etc/postgresql/<versão>/main.${WHITE}\n"
    sleep 3
    return 1
  }
  conf_dir="${pg_main_dir}/conf.d"
  printf "${GREEN} >> Diretório de configuração: ${pg_main_dir}${WHITE}\n"
  printf "${GREEN} >> Arquivo de tuning: ${conf_dir}/${CONF_BASENAME}${WHITE}\n"
  echo

  printf "${WHITE} >> Escolha o perfil do servidor:${WHITE}\n"
  echo
  printf "   [${BLUE}1${WHITE}] VPS com 4 Core x 8 GB RAM\n"
  printf "   [${BLUE}2${WHITE}] VPS com 6 Core x 16 GB RAM\n"
  printf "   [${BLUE}3${WHITE}] VPS com 8 Core x 32 GB RAM\n"
  printf "   [${BLUE}0${WHITE}] Cancelar\n"
  echo
  read -p "> " opcao

  case "${opcao}" in
    1|2|3)
      echo
      aplicar_perfil "${opcao}" "${pg_main_dir}"
      ;;
    0)
      printf "${YELLOW} >> Operação cancelada.${WHITE}\n"
      sleep 2
      return 0
      ;;
    *)
      printf "${RED} >> Opção inválida.${WHITE}\n"
      sleep 2
      return 1
      ;;
  esac

  echo
  sleep 2
  return 0
}

main "$@"
