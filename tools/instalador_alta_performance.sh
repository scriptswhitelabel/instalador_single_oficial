#!/bin/bash

# Instalação em modo Alta Performance: Redis, PostgreSQL e PgBouncer via Docker
# Não instala Postgres nem Redis nativos no sistema.

GREEN='\033[1;32m'
BLUE='\033[1;34m'
WHITE='\033[1;37m'
RED='\033[1;31m'
YELLOW='\033[1;33m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALADOR_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
STACK_TEMPLATE="${SCRIPT_DIR}/stack_altaPerformance"
ARQUIVO_VARIAVEIS="${INSTALADOR_DIR}/VARIAVEIS_INSTALACAO"
MODE_FILE="${INSTALADOR_DIR}/ALTA_PERFORMANCE_MODE"

if [ "$EUID" -ne 0 ]; then
  echo
  printf "${WHITE} >> Este script precisa ser executado como root ou com privilégios de superusuário.${WHITE}\n"
  echo
  sleep 2
  exit 1
fi

banner() {
  printf " ${BLUE}"
  printf "\n\n"
  printf "██╗███╗   ██╗███████╗████████╗ █████╗ ██╗     ██╗     ███████╗██╗    ██╗██╗\n"
  printf "██║████╗  ██║██╔════╝╚══██╔══╝██╔══██╗██║     ██║     ██╔════╝██║    ██║██║\n"
  printf "██║██╔██╗ ██║███████    ██║   ███████║██║     ██║     ███████╗██║ █╗ ██║██║\n"
  printf "██║██║╚██╗██║╚════██║   ██║   ██╔══██║██║     ██║     ╚════██║██║███╗██║██║\n"
  printf "██║██║ ╚████║███████║   ██║   ██║  ██║███████╗███████╗███████║╚███╔███╔╝██║\n"
  printf "╚═╝╚═╝  ╚═══╝╚══════╝   ╚═╝   ╚═╝  ╚═╝╚══════╝╚══════╝╚══════╝ ╚══╝╚══╝ ╚═╝\n"
  printf "${WHITE}\n"
}

# Carrega empresa e senha_deploy do arquivo de variáveis se existir
carregar_variaveis_se_existir() {
  if [ -f "${ARQUIVO_VARIAVEIS}" ]; then
    # shellcheck source=/dev/null
    source "${ARQUIVO_VARIAVEIS}" 2>/dev/null
    if [ -n "${empresa}" ] && [ -n "${senha_deploy}" ]; then
      printf "${GREEN} >> Variáveis carregadas de ${ARQUIVO_VARIAVEIS} (empresa: ${empresa})${WHITE}\n"
      return 0
    fi
  fi
  return 1
}

# Gera o docker-compose a partir do template com as substituições
gerar_stack() {
  local empresa="$1"
  local senha_deploy="$2"
  local stack_dest="${INSTALADOR_DIR}/docker-compose-alta-performance-${empresa}.yml"

  if [ ! -f "${STACK_TEMPLATE}" ]; then
    printf "${RED} >> ERRO: Template não encontrado: ${STACK_TEMPLATE}${WHITE}\n"
    exit 1
  fi

  # Escapar caracteres especiais para sed (senha pode ter &, /, etc.)
  senha_escaped=$(echo "${senha_deploy}" | sed 's/[&/\]/\\&/g')

  sed -e "s|/container-web/|/container-${empresa}/|g" \
      -e "s|POSTGRES_USER: root|POSTGRES_USER: ${empresa}|g" \
      -e "s|POSTGRES_PASSWORD: deploy2024|POSTGRES_PASSWORD: ${senha_escaped}|g" \
      -e "s|POSTGRES_DB: web|POSTGRES_DB: ${empresa}|g" \
      -e "s|DB_USER: root|DB_USER: ${empresa}|g" \
      -e "s|DB_PASSWORD: \"deploy2024\"|DB_PASSWORD: \"${senha_escaped}\"|g" \
      -e "s|redis_containerv3|redis_${empresa}|g" \
      -e "s|postgres_containerv3|postgres_${empresa}|g" \
      -e "s|pgbouncer_containerv3|pgbouncer_${empresa}|g" \
      -e "s|-U root -d web|-U ${empresa} -d ${empresa}|g" \
      -e "s|  - web$|  - ${empresa}|g" \
      -e "s|^  web:$|  ${empresa}:|g" \
      "${STACK_TEMPLATE}" > "${stack_dest}"

  echo "${stack_dest}"
}

# Instala Docker se não estiver instalado
instalar_docker_se_preciso() {
  if command -v docker >/dev/null 2>&1; then
    printf "${GREEN} >> Docker já instalado.${WHITE}\n"
    return 0
  fi
  printf "${WHITE} >> Instalando Docker...${WHITE}\n"
  curl -fsSL https://get.docker.com | sh
  systemctl enable docker
  systemctl start docker
  sleep 2
}

# Instala Docker Compose se não estiver instalado
instalar_compose_se_preciso() {
  if command -v docker-compose >/dev/null 2>&1 || docker compose version >/dev/null 2>&1; then
    printf "${GREEN} >> Docker Compose já disponível.${WHITE}\n"
    return 0
  fi
  printf "${WHITE} >> Instalando Docker Compose...${WHITE}\n"
  local compose_ver="v2.24.0"
  curl -sL "https://github.com/docker/compose/releases/download/${compose_ver}/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
  chmod +x /usr/local/bin/docker-compose
  sleep 1
}

