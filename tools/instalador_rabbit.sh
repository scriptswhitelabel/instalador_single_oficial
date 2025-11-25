#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_DATA_FILE="${INSTALL_DATA_FILE:-${SCRIPT_DIR}/../VARIAVEIS_INSTALACAO}"

RABBIT_IMAGE="${RABBIT_IMAGE:-rabbitmq:3.13-management}"
RABBIT_CONTAINER="${RABBIT_CONTAINER:-multiflow-rabbitmq}"
RABBIT_VOLUME="${RABBIT_VOLUME:-rabbitmq_volume}"
HOST_DATA_PATH="${HOST_DATA_PATH:-}"
RABBIT_USER="${RABBIT_USER:-}"
RABBIT_PASS="${RABBIT_PASS:-}"
CREDS_SOURCE=""

info() { printf "\033[1;34m[INFO]\033[0m %s\n" "$1"; }
success() { printf "\033[1;32m[SUCCESS]\033[0m %s\n" "$1"; }
warn() { printf "\033[1;33m[WARN]\033[0m %s\n" "$1"; }
error() { printf "\033[1;31m[ERROR]\033[0m %s\n" "$1"; exit 1; }

generate_password() {
  tr -dc 'A-Za-z0-9' </dev/urandom | head -c 24
}

slugify() {
  local input="${1:-empresa}"
  input=$(echo "$input" | tr '[:upper:]' '[:lower:]')
  input=$(echo "$input" | tr -cs 'a-z0-9-' '-')
  input="${input%%-}"
  input="${input##-}"
  if [ -z "$input" ]; then
    input="empresa"
  fi
  echo "$input"
}

ensure_root() {
  if [ "${EUID:-$(id -u)}" -ne 0 ]; then
    error "Este instalador precisa ser executado como root."
  fi
}

ensure_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    error "Comando '$1' não encontrado. Instale-o antes de continuar."
  fi
}

load_install_vars() {
  if [ -f "$INSTALL_DATA_FILE" ]; then
    info "Carregando credenciais do instalador em ${INSTALL_DATA_FILE}..."
    # shellcheck disable=SC1090
    source "$INSTALL_DATA_FILE"
    local loaded=false
    if [ -z "$RABBIT_USER" ] && [ -n "${empresa:-}" ]; then
      RABBIT_USER="$empresa"
      loaded=true
    fi
    if [ -z "$RABBIT_PASS" ] && [ -n "${senha_deploy:-}" ]; then
      RABBIT_PASS="$senha_deploy"
      loaded=true
    fi
    if [ "$loaded" = true ]; then
      CREDS_SOURCE="VARIAVEIS_INSTALACAO"
    fi
  else
    warn "Arquivo ${INSTALL_DATA_FILE} não encontrado. Informe as credenciais manualmente."
  fi

  RABBIT_USER="${RABBIT_USER:-multiflow}"
  RABBIT_PASS="${RABBIT_PASS:-$(generate_password)}"

  if [ -z "${HOST_DATA_PATH}" ]; then
    local slug_source="${empresa:-$RABBIT_USER}"
    local safe_slug
    safe_slug="$(slugify "$slug_source")"
    HOST_DATA_PATH="/container/rabbitmq-${safe_slug}"
  fi
}

prompt_credentials() {
  if [ "$CREDS_SOURCE" = "VARIAVEIS_INSTALACAO" ]; then
    info "Usando as credenciais coletadas na instalação (${RABBIT_USER}/********)."
    return
  fi

  read -rp "Informe o usuário do RabbitMQ [${RABBIT_USER}]: " input_user || true
  RABBIT_USER="${input_user:-$RABBIT_USER}"

  read -rp "Informe a senha do RabbitMQ (deixe vazio para gerar automaticamente): " input_pass || true
  if [ -n "${input_pass:-}" ]; then
    RABBIT_PASS="$input_pass"
  else
    warn "Senha gerada automaticamente: ${RABBIT_PASS}"
  fi
}

prepare_host_path() {
  info "Garantindo diretório de dados em ${HOST_DATA_PATH}..."
  mkdir -p "${HOST_DATA_PATH}"
  chmod 700 "${HOST_DATA_PATH}"
  success "Diretório pronto."
}

create_bind_volume() {
  info "Criando volume '${RABBIT_VOLUME}' apontando para ${HOST_DATA_PATH}..."
  if docker volume inspect "${RABBIT_VOLUME}" >/dev/null 2>&1; then
    warn "Volume '${RABBIT_VOLUME}' já existe. Ele será reutilizado."
    return
  fi

  docker volume create \
    --driver local \
    --opt type=none \
    --opt o=bind \
    --opt device="${HOST_DATA_PATH}" \
    "${RABBIT_VOLUME}" >/dev/null
  success "Volume criado."
}

stop_existing_container() {
  if docker ps -a --format '{{.Names}}' | grep -q "^${RABBIT_CONTAINER}$"; then
    warn "Contêiner ${RABBIT_CONTAINER} já existe. Parando e removendo..."
    docker stop "${RABBIT_CONTAINER}" >/dev/null || true
    docker rm "${RABBIT_CONTAINER}" >/dev/null || true
  fi
}

run_rabbit() {
  info "Iniciando contêiner ${RABBIT_CONTAINER}..."
  docker run -d \
    --name "${RABBIT_CONTAINER}" \
    --restart unless-stopped \
    -e "RABBITMQ_DEFAULT_USER=${RABBIT_USER}" \
    -e "RABBITMQ_DEFAULT_PASS=${RABBIT_PASS}" \
    -e TZ=America/Sao_Paulo \
    -v "${RABBIT_VOLUME}:/var/lib/rabbitmq" \
    -p 5672:5672 \
    -p 15672:15672 \
    "${RABBIT_IMAGE}" >/dev/null
  success "RabbitMQ em execução."
}

print_summary() {
  cat <<EOF

==========================================
RabbitMQ instalado com sucesso!
------------------------------------------
Container : ${RABBIT_CONTAINER}
Imagem    : ${RABBIT_IMAGE}
Volume    : ${RABBIT_VOLUME} -> ${HOST_DATA_PATH}
Portas    : 5672 (AMQP), 15672 (Painel)
Usuário   : ${RABBIT_USER}
Senha     : ${RABBIT_PASS}
Painel    : http://SEU_IP:15672
==========================================

EOF
}

main() {
  ensure_root
  ensure_command docker
  load_install_vars
  prompt_credentials
  prepare_host_path
  create_bind_volume
  stop_existing_container
  run_rabbit
  print_summary
}

main "$@"

