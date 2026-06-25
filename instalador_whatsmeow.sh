#!/bin/bash

GREEN='\033[1;32m'
BLUE='\033[1;34m'
WHITE='\033[1;37m'
RED='\033[1;31m'
YELLOW='\033[1;33m'

# Variaveis Padrão
ARCH=$(uname -m)
UBUNTU_VERSION=$(lsb_release -sr)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALADOR_DIR="$SCRIPT_DIR"
# shellcheck source=tools/instalar_docker_compartilhado.sh
source "${INSTALADOR_DIR}/tools/instalar_docker_compartilhado.sh"
ARQUIVO_VARIAVEIS=""
ip_atual=$(curl -s http://checkip.amazonaws.com)
default_wuzapi_port=8090
default_rabbitmq_amqp_port=5672
default_rabbitmq_mgmt_port=15672
WUZAPI_COMPOSE_PROJECT=""
WHATSMEOW_COMPOSE_LEGACY=0
wuzapi_rabbit_amqp_port="${default_rabbitmq_amqp_port}"
wuzapi_rabbit_mgmt_port="${default_rabbitmq_mgmt_port}"

if [ "$EUID" -ne 0 ]; then
  echo
  printf "${WHITE} >> Este script precisa ser executado como root ${RED}ou com privilégios de superusuário${WHITE}.\n"
  echo
  sleep 2
  exit 1
fi

# Função para manipular erros e encerrar o script
trata_erro() {
  printf "${RED}Erro encontrado na etapa $1. Encerrando o script.${WHITE}\n"
  exit 1
}

# Banner
banner() {
  clear
  printf "${BLUE}"
  echo "╔══════════════════════════════════════════════════════════════╗"
  echo "║                  INSTALADOR WHATSMEOW                        ║"
  echo "║                                                              ║"
  echo "║                    MultiFlow System                          ║"
  echo "╚══════════════════════════════════════════════════════════════╝"
  printf "${WHITE}"
  echo
}

# Aviso sobre versão PRO
aviso_versao_pro() {
  banner
  printf "${YELLOW}══════════════════════════════════════════════════════════════════${WHITE}\n"
  printf "${YELLOW}⚠️  AVISO IMPORTANTE:${WHITE}\n"
  echo
  printf "${WHITE}   O WhatsMeow só funciona na versão do MultiFlow PRO,${WHITE}\n"
  printf "${WHITE}   a partir da versão ${BLUE}6.4.4${WHITE}.\n"
  echo
  printf "${YELLOW}══════════════════════════════════════════════════════════════════${WHITE}\n"
  echo
  sleep 3
}

detectar_instancias_instaladas() {
  local instancias=()
  local nomes_empresas=()
  local temp_empresa=""

  if [ -f "${INSTALADOR_DIR}/VARIAVEIS_INSTALACAO" ]; then
    local empresa_original="${empresa:-}"
    # shellcheck source=/dev/null
    source "${INSTALADOR_DIR}/VARIAVEIS_INSTALACAO" 2>/dev/null
    temp_empresa="${empresa:-}"
    if [ -n "${temp_empresa}" ] && [ -d "/home/deploy/${temp_empresa}/backend" ]; then
      instancias+=("${INSTALADOR_DIR}/VARIAVEIS_INSTALACAO")
      nomes_empresas+=("${temp_empresa}")
    fi
    empresa="${empresa_original}"
  fi

  shopt -s nullglob
  for arquivo_instancia in "${INSTALADOR_DIR}"/VARIAVEIS_INSTALACAO_INSTANCIA_*; do
    [ -f "$arquivo_instancia" ] || continue
    local empresa_original="${empresa:-}"
    # shellcheck source=/dev/null
    source "$arquivo_instancia" 2>/dev/null
    temp_empresa="${empresa:-}"
    if [ -n "${temp_empresa}" ] && [ -d "/home/deploy/${temp_empresa}/backend" ]; then
      instancias+=("$arquivo_instancia")
      nomes_empresas+=("${temp_empresa}")
    fi
    empresa="${empresa_original}"
  done
  shopt -u nullglob

  declare -g INSTANCIAS_DETECTADAS=("${instancias[@]}")
  declare -g NOMES_EMPRESAS_DETECTADAS=("${nomes_empresas[@]}")
}

selecionar_instancia_whatsmeow() {
  banner
  printf "${WHITE} >> Em qual instância o WhatsMeow (WuzAPI) será instalado?\n\n"
  detectar_instancias_instaladas
  local total_instancias=${#INSTANCIAS_DETECTADAS[@]}

  if [ "$total_instancias" -eq 0 ]; then
    printf "${RED} >> Nenhuma instância detectada. Instale o MultiFlow antes.${WHITE}\n"
    sleep 3
    exit 1
  elif [ "$total_instancias" -eq 1 ]; then
    ARQUIVO_VARIAVEIS="${INSTANCIAS_DETECTADAS[0]}"
    # shellcheck source=/dev/null
    source "$ARQUIVO_VARIAVEIS"
    printf "${GREEN} >> Instância: ${BLUE}${empresa}${WHITE}\n\n"
    sleep 1
    return 0
  fi

  printf "${WHITE}═══════════════════════════════════════════════════════════\n"
  printf "  INSTÂNCIAS\n"
  printf "═══════════════════════════════════════════════════════════${WHITE}\n\n"
  local index=1
  for i in "${!NOMES_EMPRESAS_DETECTADAS[@]}"; do
    local empresa_nome="${NOMES_EMPRESAS_DETECTADAS[$i]}"
    local arquivo_instancia="${INSTANCIAS_DETECTADAS[$i]}"
    local empresa_original="${empresa:-}"
    # shellcheck source=/dev/null
    source "$arquivo_instancia" 2>/dev/null
    local wz_port="${wuzapi_port:-}"
    empresa="${empresa_original}"
    printf "  [${BLUE}%s${WHITE}] %s\n" "$index" "$empresa_nome"
    if [ -d "/home/deploy/${empresa_nome}/wuzapi" ]; then
      printf "      WhatsMeow: ${YELLOW}já instalado${WHITE}"
      [ -n "$wz_port" ] && printf " (porta ${wz_port})"
      echo
    else
      printf "      WhatsMeow: ${GREEN}não instalado${WHITE}\n"
    fi
    echo
    index=$((index + 1))
  done
  printf "${YELLOW} >> Escolha a instância (1-%s):${WHITE}\n" "$total_instancias"
  read -r escolha_instancia
  if ! [[ "$escolha_instancia" =~ ^[0-9]+$ ]] || [ "$escolha_instancia" -lt 1 ] || [ "$escolha_instancia" -gt "$total_instancias" ]; then
    printf "${RED} >> Opção inválida.${WHITE}\n"
    exit 1
  fi
  ARQUIVO_VARIAVEIS="${INSTANCIAS_DETECTADAS[$((escolha_instancia - 1))]}"
  # shellcheck source=/dev/null
  source "$ARQUIVO_VARIAVEIS"
  printf "${GREEN} >> Instância selecionada: ${BLUE}${empresa}${WHITE}\n\n"
  sleep 1
}

# Só instâncias que já têm WhatsMeow instalado (pasta wuzapi + compose).
selecionar_instancia_whatsmeow_atualizar() {
  banner
  printf "${WHITE} >> Qual instância atualizar (WhatsMeow / WuzAPI)?\n\n"
  detectar_instancias_instaladas
  local instancias_wz=()
  local nomes_wz=()
  local i arquivo_inst empresa_nome

  for i in "${!INSTANCIAS_DETECTADAS[@]}"; do
    arquivo_inst="${INSTANCIAS_DETECTADAS[$i]}"
    empresa_nome="${NOMES_EMPRESAS_DETECTADAS[$i]}"
    [ -d "/home/deploy/${empresa_nome}/wuzapi" ] && [ -f "/home/deploy/${empresa_nome}/wuzapi/docker-compose.yml" ] || continue
    instancias_wz+=("$arquivo_inst")
    nomes_wz+=("$empresa_nome")
  done

  if [ ${#instancias_wz[@]} -eq 0 ]; then
    printf "${RED} >> Nenhuma instância com WhatsMeow instalado (/home/deploy/<empresa>/wuzapi).${WHITE}\n"
    printf "${YELLOW} >> Use a opção 3 do menu para instalar primeiro.${WHITE}\n"
    sleep 3
    exit 1
  fi

  if [ ${#instancias_wz[@]} -eq 1 ]; then
    ARQUIVO_VARIAVEIS="${instancias_wz[0]}"
    # shellcheck source=/dev/null
    source "$ARQUIVO_VARIAVEIS"
    printf "${GREEN} >> Instância: ${BLUE}${empresa}${WHITE}\n\n"
    sleep 1
    return 0
  fi

  printf "${WHITE}═══════════════════════════════════════════════════════════\n"
  printf "  INSTÂNCIAS COM WHATSMEOW\n"
  printf "═══════════════════════════════════════════════════════════${WHITE}\n\n"
  local index=1
  for i in "${!nomes_wz[@]}"; do
    empresa_nome="${nomes_wz[$i]}"
    # shellcheck source=/dev/null
    source "${instancias_wz[$i]}" 2>/dev/null
    local wz_port="${wuzapi_port:-}"
    printf "  [${BLUE}%s${WHITE}] %s" "$index" "$empresa_nome"
    [ -n "$wz_port" ] && printf " ${WHITE}(porta host ${wz_port})"
    echo
    index=$((index + 1))
  done
  printf "${YELLOW} >> Escolha (1-%s):${WHITE}\n" "${#instancias_wz[@]}"
  read -r escolha_instancia
  if ! [[ "$escolha_instancia" =~ ^[0-9]+$ ]] || [ "$escolha_instancia" -lt 1 ] || [ "$escolha_instancia" -gt ${#instancias_wz[@]} ]; then
    printf "${RED} >> Opção inválida.${WHITE}\n"
    exit 1
  fi
  ARQUIVO_VARIAVEIS="${instancias_wz[$((escolha_instancia - 1))]}"
  # shellcheck source=/dev/null
  source "$ARQUIVO_VARIAVEIS"
  printf "${GREEN} >> Instância selecionada: ${BLUE}${empresa}${WHITE}\n\n"
  sleep 1
}

# Carregar variáveis
carregar_variaveis() {
  if [ -n "$ARQUIVO_VARIAVEIS" ] && [ -f "$ARQUIVO_VARIAVEIS" ]; then
    # shellcheck source=/dev/null
    source "$ARQUIVO_VARIAVEIS"
  elif [ -f "${INSTALADOR_DIR}/VARIAVEIS_INSTALACAO" ]; then
    ARQUIVO_VARIAVEIS="${INSTALADOR_DIR}/VARIAVEIS_INSTALACAO"
    # shellcheck source=/dev/null
    source "$ARQUIVO_VARIAVEIS"
  else
    empresa="multiflow"
    nome_titulo="MultiFlow"
  fi
  WUZAPI_COMPOSE_PROJECT="wuzapi_${empresa}"
  whatsmeow_detectar_compose_project
}

# Containers legados wuzapi-* no servidor (podem pertencer a outra instância).
whatsmeow_servidor_tem_stack_legada() {
  local names_all="$1"
  echo "$names_all" | grep -qE '^wuzapi-(db|rabbitmq|wuzapi-server)(-|$)'
}

# Porta WuzAPI registrada para esta instância (.env ou VARIAVEIS), não o default genérico.
whatsmeow_porta_registrada_instancia() {
  local wuz_dir="/home/deploy/${empresa}/wuzapi"
  local p=""

  if [ -f "${wuz_dir}/.env" ]; then
    p=$(grep -m1 '^WUZAPI_PORT=' "${wuz_dir}/.env" 2>/dev/null | cut -d '=' -f2- | tr -d '\r')
  fi
  if [ -z "$p" ] && [ -n "${ARQUIVO_VARIAVEIS:-}" ] && [ -f "$ARQUIVO_VARIAVEIS" ]; then
    p=$(grep -m1 '^wuzapi_port=' "$ARQUIVO_VARIAVEIS" 2>/dev/null | cut -d '=' -f2- | tr -d '\r')
  fi
  [ -n "$p" ] && printf '%s' "$p"
}

# Stack legada "wuzapi" pertence à instância atual (não a outra no mesmo servidor).
whatsmeow_instancia_usa_stack_legada() {
  local wuz_dir="/home/deploy/${empresa}/wuzapi"
  local names_all nm porta_reg holder

  [ -d "$wuz_dir" ] || return 1

  names_all=$(docker ps -a --format '{{.Names}}' 2>/dev/null || true)
  whatsmeow_servidor_tem_stack_legada "$names_all" || return 1

  nm=""
  if [ -f "${wuz_dir}/docker-compose.yml" ]; then
    nm=$(grep -m1 '^name:' "${wuz_dir}/docker-compose.yml" 2>/dev/null | sed -E 's/^name:[[:space:]]*//; s/["'"'"']//g; s/[[:space:]]+$//')
    if [ -z "$nm" ] || [ "$nm" = "wuzapi" ]; then
      return 0
    fi
  fi

  porta_reg=$(whatsmeow_porta_registrada_instancia)
  [ -n "$porta_reg" ] || return 1

  holder=$(docker ps --filter "publish=${porta_reg}" --format '{{.Names}}' 2>/dev/null | head -1)
  case "$holder" in
    wuzapi-wuzapi-server-*|wuzapi-server|wuzapi-wuzapi-server) return 0 ;;
  esac
  return 1
}

# Detecta o projeto Docker Compose já em uso (evita duplicar stack na atualização).
# Instalações antigas: projeto "wuzapi" (nome da pasta). Novas: "wuzapi_<empresa>".
# A stack legada só é considerada se pertencer à instância selecionada.
whatsmeow_detectar_compose_project() {
  local wuz_dir="/home/deploy/${empresa}/wuzapi"
  local proj_novo="wuzapi_${empresa}"
  local port_host="${wuzapi_port:-$default_wuzapi_port}"
  local holder names_all porta_reg
  WHATSMEOW_COMPOSE_LEGACY=0

  if [ -f "${wuz_dir}/.env" ]; then
    local p_env
    p_env=$(grep -m1 '^WUZAPI_PORT=' "${wuz_dir}/.env" 2>/dev/null | cut -d '=' -f2- | tr -d '\r')
    [ -n "$p_env" ] && port_host="$p_env"
  fi

  names_all=$(docker ps -a --format '{{.Names}}' 2>/dev/null || true)
  porta_reg=$(whatsmeow_porta_registrada_instancia)

  if echo "$names_all" | grep -qE "^${proj_novo}-(db|rabbitmq|server|wuzapi-server)(-|$)"; then
    WUZAPI_COMPOSE_PROJECT="${proj_novo}"
    printf "${GREEN} >> Stack Docker existente: projeto ${BLUE}${proj_novo}${GREEN}.${WHITE}\n\n"
    return 0
  fi

  if whatsmeow_instancia_usa_stack_legada; then
    WUZAPI_COMPOSE_PROJECT="wuzapi"
    WHATSMEOW_COMPOSE_LEGACY=1
    printf "${GREEN} >> Stack Docker existente: projeto ${BLUE}wuzapi${GREEN} (instalação legada desta instância).${WHITE}\n\n"
    return 0
  fi

  if [ -n "$porta_reg" ] && [ "$port_host" = "$porta_reg" ]; then
    holder=$(docker ps --filter "publish=${port_host}" --format '{{.Names}}' 2>/dev/null | head -1)
    if [ -n "$holder" ]; then
      case "$holder" in
        ${proj_novo}-wuzapi-server-*|${proj_novo}-server)
          WUZAPI_COMPOSE_PROJECT="${proj_novo}"
          printf "${GREEN} >> Stack na porta ${port_host}: projeto ${BLUE}${proj_novo}${GREEN}.${WHITE}\n\n"
          return 0
          ;;
      esac
    fi
  fi

  if [ -f "${wuz_dir}/docker-compose.yml" ]; then
    local nm
    nm=$(grep -m1 '^name:' "${wuz_dir}/docker-compose.yml" 2>/dev/null | sed -E 's/^name:[[:space:]]*//; s/["'"'"']//g; s/[[:space:]]+$//')
    if [ -n "$nm" ] && [ "$nm" != "${proj_novo}" ]; then
      WUZAPI_COMPOSE_PROJECT="$nm"
      [ "$nm" = "wuzapi" ] && WHATSMEOW_COMPOSE_LEGACY=1
      printf "${GREEN} >> Projeto no docker-compose.yml: ${BLUE}${nm}${GREEN}.${WHITE}\n\n"
      return 0
    fi
    if [ "$nm" = "${proj_novo}" ] && whatsmeow_instancia_usa_stack_legada; then
      WUZAPI_COMPOSE_PROJECT="wuzapi"
      WHATSMEOW_COMPOSE_LEGACY=1
      printf "${YELLOW} >> docker-compose.yml com ${proj_novo}, mas stack legada ${BLUE}wuzapi-*${YELLOW} é desta instância — usando projeto ${BLUE}wuzapi${YELLOW}.${WHITE}\n\n"
      return 0
    fi
    [ -n "$nm" ] && WUZAPI_COMPOSE_PROJECT="$nm" && [ "$nm" = "wuzapi" ] && WHATSMEOW_COMPOSE_LEGACY=1 && return 0
  fi

  WUZAPI_COMPOSE_PROJECT="${proj_novo}"
  if [ ! -d "$wuz_dir" ] && whatsmeow_servidor_tem_stack_legada "$names_all"; then
    printf "${GREEN} >> Nova instância: projeto ${BLUE}${proj_novo}${GREEN} (stack legada de outra instância não será alterada).${WHITE}\n\n"
  fi
}

# Remove stack duplicada criada por atualização com projeto errado (ex.: wuzapi_multiflow junto de wuzapi).
whatsmeow_remover_stack_orfao() {
  local orfao="wuzapi_${empresa}"
  [ "$orfao" = "$WUZAPI_COMPOSE_PROJECT" ] && return 0
  if ! docker ps -a --format '{{.Names}}' 2>/dev/null | grep -qE "^${orfao}(-|$)"; then
    return 0
  fi
  # Não remover órfã se a stack legada wuzapi ainda está em uso
  if [ "$WUZAPI_COMPOSE_PROJECT" = "wuzapi" ] && docker ps -a --format '{{.Names}}' 2>/dev/null | grep -qE '^wuzapi-(db|rabbitmq|wuzapi-server)'; then
    printf "${YELLOW} >> Limpando stack duplicada ${orfao} (a stack ativa é wuzapi)...${WHITE}\n"
  fi
  local docker_compose_cmd="docker compose"
  docker compose version >/dev/null 2>&1 || docker_compose_cmd="docker-compose"
  printf "${YELLOW} >> Removendo stack órfã ${orfao} (containers duplicados da atualização)...${WHITE}\n"
  (cd "/home/deploy/${empresa}/wuzapi" && $docker_compose_cmd -p "$orfao" down 2>/dev/null) || true
}

whatsmeow_coletar_portas_em_uso() {
  WHATSMEOW_PORTAS_EM_USO=()
  WHATSMEOW_PORTAS_RESUMO=()
  local env_file emp port
  for env_file in /home/deploy/*/wuzapi/.env; do
    [ -f "$env_file" ] || continue
    emp=$(basename "$(dirname "$(dirname "$env_file")")")
    [ "$emp" = "${empresa:-}" ] && continue
    port=$(grep -m1 '^WUZAPI_PORT=' "$env_file" 2>/dev/null | cut -d '=' -f2- | tr -d '\r')
    [ -z "$port" ] && continue
    WHATSMEOW_PORTAS_EM_USO+=("$port")
    WHATSMEOW_PORTAS_RESUMO+=("${emp}:${port}")
  done
  local arq
  for arq in "${INSTALADOR_DIR}"/VARIAVEIS_INSTALACAO "${INSTALADOR_DIR}"/VARIAVEIS_INSTALACAO_INSTANCIA_*; do
    [ -f "$arq" ] || continue
    [ "$arq" = "$ARQUIVO_VARIAVEIS" ] && continue
    port=$(grep -m1 '^wuzapi_port=' "$arq" 2>/dev/null | cut -d '=' -f2- | tr -d '\r')
    [ -z "$port" ] && continue
    emp=$(grep -m1 '^empresa=' "$arq" 2>/dev/null | cut -d '=' -f2- | tr -d '\r')
    [[ " ${WHATSMEOW_PORTAS_EM_USO[*]} " == *" $port "* ]] && continue
    WHATSMEOW_PORTAS_EM_USO+=("$port")
    WHATSMEOW_PORTAS_RESUMO+=("${emp:-?}:${port}")
  done
}

whatsmeow_porta_em_listen() {
  local port="$1"
  if command -v ss >/dev/null 2>&1; then
    ss -tlnH 2>/dev/null | grep -qE ":${port}([[:space:]]|$)"
    return $?
  fi
  return 1
}

whatsmeow_porta_indisponivel() {
  local port="$1"
  local p
  for p in "${WHATSMEOW_PORTAS_EM_USO[@]}"; do
    [ "$p" = "$port" ] && return 0
  done
  whatsmeow_porta_em_listen "$port"
}

whatsmeow_proxima_porta_livre() {
  local p="${default_wuzapi_port}"
  while [ "$p" -le 65535 ] && whatsmeow_porta_indisponivel "$p"; do
    p=$((p + 1))
  done
  printf '%s' "$p"
}

whatsmeow_docker_publica_porta_host() {
  local port="$1"
  command -v docker >/dev/null 2>&1 || return 1
  docker ps --format '{{.Ports}}' 2>/dev/null | grep -qE "(0\.0\.0\.0|127\.0\.0\.1|\[::\]):${port}->"
}

whatsmeow_coletar_portas_rabbit_registradas() {
  WHATSMEOW_RABBIT_AMQP_USADAS=()
  WHATSMEOW_RABBIT_MGMT_USADAS=()
  local env_file emp amqp mgmt
  for env_file in /home/deploy/*/wuzapi/.env; do
    [ -f "$env_file" ] || continue
    emp=$(basename "$(dirname "$(dirname "$env_file")")")
    [ "$emp" = "${empresa:-}" ] && continue
    amqp=$(grep -m1 '^RABBITMQ_AMQP_PORT=' "$env_file" 2>/dev/null | cut -d '=' -f2- | tr -d '\r')
    mgmt=$(grep -m1 '^RABBITMQ_MGMT_PORT=' "$env_file" 2>/dev/null | cut -d '=' -f2- | tr -d '\r')
    [ -n "$amqp" ] && WHATSMEOW_RABBIT_AMQP_USADAS+=("$amqp")
    [ -n "$mgmt" ] && WHATSMEOW_RABBIT_MGMT_USADAS+=("$mgmt")
  done
}

whatsmeow_rabbit_porta_na_lista() {
  local port="$1"
  shift
  local p
  for p in "$@"; do
    [ "$p" = "$port" ] && return 0
  done
  return 1
}

whatsmeow_rabbit_portas_host_ocupadas() {
  local amqp="$1"
  local mgmt="$2"
  whatsmeow_porta_em_listen "$amqp" && return 0
  whatsmeow_porta_em_listen "$mgmt" && return 0
  whatsmeow_docker_publica_porta_host "$amqp" && return 0
  whatsmeow_docker_publica_porta_host "$mgmt" && return 0
  whatsmeow_rabbit_porta_na_lista "$amqp" "${WHATSMEOW_RABBIT_AMQP_USADAS[@]}" && return 0
  whatsmeow_rabbit_porta_na_lista "$mgmt" "${WHATSMEOW_RABBIT_MGMT_USADAS[@]}" && return 0
  return 1
}

whatsmeow_ha_rabbitmq_rodando() {
  if command -v docker >/dev/null 2>&1; then
    if docker ps --format '{{.Image}}' 2>/dev/null | grep -qi 'rabbitmq'; then
      return 0
    fi
  fi
  whatsmeow_porta_em_listen "$default_rabbitmq_amqp_port" && return 0
  whatsmeow_porta_em_listen "$default_rabbitmq_mgmt_port" && return 0
  return 1
}

# Escolhe portas AMQP/management no host (5672/15672, 5673/15673, ...) sem conflito
whatsmeow_definir_portas_rabbit() {
  banner
  printf "${WHITE} >> Definindo portas do RabbitMQ no host (evitar conflito entre instâncias)...\n"
  echo

  # shellcheck source=/dev/null
  [ -n "$ARQUIVO_VARIAVEIS" ] && [ -f "$ARQUIVO_VARIAVEIS" ] && source "$ARQUIVO_VARIAVEIS"

  if [ -f "/home/deploy/${empresa}/wuzapi/.env" ]; then
    local amqp_ex mgmt_ex
    amqp_ex=$(grep -m1 '^RABBITMQ_AMQP_PORT=' "/home/deploy/${empresa}/wuzapi/.env" 2>/dev/null | cut -d '=' -f2- | tr -d '\r')
    mgmt_ex=$(grep -m1 '^RABBITMQ_MGMT_PORT=' "/home/deploy/${empresa}/wuzapi/.env" 2>/dev/null | cut -d '=' -f2- | tr -d '\r')
    if [ -n "$amqp_ex" ] && [ -n "$mgmt_ex" ]; then
      wuzapi_rabbit_amqp_port="$amqp_ex"
      wuzapi_rabbit_mgmt_port="$mgmt_ex"
    fi
  fi

  if [ -z "${wuzapi_rabbit_amqp_port}" ] || [ -z "${wuzapi_rabbit_mgmt_port}" ]; then
    wuzapi_rabbit_amqp_port="${wuzapi_rabbit_amqp_port:-$default_rabbitmq_amqp_port}"
    wuzapi_rabbit_mgmt_port="${wuzapi_rabbit_mgmt_port:-$default_rabbitmq_mgmt_port}"
  fi

  whatsmeow_coletar_portas_rabbit_registradas
  if ! whatsmeow_rabbit_portas_host_ocupadas "$wuzapi_rabbit_amqp_port" "$wuzapi_rabbit_mgmt_port"; then
    printf "${GREEN} >> Portas RabbitMQ: AMQP ${wuzapi_rabbit_amqp_port} | Management ${wuzapi_rabbit_mgmt_port}${WHITE}\n\n"
    salvar_variavel_instancia "wuzapi_rabbit_amqp_port" "${wuzapi_rabbit_amqp_port}"
    salvar_variavel_instancia "wuzapi_rabbit_mgmt_port" "${wuzapi_rabbit_mgmt_port}"
    sleep 1
    return 0
  fi

  printf "${YELLOW} >> Portas ${wuzapi_rabbit_amqp_port}/${wuzapi_rabbit_mgmt_port} em uso — buscando par livre...${WHITE}\n"
  whatsmeow_coletar_portas_rabbit_registradas
  wuzapi_rabbit_amqp_port=$default_rabbitmq_amqp_port
  wuzapi_rabbit_mgmt_port=$default_rabbitmq_mgmt_port

  if whatsmeow_ha_rabbitmq_rodando; then
    printf "${YELLOW} >> RabbitMQ já detectado no servidor (container ou porta ${default_rabbitmq_amqp_port}/${default_rabbitmq_mgmt_port}).${WHITE}\n"
  fi

  while whatsmeow_rabbit_portas_host_ocupadas "$wuzapi_rabbit_amqp_port" "$wuzapi_rabbit_mgmt_port"; do
    printf "${WHITE} >> Portas ${wuzapi_rabbit_amqp_port}/${wuzapi_rabbit_mgmt_port} ocupadas — tentando próximo par...${WHITE}\n"
    wuzapi_rabbit_amqp_port=$((wuzapi_rabbit_amqp_port + 1))
    wuzapi_rabbit_mgmt_port=$((wuzapi_rabbit_mgmt_port + 1))
  done

  salvar_variavel_instancia "wuzapi_rabbit_amqp_port" "${wuzapi_rabbit_amqp_port}"
  salvar_variavel_instancia "wuzapi_rabbit_mgmt_port" "${wuzapi_rabbit_mgmt_port}"

  printf "${GREEN} >> RabbitMQ no host: AMQP ${BLUE}${wuzapi_rabbit_amqp_port}${GREEN} → container 5672 | Management ${BLUE}${wuzapi_rabbit_mgmt_port}${GREEN} → 15672${WHITE}\n"
  echo
  sleep 1
}

salvar_variavel_instancia() {
  local chave="$1"
  local valor="$2"
  [ -z "$ARQUIVO_VARIAVEIS" ] || [ ! -f "$ARQUIVO_VARIAVEIS" ] && return 0
  if grep -q "^${chave}=" "$ARQUIVO_VARIAVEIS" 2>/dev/null; then
    sed -i "s|^${chave}=.*|${chave}=${valor}|" "$ARQUIVO_VARIAVEIS"
  else
    echo "${chave}=${valor}" >>"$ARQUIVO_VARIAVEIS"
  fi
}

# Verificar se WhatsMeow já está instalado
verificar_instalacao_existente() {
  banner
  printf "${WHITE} >> Verificando se o WhatsMeow já está instalado...\n"
  echo
  
  if [ -d "/home/deploy/${empresa}/wuzapi" ]; then
    printf "${YELLOW}⚠️  AVISO: A pasta wuzapi já foi localizada dentro da instalação.${WHITE}\n"
    printf "${YELLOW}   Pasta encontrada: /home/deploy/${empresa}/wuzapi${WHITE}\n"
    echo
    printf "${WHITE}   Deseja reinstalar o WhatsMeow? (s/n):${WHITE}\n"
    printf "${YELLOW}   ⚠️  ATENÇÃO: Isso irá remover a instalação atual e todos os dados!${WHITE}\n"
    echo
    read -p "> " resposta
    
    if [ "$resposta" != "s" ] && [ "$resposta" != "S" ]; then
      printf "${YELLOW} >> Instalação cancelada pelo usuário.${WHITE}\n"
      echo
      exit 0
    fi
    
    printf "${WHITE} >> Iniciando reinstalação...${WHITE}\n"
    echo
    
    # Parar e remover containers Docker se existirem (projeto detectado: legado ou wuzapi_<empresa>)
    if [ -f "/home/deploy/${empresa}/wuzapi/docker-compose.yml" ]; then
      printf "${WHITE} >> Parando containers Docker do WhatsMeow (projeto ${WUZAPI_COMPOSE_PROJECT:-wuzapi_${empresa}})...${WHITE}\n"
      cd /home/deploy/${empresa}/wuzapi
      local proj="${WUZAPI_COMPOSE_PROJECT:-wuzapi_${empresa}}"
      docker compose -p "$proj" down -v 2>/dev/null || docker-compose -p "$proj" down -v 2>/dev/null || true
      echo
      sleep 2
    fi
    
    # Remover a pasta wuzapi
    printf "${WHITE} >> Removendo pasta wuzapi existente...${WHITE}\n"
    rm -rf /home/deploy/${empresa}/wuzapi
    WUZAPI_COMPOSE_PROJECT="wuzapi_${empresa}"
    WHATSMEOW_COMPOSE_LEGACY=0
    printf "${GREEN} >> Pasta removida com sucesso!${WHITE}\n"
    echo
    sleep 2
    
    printf "${GREEN} >> Prosseguindo com a instalação...${WHITE}\n"
    echo
    sleep 2
  else
    printf "${GREEN} >> WhatsMeow não encontrado. Prosseguindo com a instalação...${WHITE}\n"
    echo
    sleep 2
  fi
}

# Solicitar subdomínio da API WhatsMeow
solicitar_subdominio_whatsmeow() {
  banner
  printf "${WHITE} >> Insira o subdomínio da API WhatsMeow:${WHITE}\n"
  echo
  read -p "> " subdominio_whatsmeow
  echo
  printf "   ${WHITE}Subdomínio API WhatsMeow: ---->> ${YELLOW}${subdominio_whatsmeow}${WHITE}\n"
  salvar_variavel_instancia "subdominio_whatsmeow" "${subdominio_whatsmeow}"
  sleep 2
}

# Solicitar porta da API WhatsMeow
solicitar_porta_whatsmeow() {
  banner
  whatsmeow_coletar_portas_em_uso
  printf "${WHITE} >> Porta HTTP do WuzAPI (proxy Nginx → 127.0.0.1:PORTA)\n"
  echo
  if [ ${#WHATSMEOW_PORTAS_RESUMO[@]} -gt 0 ]; then
    printf "${YELLOW} >> Portas já usadas por outra(s) instância(s):${WHITE}\n"
    local item
    for item in "${WHATSMEOW_PORTAS_RESUMO[@]}"; do
      printf "      ${BLUE}%s${WHITE}\n" "$item"
    done
    echo
  fi

  local sugestao
  sugestao=$(whatsmeow_proxima_porta_livre)
  local porta_escolhida=""
  while true; do
    printf "${WHITE} >> Porta para ${BLUE}${empresa}${WHITE} [padrão: ${sugestao}]: \n"
    read -r porta_escolhida
    porta_escolhida="${porta_escolhida:-$sugestao}"
    if ! [[ "$porta_escolhida" =~ ^[0-9]+$ ]] || [ "$porta_escolhida" -lt 1024 ] || [ "$porta_escolhida" -gt 65535 ]; then
      printf "${RED} >> Porta inválida (1024-65535).${WHITE}\n\n"
      continue
    fi
    if whatsmeow_porta_indisponivel "$porta_escolhida"; then
      printf "${RED} >> Porta ${porta_escolhida} indisponível.${WHITE}\n\n"
      sugestao=$(whatsmeow_proxima_porta_livre)
      continue
    fi
    break
  done

  wuzapi_port="$porta_escolhida"
  printf "${GREEN} >> Porta selecionada: ${wuzapi_port}${WHITE}\n"
  salvar_variavel_instancia "wuzapi_port" "${wuzapi_port}"
  echo
  sleep 2
}

# Validação de DNS
verificar_dns_whatsmeow() {
  banner
  printf "${WHITE} >> Verificando o DNS do subdomínio da API WhatsMeow...\n"
  echo
  sleep 2
  sudo apt-get install dnsutils -y >/dev/null 2>&1

  # Remover https:// se presente
  local domain=$(echo "${subdominio_whatsmeow}" | sed 's|https\?://||')
  local resolved_ip
  local cname_target

  cname_target=$(dig +short CNAME ${domain} 2>/dev/null)

  if [ -n "${cname_target}" ]; then
    resolved_ip=$(dig +short ${cname_target} 2>/dev/null)
  else
    resolved_ip=$(dig +short ${domain} 2>/dev/null)
  fi

  if [ "${resolved_ip}" != "${ip_atual}" ]; then
    echo "O domínio ${domain} (resolvido para ${resolved_ip}) não está apontando para o IP público atual (${ip_atual})."
    echo
    printf "${RED} >> Verifique o apontamento de DNS do subdomínio: ${subdominio_whatsmeow}${WHITE}\n"
    echo
    printf "${WHITE} >> Deseja continuar a instalação mesmo assim? (S/N): ${WHITE}\n"
    echo
    read -p "> " continuar_dns
    continuar_dns=$(echo "${continuar_dns}" | tr '[:lower:]' '[:upper:]')
    echo
    if [ "${continuar_dns}" != "S" ]; then
      printf "${GREEN} >> Instalação cancelada.${WHITE}\n"
      sleep 2
      exit 0
    fi
    printf "${YELLOW} >> Continuando a instalação mesmo com DNS não configurado corretamente...${WHITE}\n"
    sleep 2
  else
    echo "Subdomínio ${domain} está apontando corretamente para o IP público da VPS."
    sleep 2
  fi
  echo
  printf "${WHITE} >> Continuando...\n"
  sleep 2
  echo
}

# Configurar Nginx para API WhatsMeow
configurar_nginx_whatsmeow() {
  banner
  printf "${WHITE} >> Configurando Nginx para API WhatsMeow...\n"
  echo
  {
    # Remover https:// ou http:// se presente
    whatsmeow_hostname=$(echo "${subdominio_whatsmeow}" | sed 's|https\?://||')
    sudo su - root <<EOF
cat > /etc/nginx/sites-available/${empresa}-whatsmeow << END
upstream api_whatsmeow_${empresa} {
        server 127.0.0.1:${wuzapi_port};
        keepalive 32;
    }
server {
  server_name ${whatsmeow_hostname};
  location / {
    proxy_pass http://api_whatsmeow_${empresa};
    proxy_http_version 1.1;
    proxy_set_header Upgrade \\\$http_upgrade;
    proxy_set_header Connection 'upgrade';
    proxy_set_header Host \\\$host;
    proxy_set_header X-Real-IP \\\$remote_addr;
    proxy_set_header X-Forwarded-Proto \\\$scheme;
    proxy_set_header X-Forwarded-For \\\$proxy_add_x_forwarded_for;
    proxy_cache_bypass \\\$http_upgrade;
    proxy_buffering on;
  }
}
END
ln -s /etc/nginx/sites-available/${empresa}-whatsmeow /etc/nginx/sites-enabled 2>/dev/null || true
EOF

    sleep 2

    banner
    printf "${WHITE} >> Emitindo SSL do ${subdominio_whatsmeow}...\n"
    echo
    # Remover https:// ou http:// se presente
    whatsmeow_domain=$(echo "${subdominio_whatsmeow}" | sed 's|https\?://||')
    sudo su - root <<EOF
    certbot -m ${email_deploy} \
            --nginx \
            --agree-tos \
            -n \
            -d ${whatsmeow_domain}
EOF

    sleep 2
  } || trata_erro "configurar_nginx_whatsmeow"
}

# Clonar repositório wuzapi
clonar_repositorio_wuzapi() {
  banner
  printf "${WHITE} >> Clonando repositório wuzapi...\n"
  echo
  
  {
    cd /home/deploy/${empresa}
    
    if git clone https://github.com/asternic/wuzapi >/dev/null 2>&1; then
      printf "${GREEN} >> Repositório wuzapi clonado com sucesso!${WHITE}\n"
      sleep 2
    else
      printf "${RED}❌ ERRO: Falha ao clonar o repositório wuzapi.${WHITE}\n"
      printf "${RED}   Verifique sua conexão com a internet e tente novamente.${WHITE}\n"
      exit 1
    fi
  } || trata_erro "clonar_repositorio_wuzapi"
}

# Corrigir Dockerfile do wuzapi
corrigir_dockerfile_wuzapi() {
  banner
  printf "${WHITE} >> Verificando e corrigindo Dockerfile do wuzapi...\n"
  echo
  
  {
    local dockerfile_path="/home/deploy/${empresa}/wuzapi/Dockerfile"
    
    if [ ! -f "$dockerfile_path" ]; then
      printf "${YELLOW}⚠️  Dockerfile não encontrado.${WHITE}\n"
      printf "${RED}   Erro: Dockerfile não existe no repositório clonado.${WHITE}\n"
      exit 1
    fi
    
    # Criar backup
    cp "$dockerfile_path" "${dockerfile_path}.backup" 2>/dev/null || true
    
    printf "${WHITE} >> Verificando Dockerfile existente...${WHITE}\n"
    
    # Remover tentativas de modificar /etc/resolv.conf (não funciona durante build)
    if grep -q "nameserver 8.8.8.8" "$dockerfile_path" 2>/dev/null || grep -q "/etc/resolv.conf" "$dockerfile_path" 2>/dev/null; then
      printf "${WHITE} >> Removendo tentativas de modificar /etc/resolv.conf (não funciona durante build)...${WHITE}\n"
      # Remover linhas que tentam modificar resolv.conf
      sed -i '/RUN echo.*nameserver.*resolv.conf/d' "$dockerfile_path" 2>/dev/null
      sed -i '/Configure DNS for apt-get/d' "$dockerfile_path" 2>/dev/null
      # Remover linhas vazias duplicadas
      sed -i '/^$/N;/^\n$/D' "$dockerfile_path" 2>/dev/null
      printf "${GREEN} >> Dockerfile limpo! DNS será configurado via docker-compose.yml${WHITE}\n"
    fi
    
    printf "${WHITE} >> DNS será configurado através do docker-compose.yml e Docker daemon${WHITE}\n"
    
    # Verificar se há problemas com apt-get (Ubuntu/Debian)
    if grep -q "apt-get install" "$dockerfile_path" 2>/dev/null; then
      printf "${WHITE} >> Corrigindo lista de pacotes apt-get...${WHITE}\n"
      
      # Usar awk para processar o arquivo de forma mais confiável
      awk '
        BEGIN { in_section = 0; section_started = 0 }
        
        /# Install runtime dependencies/ || (/RUN apt-get update/ && /apt-get install/) {
          if (!section_started) {
            print "# Install runtime dependencies"
            print "RUN apt-get update && apt-get install -y --no-install-recommends \\"
            print "    ca-certificates \\"
            print "    netcat-openbsd \\"
            print "    postgresql-client \\"
            print "    openssl \\"
            print "    curl \\"
            print "    ffmpeg \\"
            print "    tzdata \\"
            print "    && rm -rf /var/lib/apt/lists/*"
            in_section = 1
            section_started = 1
            next
          }
        }
        
        in_section == 1 {
          # Continuar pulando linhas até encontrar rm -rf ou próxima instrução
          if (/rm -rf.*apt\/lists/ || /rm -rf.*var\/lib\/apt\/lists/) {
            in_section = 0
            next
          }
          # Se encontrar uma nova instrução (começa com letra maiúscula e não é continuação)
          if (/^[A-Z]/ && !/^RUN/ && !/^#/ && !/^[[:space:]]*\\/) {
            in_section = 0
            print
            next
          }
          # Se encontrar outra instrução RUN ou comentário
          if (/^RUN/ || /^#/) {
            in_section = 0
            print
            next
          }
          # Pular linhas de continuação (que terminam com \)
          if (/[[:space:]]*\\[[:space:]]*$/) {
            next
          }
          # Se chegou aqui e não é continuação, sair da seção
          in_section = 0
          print
          next
        }
        
        { print }
      ' "$dockerfile_path" > "${dockerfile_path}.tmp" && mv "${dockerfile_path}.tmp" "$dockerfile_path"
      
      if [ $? -eq 0 ]; then
        printf "${GREEN} >> Dockerfile corrigido com sucesso!${WHITE}\n"
      else
        printf "${RED} >> Erro ao corrigir Dockerfile.${WHITE}\n"
        printf "${YELLOW} >> Tentando método alternativo...${WHITE}\n"
        
        # Método alternativo: usar perl para substituição
        perl -i -pe '
          if (/# Install runtime dependencies/ || (/RUN apt-get update/ && /apt-get install/)) {
            $_ = "# Install runtime dependencies\nRUN apt-get update && apt-get install -y --no-install-recommends \\\n    ca-certificates \\\n    netcat-openbsd \\\n    postgresql-client \\\n    openssl \\\n    curl \\\n    ffmpeg \\\n    tzdata \\\n    && rm -rf /var/lib/apt/lists/*\n";
            $skip = 1;
          } elsif ($skip) {
            if (/rm -rf.*apt\/lists/ || /^[A-Z]/) {
              $skip = 0;
              $_ = "" if /rm -rf.*apt\/lists/;
            } else {
              $_ = "";
            }
          }
        ' "$dockerfile_path" 2>/dev/null
        
        if [ $? -eq 0 ]; then
          printf "${GREEN} >> Dockerfile corrigido usando método alternativo!${WHITE}\n"
        else
          printf "${RED} >> Erro: Não foi possível corrigir o Dockerfile automaticamente.${WHITE}\n"
          printf "${YELLOW} >> Você pode corrigir manualmente o arquivo: ${dockerfile_path}${WHITE}\n"
        fi
      fi
      
    elif grep -q "apk add" "$dockerfile_path" 2>/dev/null; then
      printf "${WHITE} >> Dockerfile usa Alpine Linux (apk). Verificando formatação...${WHITE}\n"
      # Corrigir quebras de linha se necessário
      sed -i 's/\\[[:space:]]*$/ \\/g' "$dockerfile_path"
      printf "${GREEN} >> Dockerfile verificado!${WHITE}\n"
    else
      printf "${YELLOW} >> Dockerfile não usa apt-get nem apk. Mantendo como está.${WHITE}\n"
    fi
    
    sleep 2
  } || trata_erro "corrigir_dockerfile_wuzapi"
}

# Gerar chaves de criptografia
gerar_chaves_criptografia() {
  # Gerar chave de criptografia de 32 bytes (64 caracteres hex)
  WUZAPI_GLOBAL_ENCRYPTION_KEY=$(openssl rand -hex 32)
  
  # Gerar chave HMAC de pelo menos 32 caracteres
  WUZAPI_GLOBAL_HMAC_KEY=$(openssl rand -base64 32 | tr -d '\n' | head -c 40)
}

# Configurar arquivo .env do wuzapi
configurar_env_wuzapi() {
  banner
  printf "${WHITE} >> Configurando arquivo .env do wuzapi...\n"
  echo
  {
    # shellcheck source=/dev/null
    source "$ARQUIVO_VARIAVEIS"
    
    gerar_chaves_criptografia
    
    subdominio_limpo=$(echo "${subdominio_whatsmeow}" | sed 's|https\?://||')
    local db_user="wuzapi_${empresa}"
    db_user="${db_user//[^a-zA-Z0-9_]}"
    local db_name="$db_user"
    
    # Criar arquivo .env
    cat > /home/deploy/${empresa}/wuzapi/.env <<EOF
# .env
# Server Configuration
WUZAPI_PORT=${wuzapi_port}
WUZAPI_ADDRESS=0.0.0.0

# Token for WuzAPI Admin
WUZAPI_ADMIN_TOKEN=${senha_deploy}

# Encryption key for sensitive data (32 bytes for AES-256)
WUZAPI_GLOBAL_ENCRYPTION_KEY=${WUZAPI_GLOBAL_ENCRYPTION_KEY}

# Global HMAC Key for webhook signing (minimum 32 characters)
WUZAPI_GLOBAL_HMAC_KEY=${WUZAPI_GLOBAL_HMAC_KEY}

# Global webhook URL
WUZAPI_GLOBAL_WEBHOOK=https://${subdominio_limpo}/webhook

# "json" or "form" for the default
WEBHOOK_FORMAT=json

# WuzAPI Session Configuration
# Chrome no Windows — nome em Dispositivos vinculados (WhatsApp)
SESSION_DEVICE_NAME=Windows - Wuz
SESSION_PLATFORM_TYPE=CHROME

# Database configuration
DB_USER=${db_user}
DB_PASSWORD=${senha_deploy}
DB_NAME=${db_name}
DB_HOST=db
DB_PORT=5432
DB_SSLMODE=false
TZ=America/Sao_Paulo

# RabbitMQ (host publicado; URL interna usa hostname rabbitmq:5672 no compose)
RABBITMQ_AMQP_PORT=${wuzapi_rabbit_amqp_port}
RABBITMQ_MGMT_PORT=${wuzapi_rabbit_mgmt_port}
RABBITMQ_URL=amqp://${db_user}:${senha_deploy}@rabbitmq:5672/%2F
RABBITMQ_QUEUE=whatsapp_events_${empresa}
EOF

    printf "${GREEN} >> Arquivo .env do wuzapi configurado com sucesso!${WHITE}\n"
    sleep 2
  } || trata_erro "configurar_env_wuzapi"
}

# Na atualização: reutiliza portas do RabbitMQ já publicadas pela stack (evita 5673+ e stack nova).
whatsmeow_portas_rabbit_da_stack_atual() {
  local rmq_name amqp_host mgmt_host
  rmq_name=$(docker ps -a --format '{{.Names}}' 2>/dev/null | grep -E "^(${WUZAPI_COMPOSE_PROJECT}-rabbitmq|wuzapi-rabbitmq)-" | head -1)
  [ -z "$rmq_name" ] && return 1
  amqp_host=$(docker port "$rmq_name" 5672/tcp 2>/dev/null | head -1 | sed -n 's/.*:\([0-9]*\)$/\1/p')
  mgmt_host=$(docker port "$rmq_name" 15672/tcp 2>/dev/null | head -1 | sed -n 's/.*:\([0-9]*\)$/\1/p')
  [ -z "$amqp_host" ] || [ -z "$mgmt_host" ] && return 1
  wuzapi_rabbit_amqp_port="$amqp_host"
  wuzapi_rabbit_mgmt_port="$mgmt_host"
  printf "${GREEN} >> Mantendo portas Rabbit da stack atual: AMQP ${wuzapi_rabbit_amqp_port} | Management ${wuzapi_rabbit_mgmt_port}${WHITE}\n\n"
  return 0
}

# Após git pull: só atualiza portas Rabbit no .env (não recria o arquivo inteiro).
whatsmeow_atualizar_env_portas_rabbit() {
  local env_file="/home/deploy/${empresa}/wuzapi/.env"
  [ -f "$env_file" ] || return 0
  if grep -q '^RABBITMQ_AMQP_PORT=' "$env_file" 2>/dev/null; then
    sed -i "s|^RABBITMQ_AMQP_PORT=.*|RABBITMQ_AMQP_PORT=${wuzapi_rabbit_amqp_port}|" "$env_file"
  else
    echo "RABBITMQ_AMQP_PORT=${wuzapi_rabbit_amqp_port}" >>"$env_file"
  fi
  if grep -q '^RABBITMQ_MGMT_PORT=' "$env_file" 2>/dev/null; then
    sed -i "s|^RABBITMQ_MGMT_PORT=.*|RABBITMQ_MGMT_PORT=${wuzapi_rabbit_mgmt_port}|" "$env_file"
  else
    echo "RABBITMQ_MGMT_PORT=${wuzapi_rabbit_mgmt_port}" >>"$env_file"
  fi
  chown deploy:deploy "$env_file" 2>/dev/null || true
}

# Garante SESSION_DEVICE_NAME e SESSION_PLATFORM_TYPE no .env (instalações antigas).
# Não sobrescreve nome customizado; só troca o padrão legado WuzAPI.
whatsmeow_atualizar_env_sessao_dispositivo() {
  local env_file="/home/deploy/${empresa}/wuzapi/.env"
  [ -f "$env_file" ] || return 0

  if grep -q '^SESSION_DEVICE_NAME=' "$env_file" 2>/dev/null; then
    if grep -qE '^SESSION_DEVICE_NAME=WuzAPI[[:space:]]*$' "$env_file" 2>/dev/null; then
      sed -i 's|^SESSION_DEVICE_NAME=WuzAPI[[:space:]]*$|SESSION_DEVICE_NAME=Windows - Wuz|' "$env_file"
      printf "${GREEN} >> .env: SESSION_DEVICE_NAME atualizado (WuzAPI → Windows - Wuz).${WHITE}\n"
    fi
  else
    {
      echo ""
      echo "# WuzAPI Session Configuration"
      echo "# Chrome no Windows — nome em Dispositivos vinculados (WhatsApp)"
      echo "SESSION_DEVICE_NAME=Windows - Wuz"
    } >>"$env_file"
    printf "${GREEN} >> .env: SESSION_DEVICE_NAME adicionado.${WHITE}\n"
  fi

  if ! grep -q '^SESSION_PLATFORM_TYPE=' "$env_file" 2>/dev/null; then
    if grep -q '^SESSION_DEVICE_NAME=' "$env_file" 2>/dev/null; then
      sed -i '/^SESSION_DEVICE_NAME=/a SESSION_PLATFORM_TYPE=CHROME' "$env_file"
    else
      echo "SESSION_PLATFORM_TYPE=CHROME" >>"$env_file"
    fi
    printf "${GREEN} >> .env: SESSION_PLATFORM_TYPE=CHROME adicionado.${WHITE}\n"
  fi

  chown deploy:deploy "$env_file" 2>/dev/null || true
}

# Reaplica docker-compose.yml do instalador (git sobrescreve com 5672 padrão do upstream).
whatsmeow_reaplicar_compose_instalador() {
  banner
  printf "${WHITE} >> Reaplicando docker-compose.yml do instalador (portas da instância)...\n"
  echo
  carregar_variaveis
  if [ -f "/home/deploy/${empresa}/wuzapi/.env" ]; then
    local p
    p=$(grep -m1 '^WUZAPI_PORT=' "/home/deploy/${empresa}/wuzapi/.env" 2>/dev/null | cut -d '=' -f2- | tr -d '\r')
    [ -n "$p" ] && wuzapi_port="$p"
  fi
  if ! whatsmeow_portas_rabbit_da_stack_atual; then
    whatsmeow_definir_portas_rabbit
  fi
  configurar_docker_compose
  whatsmeow_atualizar_env_portas_rabbit
  whatsmeow_atualizar_env_sessao_dispositivo
}

# Verificar e corrigir DNS antes do build
verificar_e_corrigir_dns() {
  banner
  printf "${WHITE} >> Verificando e corrigindo configurações de DNS...\n"
  echo
  
  {
    # Verificar DNS do sistema
    if ! grep -q "8.8.8.8" /etc/resolv.conf 2>/dev/null; then
      printf "${WHITE} >> Adicionando Google DNS ao sistema...\n"
      echo "nameserver 8.8.8.8" >> /etc/resolv.conf
      echo "nameserver 8.8.4.4" >> /etc/resolv.conf
      printf "${GREEN} >> DNS do sistema configurado!${WHITE}\n"
    fi
    
    # Verificar conectividade de rede
    printf "${WHITE} >> Verificando conectividade de rede...\n"
    if ! ping -c 1 -W 2 8.8.8.8 >/dev/null 2>&1; then
      printf "${YELLOW}⚠️  Aviso: Não foi possível fazer ping no Google DNS.${WHITE}\n"
      printf "${WHITE}   Verifique sua conexão de internet.${WHITE}\n"
    else
      printf "${GREEN} >> Conectividade de rede OK!${WHITE}\n"
    fi
    
    # Verificar resolução DNS
    printf "${WHITE} >> Verificando resolução DNS...\n"
    if command -v nslookup >/dev/null 2>&1; then
      if ! nslookup deb.debian.org >/dev/null 2>&1; then
        printf "${YELLOW}⚠️  Aviso: Não foi possível resolver deb.debian.org.${WHITE}\n"
      else
        printf "${GREEN} >> Resolução DNS OK!${WHITE}\n"
      fi
    fi
    
    # Configurar DNS do Docker daemon
    docker_daemon_updated=false
    if [ ! -f /etc/docker/daemon.json ]; then
      printf "${WHITE} >> Criando configuração do Docker daemon...\n"
      mkdir -p /etc/docker
      cat > /etc/docker/daemon.json <<EOF
{
  "dns": ["8.8.8.8", "8.8.4.4", "1.1.1.1"]
}
EOF
      docker_daemon_updated=true
      printf "${GREEN} >> Configuração do Docker daemon criada!${WHITE}\n"
    else
      # Verificar se DNS já está configurado
      if ! grep -q "8.8.8.8" /etc/docker/daemon.json 2>/dev/null; then
        printf "${WHITE} >> Adicionando DNS à configuração do Docker daemon...\n"
        # Usar jq se disponível, senão usar sed
        if command -v jq >/dev/null 2>&1; then
          jq '.dns = ["8.8.8.8", "8.8.4.4", "1.1.1.1"]' /etc/docker/daemon.json > /etc/docker/daemon.json.tmp && mv /etc/docker/daemon.json.tmp /etc/docker/daemon.json
        else
          # Método alternativo com sed
          cp /etc/docker/daemon.json /etc/docker/daemon.json.backup
          sed -i 's/}$/,\n  "dns": ["8.8.8.8", "8.8.4.4", "1.1.1.1"]\n}/' /etc/docker/daemon.json 2>/dev/null || {
            # Se falhar, criar novo arquivo
            cat > /etc/docker/daemon.json <<EOF
{
  "dns": ["8.8.8.8", "8.8.4.4", "1.1.1.1"]
}
EOF
          }
        fi
        docker_daemon_updated=true
        printf "${GREEN} >> DNS adicionado à configuração do Docker!${WHITE}\n"
      fi
    fi
    
    # Reiniciar Docker se configuração foi atualizada
    if [ "$docker_daemon_updated" = true ]; then
      printf "${WHITE} >> Reiniciando Docker para aplicar configurações...\n"
      systemctl restart docker
      sleep 5
      printf "${GREEN} >> Docker reiniciado!${WHITE}\n"
      printf "${YELLOW}   (Containers com restart=always, ex.: Portainer, voltam a subir automaticamente.)${WHITE}\n"
    fi
    
    # Verificar se Docker está rodando
    if ! systemctl is-active --quiet docker; then
      printf "${RED}❌ ERRO: Docker não está rodando!${WHITE}\n"
      printf "${WHITE}   Tentando iniciar Docker...\n"
      systemctl start docker
      sleep 3
    fi
    
    printf "${GREEN} >> Verificação de DNS concluída!${WHITE}\n"
    sleep 2
  } || {
    printf "${YELLOW}⚠️  Aviso: Não foi possível configurar DNS automaticamente.${WHITE}\n"
    printf "${WHITE}   O build pode falhar se houver problemas de conectividade.${WHITE}\n"
    sleep 2
  }
}

# Configurar docker-compose.yml
configurar_docker_compose() {
  banner
  printf "${WHITE} >> Configurando docker-compose.yml...\n"
  echo
  {
    # shellcheck source=/dev/null
    source "$ARQUIVO_VARIAVEIS"
    local db_user="wuzapi_${empresa}"
    db_user="${db_user//[^a-zA-Z0-9_]}"
    local cn_server="" cn_db="" cn_rmq=""
    if [ "${WHATSMEOW_COMPOSE_LEGACY}" != "1" ]; then
      cn_server="    container_name: ${WUZAPI_COMPOSE_PROJECT}-server"
      cn_db="    container_name: ${WUZAPI_COMPOSE_PROJECT}-db"
      cn_rmq="    container_name: ${WUZAPI_COMPOSE_PROJECT}-rabbitmq"
    fi

    # Criar arquivo docker-compose.yml
    cat > /home/deploy/${empresa}/wuzapi/docker-compose.yml <<DOCKERCOMPOSE
name: ${WUZAPI_COMPOSE_PROJECT}
services:
  wuzapi-server:
${cn_server}
    build:
      context: .
      dockerfile: Dockerfile
      extra_hosts:
        - "deb.debian.org:151.101.0.204"
        - "security.debian.org:151.101.0.204"
    dns:
      - 8.8.8.8
      - 8.8.4.4
      - 1.1.1.1
    ports:
      - "\${WUZAPI_PORT:-${wuzapi_port:-${default_wuzapi_port}}}:8080"
    environment:
      - WUZAPI_ADMIN_TOKEN=\${WUZAPI_ADMIN_TOKEN}
      - WUZAPI_GLOBAL_ENCRYPTION_KEY=\${WUZAPI_GLOBAL_ENCRYPTION_KEY}
      - WUZAPI_GLOBAL_HMAC_KEY=\${WUZAPI_GLOBAL_HMAC_KEY:-}
      - WUZAPI_GLOBAL_WEBHOOK=\${WUZAPI_GLOBAL_WEBHOOK:-}
      - DB_USER=\${DB_USER:-wuzapi}
      - DB_PASSWORD=\${DB_PASSWORD:-wuzapi}
      - DB_NAME=\${DB_NAME:-wuzapi}
      - DB_HOST=db
      - DB_PORT=\${DB_PORT:-5432}
      - TZ=\${TZ:-America/Sao_Paulo}
      - WEBHOOK_FORMAT=\${WEBHOOK_FORMAT:-json}
      - SESSION_DEVICE_NAME=\${SESSION_DEVICE_NAME:-Windows - Wuz}
      - SESSION_PLATFORM_TYPE=\${SESSION_PLATFORM_TYPE:-CHROME}
      # RabbitMQ configuration Optional
      - RABBITMQ_URL=amqp://${db_user}:\${DB_PASSWORD}@rabbitmq:5672/
      - RABBITMQ_QUEUE=whatsapp_events_${empresa}
    depends_on:
      db:
        condition: service_healthy
      rabbitmq:
        condition: service_healthy
    networks:
      - wuzapi-network
    security_opt:
      - seccomp=unconfined
      - apparmor=unconfined
    restart: always

  db:
${cn_db}
    image: postgres:16
    environment:
      POSTGRES_USER: \${DB_USER:-${db_user}}
      POSTGRES_PASSWORD: \${DB_PASSWORD:-wuzapi}
      POSTGRES_DB: \${DB_NAME:-${db_user}}
    # ports:
    #   - "\${DB_PORT:-5432}:5432" # Uncomment to access the database directly from your host machine.
    volumes:
      - db_data:/var/lib/postgresql/data
    networks:
      - wuzapi-network
    security_opt:
      - seccomp=unconfined
      - apparmor=unconfined
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U \${DB_USER:-wuzapi}"]
      interval: 5s
      timeout: 5s
      retries: 5
    restart: always

  rabbitmq:
${cn_rmq}
    image: rabbitmq:3-management
    hostname: rabbitmq-${empresa}
    environment:
      RABBITMQ_DEFAULT_USER: \${DB_USER:-${db_user}}
      RABBITMQ_DEFAULT_PASS: \${DB_PASSWORD:-wuzapi}
      RABBITMQ_DEFAULT_VHOST: /
    ports:
      - "${wuzapi_rabbit_amqp_port}:5672"
      - "${wuzapi_rabbit_mgmt_port}:15672"
    volumes:
      - rabbitmq_data:/var/lib/rabbitmq
    networks:
      - wuzapi-network
    security_opt:
      - seccomp=unconfined
      - apparmor=unconfined
    healthcheck:
      test: ["CMD", "rabbitmq-diagnostics", "ping"]
      interval: 10s
      timeout: 5s
      retries: 5
    restart: always

networks:
  wuzapi-network:
    driver: bridge

volumes:
  db_data:
  rabbitmq_data:
DOCKERCOMPOSE

    printf "${GREEN} >> Arquivo docker-compose.yml configurado com sucesso!${WHITE}\n"
    sleep 2
  } || trata_erro "configurar_docker_compose"
}

whatsmeow_set_env_backend() {
  local arquivo_env="$1"
  local chave="$2"
  local valor="$3"
  if grep -q "^${chave}=" "$arquivo_env" 2>/dev/null; then
    sed -i "s|^${chave}=.*|${chave}=${valor}|" "$arquivo_env"
  else
    echo "${chave}=${valor}" >>"$arquivo_env"
  fi
}

# Atualizar .env do backend
atualizar_env_backend() {
  banner
  printf "${WHITE} >> Atualizando .env do backend com configurações do WhatsMeow...\n"
  echo
  {
    # shellcheck source=/dev/null
    source "$ARQUIVO_VARIAVEIS"
    
    subdominio_limpo=$(echo "${subdominio_whatsmeow}" | sed 's|https\?://||')
    local backend_env="/home/deploy/${empresa}/backend/.env"
    [ ! -f "$backend_env" ] && printf "${RED} >> ERRO: ${backend_env} não encontrado.${WHITE}\n" && exit 1

    if ! grep -q '^# WhatsMeow Configuration' "$backend_env" 2>/dev/null; then
      echo "" >>"$backend_env"
      echo "# WhatsMeow Configuration" >>"$backend_env"
    fi
    whatsmeow_set_env_backend "$backend_env" "WUZAPI_URL" "https://${subdominio_limpo}"
    whatsmeow_set_env_backend "$backend_env" "WUZAPI_ADMIN_TOKEN" "${senha_deploy}"
    whatsmeow_set_env_backend "$backend_env" "WUZAPI_TOKEN" "${senha_deploy}"
    whatsmeow_set_env_backend "$backend_env" "WUZAPI_READ_RECEIPT_ENABLE_DELAY_MS" "2700000"
    chown deploy:deploy "$backend_env" 2>/dev/null || true
    chmod 600 "$backend_env" 2>/dev/null || true
    
    printf "${GREEN} >> .env do backend (${empresa}) atualizado com sucesso!${WHITE}\n"
    sleep 2
  } || trata_erro "atualizar_env_backend"
}

# Corrige init parcial do Postgres (volume sem CREATE DATABASE após falha de socket no Proxmox).
whatsmeow_garantir_banco_postgres() {
  # shellcheck source=/dev/null
  source "$ARQUIVO_VARIAVEIS"
  local db_user="wuzapi_${empresa}"
  db_user="${db_user//[^a-zA-Z0-9_]}"
  local db_container="${WUZAPI_COMPOSE_PROJECT}-db"

  command -v docker >/dev/null 2>&1 || return 0
  docker ps --format '{{.Names}}' 2>/dev/null | grep -qx "$db_container" || return 0

  if docker exec "$db_container" psql -U "$db_user" -d postgres -tAc \
    "SELECT 1 FROM pg_database WHERE datname='${db_user}'" 2>/dev/null | grep -q 1; then
    return 0
  fi

  printf "${YELLOW} >> Banco ${db_user} ausente no Postgres do WuzAPI — criando...${WHITE}\n"
  docker exec "$db_container" psql -U "$db_user" -d postgres -c \
    "CREATE DATABASE \"${db_user}\" OWNER \"${db_user}\";" 2>/dev/null || true
}

# Verificar e instalar Docker
verificar_e_instalar_docker() {
  banner
  printf "${WHITE} >> Verificando se o Docker está instalado...\n"
  echo

  if verificar_docker_funcionando; then
    printf "${GREEN} >> Docker já está instalado.${WHITE}\n"
    docker --version
    docker compose version 2>/dev/null || docker-compose --version 2>/dev/null || true
    echo
    sleep 2
    return 0
  fi

  printf "${YELLOW} >> Docker não encontrado. Iniciando instalação...${WHITE}\n"
  echo

  if ! instalar_docker_compartilhado; then
    printf "${RED}❌ ERRO: Docker não está disponível após instalação!${WHITE}\n"
    printf "${WHITE}   SO detectado: $(. /etc/os-release 2>/dev/null; echo ${PRETTY_NAME:-desconhecido})${WHITE}\n"
    printf "${WHITE}   Tente executar manualmente:${WHITE}\n"
    printf "${WHITE}   curl -fsSL https://get.docker.com | sh${WHITE}\n"
    printf "${WHITE}   ou: apt-get install -y docker.io docker-compose${WHITE}\n"
    exit 1
  fi

  if ! verificar_docker_funcionando; then
    trata_erro "verificar_e_instalar_docker"
  fi

  printf "${GREEN} >> Docker instalado com sucesso!${WHITE}\n"
  docker --version
  docker compose version 2>/dev/null || docker-compose --version 2>/dev/null || true
  printf "${GREEN} >> Docker e docker compose verificados e funcionando!${WHITE}\n"
  echo
  sleep 2
}

# Subir containers do WhatsMeow
subir_containers_whatsmeow() {
  banner
  printf "${WHITE} >> Subindo containers do WhatsMeow...\n"
  echo
  
  {
    # Verificar se Docker está disponível antes de continuar
    if ! command -v docker >/dev/null 2>&1; then
      printf "${RED}❌ ERRO: Comando 'docker' não encontrado!${WHITE}\n"
      printf "${WHITE}   Verifique se o Docker está instalado e no PATH.${WHITE}\n"
      printf "${WHITE}   Tente executar: sudo apt-get install -y docker.io${WHITE}\n"
      exit 1
    fi
    
    # Verificar se docker compose está disponível
    docker_compose_cmd="docker compose"
    if ! docker compose version >/dev/null 2>&1; then
      if command -v docker-compose >/dev/null 2>&1; then
        docker_compose_cmd="docker-compose"
        printf "${WHITE} >> Usando docker-compose (versão antiga)${WHITE}\n"
      else
        printf "${RED}❌ ERRO: docker compose não está disponível!${WHITE}\n"
        exit 1
      fi
    fi
    
    cd /home/deploy/${empresa}/wuzapi
    docker_compose_cmd="$docker_compose_cmd -p ${WUZAPI_COMPOSE_PROJECT}"
    
    # Verificar conectividade antes do build
    printf "${WHITE} >> Verificando conectividade antes do build...\n"
    if ! ping -c 1 -W 2 deb.debian.org >/dev/null 2>&1; then
      printf "${YELLOW}⚠️  Aviso: Não foi possível fazer ping em deb.debian.org${WHITE}\n"
      printf "${WHITE}   Tentando continuar mesmo assim...\n"
    else
      printf "${GREEN} >> Conectividade com deb.debian.org OK!${WHITE}\n"
    fi
    echo
    
    # Limpar builds anteriores que podem ter falhado
    printf "${WHITE} >> Limpando builds anteriores...\n"
    $docker_compose_cmd down -v 2>/dev/null || true
    docker builder prune -f >/dev/null 2>&1 || true
    echo
    
    printf "${WHITE} >> Executando docker compose build (isso pode levar alguns minutos)...\n"
    echo
    
    # Tentar build com retry
    max_retries=3
    retry_count=0
    build_success=false
    
    while [ $retry_count -lt $max_retries ] && [ "$build_success" = false ]; do
      if [ $retry_count -gt 0 ]; then
        printf "${YELLOW} >> Tentativa ${retry_count} de ${max_retries}...${WHITE}\n"
        printf "${WHITE} >> Aguardando 10 segundos antes de tentar novamente...\n"
        sleep 10
      fi
      
      # Executar build primeiro
      printf "${WHITE} >> Executando docker compose build...\n"
      docker_output=$($docker_compose_cmd build --no-cache 2>&1)
      build_exit_code=$?
      
      echo "$docker_output"
      echo
      
      # Verificar se o erro é relacionado a DNS/rede
      if echo "$docker_output" | grep -qiE "(could not resolve|failed to fetch|network|dns)"; then
        printf "${YELLOW}⚠️  Erro de rede/DNS detectado.${WHITE}\n"
        if [ $retry_count -lt $((max_retries - 1)) ]; then
          printf "${WHITE} >> Tentando novamente...${WHITE}\n"
          retry_count=$((retry_count + 1))
          continue
        fi
      fi
      
      if [ $build_exit_code -eq 0 ]; then
        build_success=true
        printf "${GREEN} >> Build concluído com sucesso!${WHITE}\n"
        echo
      else
        retry_count=$((retry_count + 1))
        if [ $retry_count -ge $max_retries ]; then
          printf "${RED}❌ ERRO: Falha ao fazer build após ${max_retries} tentativas.${WHITE}\n"
          printf "${YELLOW}   Possíveis causas:${WHITE}\n"
          printf "${YELLOW}   1. Problema de conectividade de rede${WHITE}\n"
          printf "${YELLOW}   2. DNS não configurado corretamente${WHITE}\n"
          printf "${YELLOW}   3. Firewall bloqueando conexões${WHITE}\n"
          printf "${WHITE}   Verifique os logs acima para mais detalhes.${WHITE}\n"
          printf "${WHITE}   Tente executar manualmente:${WHITE}\n"
          printf "${WHITE}   cd /home/deploy/${empresa}/wuzapi && $docker_compose_cmd build${WHITE}\n"
          exit 1
        fi
      fi
    done
    
    if [ "$build_success" = true ]; then
      printf "${WHITE} >> Executando docker compose up -d...\n"
      echo
      
      # Executar docker compose up
      docker_output=$($docker_compose_cmd up -d 2>&1)
      docker_exit_code=$?
      
      echo "$docker_output"
      echo
      
      if [ $docker_exit_code -eq 0 ]; then
        # Verificar se os containers estão rodando
        printf "${WHITE} >> Aguardando containers iniciarem...\n"
        sleep 10
        whatsmeow_garantir_banco_postgres
        docker compose -p "${WUZAPI_COMPOSE_PROJECT}" restart wuzapi-server 2>/dev/null || \
          $docker_compose_cmd restart wuzapi-server 2>/dev/null || true
        sleep 5
        
        # Verificar status dos containers
        if $docker_compose_cmd ps | grep -qE "(Healthy|Running|Up)"; then
          printf "${GREEN}✅ Containers do WhatsMeow iniciados com sucesso!${WHITE}\n"
          echo
          $docker_compose_cmd ps
          echo
          sleep 2
        else
          printf "${YELLOW}⚠️  Containers iniciados, mas alguns podem estar iniciando ainda...${WHITE}\n"
          printf "${WHITE}   Verifique o status com: cd /home/deploy/${empresa}/wuzapi && $docker_compose_cmd ps${WHITE}\n"
          echo
          sleep 2
        fi
      else
        printf "${RED}❌ ERRO: Falha ao subir os containers do WhatsMeow.${WHITE}\n"
        printf "${RED}   Verifique os logs com: cd /home/deploy/${empresa}/wuzapi && $docker_compose_cmd logs${WHITE}\n"
        exit 1
      fi
    fi
  } || trata_erro "subir_containers_whatsmeow"
}

# Atualizar código do repositório wuzapi (git pull — não apaga .env nem volumes Docker).
atualizar_codigo_wuzapi_git() {
  banner
  printf "${WHITE} >> Atualizando código do WuzAPI (git)...\n"
  echo
  {
    local wuz_dir="/home/deploy/${empresa}/wuzapi"
    local git_user="deploy"
    local head_antes head_depois

    if [ ! -d "${wuz_dir}/.git" ]; then
      printf "${RED} >> Pasta não é um repositório git. Reinstale pelo menu (opção 3).${WHITE}\n"
      exit 1
    fi

    if ! id "$git_user" >/dev/null 2>&1; then
      printf "${RED} >> Usuário ${git_user} não encontrado.${WHITE}\n"
      exit 1
    fi

    # Root em /home/deploy/* dispara "dubious ownership" no Git 2.35+
    git config --global --add safe.directory "$wuz_dir" 2>/dev/null || true
    sudo -u "$git_user" git config --global --add safe.directory "$wuz_dir" 2>/dev/null || true

    if [ -f "${wuz_dir}/.env" ]; then
      cp -a "${wuz_dir}/.env" "${wuz_dir}/.env.bak.$(date +%Y%m%d-%H%M%S)" 2>/dev/null || true
      printf "${GREEN} >> Backup do .env criado antes do pull.${WHITE}\n"
    fi

    head_antes=$(sudo -u "$git_user" git -C "$wuz_dir" rev-parse --short HEAD 2>/dev/null || echo "?")
    printf "${WHITE} >> git fetch + sincronizar com origin (usuário ${git_user})...${WHITE}\n"
    printf "${YELLOW} >> Alterações locais em arquivos versionados serão descartadas; o .env é preservado.${WHITE}\n"
    printf "${YELLOW} >> O Dockerfile será reajustado na etapa seguinte (corrigir_dockerfile).${WHITE}\n"

    sudo -u "$git_user" git -C "$wuz_dir" fetch origin 2>&1 || true

    local branch remoto_ref
    branch=$(sudo -u "$git_user" git -C "$wuz_dir" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")
    if [ -z "$branch" ] || [ "$branch" = "HEAD" ]; then
      branch=""
      for branch in main master; do
        if sudo -u "$git_user" git -C "$wuz_dir" show-ref --verify --quiet "refs/remotes/origin/${branch}" 2>/dev/null; then
          break
        fi
        branch=""
      done
      [ -z "$branch" ] && branch="main"
    fi
    remoto_ref="origin/${branch}"
    if ! sudo -u "$git_user" git -C "$wuz_dir" show-ref --verify --quiet "refs/remotes/${remoto_ref}" 2>/dev/null; then
      for branch in main master; do
        if sudo -u "$git_user" git -C "$wuz_dir" show-ref --verify --quiet "refs/remotes/origin/${branch}" 2>/dev/null; then
          remoto_ref="origin/${branch}"
          break
        fi
      done
    fi

    if ! sudo -u "$git_user" git -C "$wuz_dir" reset --hard "${remoto_ref}" 2>&1; then
      printf "${RED} >> ERRO ao alinhar com ${remoto_ref}.${WHITE}\n"
      exit 1
    fi
    sudo -u "$git_user" git -C "$wuz_dir" pull --ff-only origin "${branch}" 2>&1 || \
      sudo -u "$git_user" git -C "$wuz_dir" pull origin "${branch}" 2>&1 || true

    head_depois=$(sudo -u "$git_user" git -C "$wuz_dir" rev-parse --short HEAD 2>/dev/null || echo "?")
    printf "${GREEN} >> Git: ${head_antes} → ${head_depois}${WHITE}\n"
    chown -R deploy:deploy "$wuz_dir" 2>/dev/null || true
    sleep 1
  } || trata_erro "atualizar_codigo_wuzapi_git"
}

# Rebuild só do serviço da API (preserva Postgres/RabbitMQ — sem docker compose down -v).
rebuild_containers_whatsmeow_atualizacao() {
  banner
  printf "${WHITE} >> Rebuild do container wuzapi-server (mantém banco e RabbitMQ)...\n"
  echo
  {
    if ! command -v docker >/dev/null 2>&1; then
      printf "${RED} >> Docker não encontrado.${WHITE}\n"
      exit 1
    fi

    local docker_compose_cmd="docker compose"
    if ! docker compose version >/dev/null 2>&1; then
      if command -v docker-compose >/dev/null 2>&1; then
        docker_compose_cmd="docker-compose"
      else
        printf "${RED} >> docker compose não disponível.${WHITE}\n"
        exit 1
      fi
    fi

    cd "/home/deploy/${empresa}/wuzapi" || exit 1
    carregar_variaveis
    docker_compose_cmd="$docker_compose_cmd -p ${WUZAPI_COMPOSE_PROJECT}"

    printf "${WHITE} >> Atualizando só wuzapi-server (projeto ${WUZAPI_COMPOSE_PROJECT}; DB/RabbitMQ intactos)...${WHITE}\n"

    printf "${WHITE} >> docker compose build wuzapi-server...${WHITE}\n"
    if ! $docker_compose_cmd build wuzapi-server 2>&1; then
      printf "${YELLOW} >> Build com cache falhou; tentando --no-cache...${WHITE}\n"
      if ! $docker_compose_cmd build --no-cache wuzapi-server 2>&1; then
        printf "${RED} >> ERRO no build. Verifique: cd /home/deploy/${empresa}/wuzapi && $docker_compose_cmd build wuzapi-server${WHITE}\n"
        exit 1
      fi
    fi

    printf "${WHITE} >> docker compose up -d --no-deps --force-recreate wuzapi-server...${WHITE}\n"
    if ! $docker_compose_cmd up -d --no-deps --force-recreate wuzapi-server 2>&1; then
      if [ "${WHATSMEOW_COMPOSE_LEGACY}" = "1" ]; then
        local legado_api
        legado_api=$(docker ps -a --format '{{.Names}}' 2>/dev/null | grep -E '^wuzapi-wuzapi-server-' | head -1)
        if [ -n "$legado_api" ]; then
          printf "${YELLOW} >> Recriando container legado ${legado_api} com a nova imagem...${WHITE}\n"
          docker stop "$legado_api" 2>/dev/null || true
          docker rm "$legado_api" 2>/dev/null || true
        fi
      fi
      if ! $docker_compose_cmd up -d --no-deps wuzapi-server 2>&1; then
        printf "${RED} >> ERRO ao subir wuzapi-server (projeto ${WUZAPI_COMPOSE_PROJECT}).${WHITE}\n"
        printf "${YELLOW} >> Porta ${wuzapi_port:-8090} em uso? Verifique: docker ps --filter publish=${wuzapi_port:-8090}${WHITE}\n"
        exit 1
      fi
    fi

    sleep 8
    $docker_compose_cmd ps
    echo
    if $docker_compose_cmd ps 2>/dev/null | grep -qE "wuzapi-server|server"; then
      if $docker_compose_cmd ps 2>/dev/null | grep -qiE "Up|Running|healthy"; then
        printf "${GREEN} >> Containers atualizados.${WHITE}\n"
      else
        printf "${YELLOW} >> Verifique: $docker_compose_cmd logs wuzapi-server --tail 80${WHITE}\n"
      fi
    fi
    sleep 2
  } || trata_erro "rebuild_containers_whatsmeow_atualizacao"
}

# Reiniciar serviços
reiniciar_servicos() {
  banner
  printf "${WHITE} >> Reiniciando serviços...\n"
  echo
  {
    sudo su - root <<EOF
    if systemctl is-active --quiet nginx; then
      sudo systemctl restart nginx
    elif systemctl is-active --quiet traefik; then
      sudo systemctl restart traefik.service
    else
      printf "${GREEN}Nenhum serviço de proxy (Nginx ou Traefik) está em execução.${WHITE}"
    fi
EOF

    printf "${GREEN} >> Serviços reiniciados com sucesso!${WHITE}\n"
    sleep 2
  } || trata_erro "reiniciar_servicos"
}

# Reiniciar PM2 do backend da instância (aplica WUZAPI_* no .env)
reiniciar_pm2_backend() {
  banner
  printf "${WHITE} >> Reiniciando backend ${BLUE}${empresa}${WHITE} para aplicar o WhatsMeow...\n"
  echo
  {
    # shellcheck source=/dev/null
    source "$ARQUIVO_VARIAVEIS"
    local pm2_name="${empresa}-backend"
    local _path_node="${INSTALADOR_DIR}/tools/path_node_deploy.sh"
    [ ! -f "$_path_node" ] && _path_node="/root/instalador_single_oficial/tools/path_node_deploy.sh"

    local rc=0
    sudo su - deploy <<RESTARTBACKEND || rc=$?
set -e
if [ -f "${_path_node}" ]; then
  # shellcheck source=/dev/null
  . "${_path_node}"
else
  export PATH="/usr/local/bin:/usr/bin:\${PATH:-}"
  if [ -d /usr/local/n/versions/node/20.19.4/bin ]; then
    export PATH="/usr/local/n/versions/node/20.19.4/bin:\$PATH"
  fi
fi

if ! command -v pm2 >/dev/null 2>&1; then
  echo "ERRO: pm2 não encontrado para o usuário deploy."
  exit 1
fi

echo ">> PM2 — processos:"
pm2 list 2>/dev/null || true

if pm2 describe "${pm2_name}" >/dev/null 2>&1; then
  pm2 restart "${pm2_name}"
  pm2 save
  echo "OK: ${pm2_name} reiniciado."
elif pm2 jlist 2>/dev/null | grep -qF "\"name\":\"${pm2_name}\""; then
  pm2 restart "${pm2_name}"
  pm2 save
  echo "OK: ${pm2_name} reiniciado."
else
  echo "AVISO: processo ${pm2_name} não encontrado no PM2."
  pm2 list 2>/dev/null || true
  exit 2
fi
RESTARTBACKEND

    if [ "$rc" -eq 0 ]; then
      printf "${GREEN} >> Backend ${pm2_name} reiniciado — variáveis WUZAPI aplicadas.${WHITE}\n"
    elif [ "$rc" -eq 2 ]; then
      printf "${YELLOW}⚠️  ${pm2_name} não encontrado no PM2.${WHITE}\n"
      printf "${WHITE}   Execute como deploy: pm2 restart ${pm2_name}${WHITE}\n"
    else
      trata_erro "reiniciar_pm2_backend"
    fi
    sleep 2
  } || trata_erro "reiniciar_pm2_backend"
}

# Função principal
main() {
  aviso_versao_pro
  selecionar_instancia_whatsmeow
  carregar_variaveis
  verificar_instalacao_existente
  solicitar_subdominio_whatsmeow
  solicitar_porta_whatsmeow
  verificar_dns_whatsmeow
  configurar_nginx_whatsmeow
  clonar_repositorio_wuzapi
  verificar_e_instalar_docker
  verificar_e_corrigir_dns
  corrigir_dockerfile_wuzapi
  whatsmeow_definir_portas_rabbit
  configurar_env_wuzapi
  configurar_docker_compose
  atualizar_env_backend
  subir_containers_whatsmeow
  reiniciar_servicos
  reiniciar_pm2_backend
  
  # shellcheck source=/dev/null
  source "$ARQUIVO_VARIAVEIS"
  
  # Limpar subdomínio para exibição
  subdominio_limpo=$(echo "${subdominio_whatsmeow}" | sed 's|https\?://||')
  
  banner
  printf "${GREEN}══════════════════════════════════════════════════════════════════${WHITE}\n"
  printf "${GREEN}✅ Instalação do WhatsMeow concluída com sucesso!${WHITE}\n"
  echo
  printf "${WHITE}   📍 API WhatsMeow disponível em:${WHITE}\n"
  printf "${YELLOW}   https://${subdominio_limpo}${WHITE}\n"
  echo
  printf "${WHITE}   🔑 Access Token:${WHITE}\n"
  printf "${YELLOW}   ${senha_deploy}${WHITE}\n"
  echo
  printf "${WHITE}   📚 Para consultar os endpoints da API, acesse:${WHITE}\n"
  printf "${YELLOW}   https://${subdominio_limpo}/api${WHITE}\n"
  echo
  printf "${WHITE}   🐰 RabbitMQ (host): AMQP ${YELLOW}${wuzapi_rabbit_amqp_port}${WHITE} | Management ${YELLOW}${wuzapi_rabbit_mgmt_port}${WHITE}\n"
  echo
  printf "${GREEN}══════════════════════════════════════════════════════════════════${WHITE}\n"
  echo
  sleep 5
}

# Resolver ARQUIVO_VARIAVEIS pela empresa (sem menu).
whatsmeow_carregar_variaveis_por_empresa() {
  local emp="$1"
  INSTALADOR_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  local arq=""

  [ -n "$emp" ] || return 1

  if [ -f "${INSTALADOR_DIR}/VARIAVEIS_INSTALACAO" ]; then
    # shellcheck source=/dev/null
    source "${INSTALADOR_DIR}/VARIAVEIS_INSTALACAO" 2>/dev/null
    if [ "${empresa:-}" = "$emp" ]; then
      ARQUIVO_VARIAVEIS="${INSTALADOR_DIR}/VARIAVEIS_INSTALACAO"
      empresa="$emp"
      return 0
    fi
  fi

  shopt -s nullglob
  for arq in "${INSTALADOR_DIR}"/VARIAVEIS_INSTALACAO_INSTANCIA_*; do
    [ -f "$arq" ] || continue
    local e2=""
    e2=$(grep -m1 '^empresa=' "$arq" 2>/dev/null | cut -d '=' -f2- | tr -d '\r')
    if [ "$e2" = "$emp" ]; then
      ARQUIVO_VARIAVEIS="$arq"
      # shellcheck source=/dev/null
      source "$arq" 2>/dev/null
      empresa="$emp"
      shopt -u nullglob
      return 0
    fi
  done
  shopt -u nullglob

  empresa="$emp"
  ARQUIVO_VARIAVEIS=""
  return 0
}

# Git pull no wuzapi; retorna 0 se HEAD mudou, 1 se não mudou.
whatsmeow_git_pull_verificar_mudanca() {
  local wuz_dir="/home/deploy/${empresa}/wuzapi"
  local git_user="deploy"
  local head_antes head_depois branch remoto_ref

  WHATSMEOW_GIT_MUDOU=0
  [ -d "${wuz_dir}/.git" ] || return 1
  id "$git_user" >/dev/null 2>&1 || return 1

  git config --global --add safe.directory "$wuz_dir" 2>/dev/null || true
  sudo -u "$git_user" git config --global --add safe.directory "$wuz_dir" 2>/dev/null || true

  if [ -f "${wuz_dir}/.env" ]; then
    cp -a "${wuz_dir}/.env" "${wuz_dir}/.env.bak.$(date +%Y%m%d-%H%M%S)" 2>/dev/null || true
  fi

  head_antes=$(sudo -u "$git_user" git -C "$wuz_dir" rev-parse HEAD 2>/dev/null || echo "")
  [ -n "$head_antes" ] || return 1

  sudo -u "$git_user" git -C "$wuz_dir" fetch origin 2>&1 || true

  branch=$(sudo -u "$git_user" git -C "$wuz_dir" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")
  if [ -z "$branch" ] || [ "$branch" = "HEAD" ]; then
    branch=""
    for branch in main master; do
      if sudo -u "$git_user" git -C "$wuz_dir" show-ref --verify --quiet "refs/remotes/origin/${branch}" 2>/dev/null; then
        break
      fi
      branch=""
    done
    [ -z "$branch" ] && branch="main"
  fi
  remoto_ref="origin/${branch}"
  if ! sudo -u "$git_user" git -C "$wuz_dir" show-ref --verify --quiet "refs/remotes/${remoto_ref}" 2>/dev/null; then
    for branch in main master; do
      if sudo -u "$git_user" git -C "$wuz_dir" show-ref --verify --quiet "refs/remotes/origin/${branch}" 2>/dev/null; then
        remoto_ref="origin/${branch}"
        break
      fi
    done
  fi

  if ! sudo -u "$git_user" git -C "$wuz_dir" reset --hard "${remoto_ref}" 2>&1; then
    return 1
  fi
  sudo -u "$git_user" git -C "$wuz_dir" pull --ff-only origin "${branch}" 2>&1 || \
    sudo -u "$git_user" git -C "$wuz_dir" pull origin "${branch}" 2>&1 || true

  head_depois=$(sudo -u "$git_user" git -C "$wuz_dir" rev-parse HEAD 2>/dev/null || echo "")
  chown -R deploy:deploy "$wuz_dir" 2>/dev/null || true

  if [ -n "$head_depois" ] && [ "$head_antes" != "$head_depois" ]; then
    WHATSMEOW_GIT_MUDOU=1
    printf "${GREEN} >> WuzAPI: código atualizado (${head_antes:0:7} → ${head_depois:0:7}).${WHITE}\n"
    return 0
  fi

  printf "${WHITE} >> WuzAPI: sem alterações no repositório (${head_depois:0:7}).${WHITE}\n"
  return 1
}

# Modo automático (atualizador_fast_sistema): sem perguntas; rebuild só se git mudou.
main_atualizar_whatsmeow_sistema() {
  local emp="${1:-}"

  [ -n "$emp" ] || {
    printf "${RED} >> Empresa não informada (--atualizar-sistema <empresa>).${WHITE}\n"
    exit 1
  }

  if [ ! -d "/home/deploy/${emp}/wuzapi" ] || [ ! -f "/home/deploy/${emp}/wuzapi/docker-compose.yml" ]; then
    printf "${WHITE} >> WhatsMeow não instalado em ${emp}; etapa ignorada.${WHITE}\n"
    exit 0
  fi

  whatsmeow_carregar_variaveis_por_empresa "$emp" || true
  carregar_variaveis
  whatsmeow_remover_stack_orfao

  if whatsmeow_git_pull_verificar_mudanca; then
    whatsmeow_reaplicar_compose_instalador
    corrigir_dockerfile_wuzapi
    rebuild_containers_whatsmeow_atualizacao
    whatsmeow_remover_stack_orfao
    reiniciar_servicos
    reiniciar_pm2_backend
    printf "${GREEN} >> WhatsMeow (${empresa}) atualizado.${WHITE}\n"
  else
    printf "${GREEN} >> WhatsMeow (${emp}): nenhum rebuild necessário.${WHITE}\n"
  fi
  exit 0
}

# Atualizar WhatsMeow já instalado: git pull + rebuild wuzapi-server (sem reinstalar do zero).
main_atualizar_whatsmeow() {
  banner
  printf "${WHITE} >> Atualizar WhatsMeow (WuzAPI)${WHITE}\n"
  printf "${WHITE} >> Fluxo: git pull → ajuste Dockerfile (se preciso) → rebuild do container da API.${WHITE}\n"
  printf "${YELLOW} >> Postgres e RabbitMQ permanecem (sem apagar volumes).${WHITE}\n"
  echo
  printf "${WHITE} >> Continuar? (S/N):${WHITE}\n"
  read -r conf
  conf=$(echo "$conf" | tr '[:lower:]' '[:upper:]')
  if [ "$conf" != "S" ]; then
    printf "${YELLOW} >> Cancelado.${WHITE}\n"
    sleep 2
    exit 0
  fi

  selecionar_instancia_whatsmeow_atualizar
  carregar_variaveis
  whatsmeow_remover_stack_orfao
  atualizar_codigo_wuzapi_git
  whatsmeow_reaplicar_compose_instalador
  corrigir_dockerfile_wuzapi
  rebuild_containers_whatsmeow_atualizacao
  whatsmeow_remover_stack_orfao
  reiniciar_servicos
  reiniciar_pm2_backend

  # shellcheck source=/dev/null
  source "$ARQUIVO_VARIAVEIS"
  local subdominio_limpo
  subdominio_limpo=$(echo "${subdominio_whatsmeow:-}" | sed 's|https\?://||')
  [ -z "$subdominio_limpo" ] && subdominio_limpo="localhost:${wuzapi_port:-8090}"

  banner
  printf "${GREEN} >> Atualização do WhatsMeow (${empresa}) concluída.${WHITE}\n"
  echo
  printf "${WHITE}   URL: ${YELLOW}https://${subdominio_limpo}${WHITE}\n"
  printf "${WHITE}   Logs: ${YELLOW}cd /home/deploy/${empresa}/wuzapi && docker compose -p ${WUZAPI_COMPOSE_PROJECT} logs wuzapi-server --tail 50${WHITE}\n"
  echo
  printf "${YELLOW} >> Nome no celular (Dispositivos vinculados): após mudar SESSION_* no .env,${WHITE}\n"
  printf "${YELLOW}    desvincule no WhatsApp, faça logout da sessão (/session/logout) e pareie de novo.${WHITE}\n"
  echo
  sleep 3
}

if [ "${1:-}" = "--atualizar-sistema" ]; then
  main_atualizar_whatsmeow_sistema "${2:-}"
elif [ "${1:-}" = "--atualizar" ]; then
  main_atualizar_whatsmeow
else
  main
fi