main() {
  banner

  printf "${YELLOW}══════════════════════════════════════════════════════════════════${WHITE}\n"
  printf "${YELLOW}   INSTALAÇÃO EM MODO ALTA PERFORMANCE${WHITE}\n"
  printf "${YELLOW}══════════════════════════════════════════════════════════════════${WHITE}\n"
  echo
  printf "${WHITE}   Esta opção irá instalar:${WHITE}\n"
  printf "${WHITE}   • Redis em Alta Performance (container)${WHITE}\n"
  printf "${WHITE}   • Banco de dados PostgreSQL em Alta Performance (container)${WHITE}\n"
  printf "${WHITE}   • PgBouncer para pool de conexões${WHITE}\n"
  echo
  printf "${YELLOW}   O instalador ${RED}NÃO${YELLOW} irá instalar Postgres nem Redis nativos no sistema.${WHITE}\n"
  printf "${WHITE}   Tudo rodará via Docker (containers).${WHITE}\n"
  echo
  printf "${WHITE}   Requisitos recomendados do servidor para operar bem:${WHITE}\n"
  printf "${WHITE}   • Processador: 4 a 6 CORE${WHITE}\n"
  printf "${WHITE}   • Memória RAM: 12 a 16 GB${WHITE}\n"
  echo
  printf "${YELLOW}══════════════════════════════════════════════════════════════════${WHITE}\n"
  echo
  printf "${WHITE}   Deseja continuar? (S/N):${WHITE}\n"
  read -p "> " confirma
  confirma=$(echo "${confirma}" | tr '[:lower:]' '[:upper:]')
  if [ "${confirma}" != "S" ]; then
    printf "${GREEN} >> Operação cancelada.${WHITE}\n"
    sleep 2
    exit 0
  fi

  # Coletar todas as informações da instalação (igual ao instalador normal)
  printf "${WHITE} >> Serão solicitadas todas as informações da instalação (DNS, URLs, email, proxy, portas, token, repositório, etc.).${WHITE}\n"
  echo
  printf "${GREEN} >> Pressione Enter para iniciar...${WHITE}\n"
  read -r

  echo "ALTA_PERFORMANCE=1" > "${MODE_FILE}"
  cd "${INSTALADOR_DIR}" || exit 1
  if ! bash "${INSTALADOR_DIR}/instalador_single.sh" --coletar-variaveis-alta-performance; then
    printf "${RED} >> Coleta de variáveis interrompida ou falhou.${WHITE}\n"
    rm -f "${MODE_FILE}"
    sleep 3
    exit 1
  fi

  # Carregar empresa e senha (já salvos em VARIAVEIS_INSTALACAO)
  # shellcheck source=/dev/null
  source "${ARQUIVO_VARIAVEIS}" 2>/dev/null
  if [ -z "${empresa}" ] || [ -z "${senha_deploy}" ]; then
    printf "${RED} >> ERRO: empresa ou senha_deploy não encontrados em ${ARQUIVO_VARIAVEIS}.${WHITE}\n"
    sleep 3
    exit 1
  fi

  printf "${WHITE} >> Gerando stack Docker (empresa: ${empresa})...${WHITE}\n"
  stack_file=$(gerar_stack "${empresa}" "${senha_deploy}")
  if [ -z "${stack_file}" ] || [ ! -f "${stack_file}" ]; then
    printf "${RED} >> Falha ao gerar arquivo do stack.${WHITE}\n"
    exit 1
  fi
  printf "${GREEN} >> Stack gerado: ${stack_file}${WHITE}\n"

  # Diretórios de dados
  mkdir -p "/container-${empresa}/redis"
  mkdir -p "/container-${empresa}/banco"
  printf "${GREEN} >> Diretórios de dados criados em /container-${empresa}/${WHITE}\n"

  instalar_docker_se_preciso
  instalar_compose_se_preciso

  printf "${WHITE} >> Subindo containers (Redis, Postgres, PgBouncer)...${WHITE}\n"
  cd "${INSTALADOR_DIR}" || exit 1
  if docker-compose -f "${stack_file}" up -d 2>/dev/null || docker compose -f "${stack_file}" up -d; then
    printf "${GREEN} >> Stack em execução.${WHITE}\n"
  else
    printf "${RED} >> Erro ao subir os containers. Verifique os logs.${WHITE}\n"
    exit 1
  fi

  # Aguardar Postgres/PgBouncer ficarem saudáveis
  printf "${WHITE} >> Aguardando serviços ficarem prontos...${WHITE}\n"
  sleep 15

  # Gravar modo alta performance para o instalador principal
  cat > "${MODE_FILE}" <<EOF
ALTA_PERFORMANCE=1
empresa=${empresa}
senha_deploy=${senha_deploy}
EOF
  printf "${GREEN} >> Modo Alta Performance registrado.${WHITE}\n"
  echo
  printf "${WHITE} >> Iniciando instalação automaticamente (sem pausas)...${WHITE}\n"
  echo

  cd "${INSTALADOR_DIR}" || exit 1
  if [ ! -f "${INSTALADOR_DIR}/instalador_single.sh" ]; then
    printf "${RED} >> instalador_single.sh não encontrado.${WHITE}\n"
    exit 1
  fi

  if ! bash "${INSTALADOR_DIR}/instalador_single.sh" --executar-instalacao-alta-performance; then
    printf "${RED} >> A instalação encontrou erros. Abrindo menu para verificação.${WHITE}\n"
    sleep 3
  fi

  printf "${GREEN} >> Pressione Enter para abrir o Menu Principal.${WHITE}\n"
  read -r
  exec bash "${INSTALADOR_DIR}/instalador_single.sh"
}

main "$@"
