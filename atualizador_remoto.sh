#!/bin/bash

GREEN='\033[1;32m'
BLUE='\033[1;34m'
WHITE='\033[1;37m'
RED='\033[1;31m'
YELLOW='\033[1;33m'

# Variaveis Padrão
ARCH=$(uname -m)
UBUNTU_VERSION=$(lsb_release -sr)
ARQUIVO_VARIAVEIS="VARIAVEIS_INSTALACAO"
ARQUIVO_ETAPAS="ETAPA_INSTALACAO"
FFMPEG="$(pwd)/ffmpeg.x"
FFMPEG_DIR="$(pwd)/ffmpeg"
ip_atual=$(curl -s http://checkip.amazonaws.com)
jwt_secret=$(openssl rand -base64 32)
jwt_refresh_secret=$(openssl rand -base64 32)

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

# Função banner
banner() {
  printf " ${BLUE}"
  printf "\n\n"
  printf "██╗███╗   ██╗███████╗████████╗ █████╗ ██╗     ██╗     ███████╗██╗    ██╗██╗\n"
  printf "██║████╗  ██║██╔════╝╚══██╔══╝██╔══██╗██║     ██║     ██╔════╝██║    ██║██║\n"
  printf "██║██╔██╗ ██║███████    ██║   ███████║██║     ██║     ███████╗██║ █╗ ██║██║\n"
  printf "██║██║╚██╗██║╚════██║   ██║   ██╔══██║██║     ██║     ╚════██║██║███╗██║██║\n"
  printf "██║██║ ╚████║███████║   ██║   ██║  ██║███████╗███████╗███████║╚███╔███╔╝██║\n"
  printf "╚═╝╚═╝  ╚═══╝╚══════╝   ╚═╝   ╚═╝  ╚═╝╚══════╝╚══════╝╚══════╝ ╚══╝╚══╝ ╚══════╝\n"
  printf "${WHITE}\n"
}

# Função para detectar e listar todas as instâncias instaladas
detectar_instancias_instaladas() {
  local instancias=()
  local nomes_empresas=()
  local temp_empresa=""
  local temp_subdominio_backend=""
  local temp_subdominio_frontend=""
  
  # Verificar instalação base (arquivo VARIAVEIS_INSTALACAO)
  INSTALADOR_DIR="/root/instalador_single_oficial"
  ARQUIVO_VARIAVEIS="VARIAVEIS_INSTALACAO"
  if [ -f "${INSTALADOR_DIR}/${ARQUIVO_VARIAVEIS}" ]; then
    # Salvar variáveis atuais
    local empresa_original="${empresa:-}"
    local subdominio_backend_original="${subdominio_backend:-}"
    local subdominio_frontend_original="${subdominio_frontend:-}"
    
    # Carregar variáveis do arquivo
    source "${INSTALADOR_DIR}/${ARQUIVO_VARIAVEIS}" 2>/dev/null
    temp_empresa="${empresa:-}"
    
    if [ -n "${temp_empresa}" ] && [ -d "/home/deploy/${temp_empresa}" ] && [ -d "/home/deploy/${temp_empresa}/backend" ]; then
      instancias+=("${INSTALADOR_DIR}/${ARQUIVO_VARIAVEIS}")
      nomes_empresas+=("${temp_empresa}")
    fi
    
    # Restaurar variáveis originais
    empresa="${empresa_original}"
    subdominio_backend="${subdominio_backend_original}"
    subdominio_frontend="${subdominio_frontend_original}"
  fi
  
  # Verificar instâncias adicionais (arquivos VARIAVEIS_INSTALACAO_INSTANCIA_*)
  if [ -d "${INSTALADOR_DIR}" ]; then
    for arquivo_instancia in "${INSTALADOR_DIR}"/VARIAVEIS_INSTALACAO_INSTANCIA_*; do
      if [ -f "$arquivo_instancia" ]; then
        # Salvar variáveis atuais
        local empresa_original="${empresa:-}"
        local subdominio_backend_original="${subdominio_backend:-}"
        local subdominio_frontend_original="${subdominio_frontend:-}"
        
        # Carregar variáveis do arquivo
        source "$arquivo_instancia" 2>/dev/null
        temp_empresa="${empresa:-}"
        
        if [ -n "${temp_empresa}" ] && [ -d "/home/deploy/${temp_empresa}" ] && [ -d "/home/deploy/${temp_empresa}/backend" ]; then
          instancias+=("$arquivo_instancia")
          nomes_empresas+=("${temp_empresa}")
        fi
        
        # Restaurar variáveis originais
        empresa="${empresa_original}"
        subdominio_backend="${subdominio_backend_original}"
        subdominio_frontend="${subdominio_frontend_original}"
      fi
    done
  fi
  
  # Retornar arrays (usando variáveis globais)
  declare -g INSTANCIAS_DETECTADAS=("${instancias[@]}")
  declare -g NOMES_EMPRESAS_DETECTADAS=("${nomes_empresas[@]}")
}

# Função para selecionar qual instância atualizar
selecionar_instancia_atualizar() {
  banner
  printf "${WHITE} >> Detectando instâncias instaladas...\n"
  echo
  
  detectar_instancias_instaladas
  
  local total_instancias=${#INSTANCIAS_DETECTADAS[@]}
  
  if [ $total_instancias -eq 0 ]; then
    printf "${RED} >> ERRO: Nenhuma instância instalada detectada!${WHITE}\n"
    printf "${YELLOW} >> Não é possível atualizar. Verifique se há instâncias instaladas.${WHITE}\n"
    sleep 3
    return 1
  elif [ $total_instancias -eq 1 ]; then
    # Apenas uma instância, usar diretamente
    printf "${GREEN} >> Uma instância detectada: ${BLUE}${NOMES_EMPRESAS_DETECTADAS[0]}${WHITE}\n"
    echo
    sleep 2
    
    # Carregar variáveis da instância única
    source "${INSTANCIAS_DETECTADAS[0]}"
    # Salvar arquivo usado em variável global para uso posterior
    declare -g ARQUIVO_VARIAVEIS_USADO="${INSTANCIAS_DETECTADAS[0]}"
    return 0
  else
    # Múltiplas instâncias, perguntar qual atualizar
    printf "${WHITE}═══════════════════════════════════════════════════════════\n"
    printf "  INSTÂNCIAS INSTALADAS DETECTADAS\n"
    printf "═══════════════════════════════════════════════════════════\n${WHITE}"
    echo
    
    local index=1
    for i in "${!NOMES_EMPRESAS_DETECTADAS[@]}"; do
      local empresa_nome="${NOMES_EMPRESAS_DETECTADAS[$i]}"
      local arquivo_instancia="${INSTANCIAS_DETECTADAS[$i]}"
      
      # Salvar variáveis atuais antes de carregar
      local empresa_original="${empresa:-}"
      local subdominio_backend_original="${subdominio_backend:-}"
      local subdominio_frontend_original="${subdominio_frontend:-}"
      
      # Tentar carregar informações adicionais da instância
      source "$arquivo_instancia" 2>/dev/null
      
      local temp_subdominio_backend="${subdominio_backend:-}"
      local temp_subdominio_frontend="${subdominio_frontend:-}"
      
      # Restaurar variáveis originais
      empresa="${empresa_original}"
      subdominio_backend="${subdominio_backend_original}"
      subdominio_frontend="${subdominio_frontend_original}"
      
      printf "${BLUE}  [$index]${WHITE} Empresa: ${GREEN}${empresa_nome}${WHITE}\n"
      if [ -n "${temp_subdominio_backend}" ]; then
        printf "      Backend: ${YELLOW}${temp_subdominio_backend}${WHITE}\n"
      fi
      if [ -n "${temp_subdominio_frontend}" ]; then
        printf "      Frontend: ${YELLOW}${temp_subdominio_frontend}${WHITE}\n"
      fi
      echo
      ((index++))
    done
    
    printf "${WHITE}═══════════════════════════════════════════════════════════\n${WHITE}"
    echo
    printf "${YELLOW} >> Qual instância deseja atualizar? (1-${total_instancias}):${WHITE}\n"
    read -p "> " escolha_instancia
    
    # Validar entrada
    if ! [[ "$escolha_instancia" =~ ^[0-9]+$ ]]; then
      printf "${RED} >> ERRO: Entrada inválida. Digite um número.${WHITE}\n"
      sleep 2
      return 1
    fi
    
    if [ "$escolha_instancia" -lt 1 ] || [ "$escolha_instancia" -gt $total_instancias ]; then
      printf "${RED} >> ERRO: Opção inválida. Escolha um número entre 1 e ${total_instancias}.${WHITE}\n"
      sleep 2
      return 1
    fi
    
    # Carregar variáveis da instância selecionada
    local indice_selecionado=$((escolha_instancia - 1))
    source "${INSTANCIAS_DETECTADAS[$indice_selecionado]}"
    # Salvar arquivo usado em variável global para uso posterior
    declare -g ARQUIVO_VARIAVEIS_USADO="${INSTANCIAS_DETECTADAS[$indice_selecionado]}"
    
    printf "${GREEN} >> Instância selecionada: ${BLUE}${empresa}${WHITE}\n"
    echo
    sleep 2
    return 0
  fi
}

# Carregar variáveis
dummy_carregar_variaveis() {
  if [ -f $ARQUIVO_VARIAVEIS ]; then
    source $ARQUIVO_VARIAVEIS
  else
    empresa="multiflow"
    nome_titulo="MultiFlow"
  fi
}

# Quando apt update falha (ex.: repo postgresql.org 404 em sources.list.d), NodeSource aborta.
# Este fallback baixa o tarball oficial de nodejs.org — não depende de apt.
instalar_node_fallback_tarball_oficial() {
  local NODE_TARGET="${1:-20.19.4}"
  local V="v${NODE_TARGET}"
  local ARCH_RAW MACHINE NAME URL TMP
  ARCH_RAW=$(uname -m)
  case "$ARCH_RAW" in
    x86_64) MACHINE=x64 ;;
    aarch64) MACHINE=arm64 ;;
    *)
      printf '%s\n' "ERRO: arquitetura não suportada para tarball Node: ${ARCH_RAW}" >&2
      return 1
      ;;
  esac
  NAME="node-${V}-linux-${MACHINE}"
  URL="https://nodejs.org/dist/${V}/${NAME}.tar.xz"
  TMP="/tmp/${NAME}.tar.xz"
  printf '%s\n' ">> Baixando ${NAME} de nodejs.org (sem apt)..."
  curl -fsSL "$URL" -o "$TMP" || return 1
  sudo tar -xJf "$TMP" -C /usr/local --strip-components=1 || return 1
  rm -f "$TMP"
  sudo mkdir -p "/usr/local/n/versions/node/${NODE_TARGET}/bin"
  sudo ln -sf /usr/local/bin/node "/usr/local/n/versions/node/${NODE_TARGET}/bin/node"
  sudo ln -sf /usr/local/bin/npm "/usr/local/n/versions/node/${NODE_TARGET}/bin/npm"
  sudo ln -sf /usr/local/bin/npx "/usr/local/n/versions/node/${NODE_TARGET}/bin/npx" 2>/dev/null || true
  sudo ln -sf /usr/local/bin/node /usr/bin/node
  sudo ln -sf /usr/local/bin/npm /usr/bin/npm
  sudo ln -sf /usr/local/bin/npx /usr/bin/npx 2>/dev/null || true
  export PATH="/usr/local/bin:/usr/bin:${PATH:-}"
  command -v node >/dev/null 2>&1 && command -v npm >/dev/null 2>&1 || return 1
  [ "$(node -v | sed 's/v//')" = "$NODE_TARGET" ] || return 1
  printf '%s\n' ">> Node ${NODE_TARGET} instalado via tarball oficial."
  return 0
}

# Função para verificar e instalar Node.js 20.19.4
# Não remove Node/npm antes de instalar a nova versão (evita servidor sem node se apt/curl falhar).
# O bloco antigo usava purge + "|| true" no NodeSource e terminava com printf de sucesso, mascarando falhas.
verificar_e_instalar_nodejs() {
  printf "${WHITE} >> Verificando versão do Node.js instalada...\n"
  
  NODE_TARGET="20.19.4"
  export PATH="/usr/local/bin:/usr/bin:${PATH:-}"
  if [ -d "/usr/local/n/versions/node/${NODE_TARGET}/bin" ]; then
    export PATH="/usr/local/n/versions/node/${NODE_TARGET}/bin:$PATH"
  fi
  
  if command -v node >/dev/null 2>&1; then
    NODE_VERSION=$(node -v | sed 's/v//')
    printf "${BLUE} >> Versão atual do Node.js: ${NODE_VERSION}\n"
    if [ "$NODE_VERSION" = "$NODE_TARGET" ]; then
      printf "${GREEN} >> Node.js já está na versão correta (${NODE_TARGET}). Prosseguindo...\n"
      sleep 2
      return 0
    fi
  else
    printf "${YELLOW} >> Node.js não encontrado no PATH do root (será instalado).\n"
  fi
  
  printf "${YELLOW} >> Ajustando para Node.js ${NODE_TARGET} (mantém a instalação atual até a nova estar pronta).\n"
  
  (
    set -e
    if ! command -v npm >/dev/null 2>&1; then
      echo "=== npm ausente: tentando NodeSource + apt ==="
      sudo rm -f /etc/apt/sources.list.d/nodesource.list 2>/dev/null || true
      sudo rm -f /etc/apt/sources.list.d/nodesource*.list 2>/dev/null || true
      if curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash - \
        && sudo apt-get update -y \
        && sudo DEBIAN_FRONTEND=noninteractive apt-get install -y nodejs \
        && command -v npm >/dev/null 2>&1; then
        echo "=== Node + npm via apt OK ==="
      else
        echo "=== apt/nodesource falhou (ex.: outro .list com 404 — comum: apt.postgresql.org pgdg). Tentando tarball nodejs.org ==="
        instalar_node_fallback_tarball_oficial "${NODE_TARGET}" || { echo "ERRO: tarball oficial também falhou."; exit 1; }
      fi
      command -v npm >/dev/null 2>&1 || { echo "ERRO: npm ainda ausente após instalação."; exit 1; }
    fi

    if [ "$(node -v | sed 's/v//')" != "${NODE_TARGET}" ]; then
      echo "=== Instalando gerenciador n (global) ==="
      sudo npm install -g n
      echo "=== Instalando Node.js ${NODE_TARGET} via n ==="
      sudo n "${NODE_TARGET}"
    else
      echo "=== Já em Node ${NODE_TARGET} (apt ou tarball), pulando n ==="
    fi
    
    test -x "/usr/local/n/versions/node/${NODE_TARGET}/bin/node"
    test -x "/usr/local/n/versions/node/${NODE_TARGET}/bin/npm"
    
    echo "=== Links em /usr/bin ==="
    sudo ln -sf "/usr/local/n/versions/node/${NODE_TARGET}/bin/node" /usr/bin/node
    sudo ln -sf "/usr/local/n/versions/node/${NODE_TARGET}/bin/npm" /usr/bin/npm
    sudo ln -sf "/usr/local/n/versions/node/${NODE_TARGET}/bin/npx" /usr/bin/npx 2>/dev/null || true
    
    if ! grep -q "/usr/local/n/versions/node/${NODE_TARGET}" /etc/profile 2>/dev/null; then
      echo "export PATH=/usr/local/n/versions/node/${NODE_TARGET}/bin:/usr/bin:\$PATH" | sudo tee -a /etc/profile > /dev/null
    fi
    
    export PATH="/usr/local/n/versions/node/${NODE_TARGET}/bin:/usr/bin:$PATH"
    echo "=== Conferência ==="
    node -v
    npm -v
    [ "$(node -v | sed 's/v//')" = "${NODE_TARGET}" ] || { echo "ERRO: versão final não é ${NODE_TARGET}"; exit 1; }
  ) || trata_erro "verificar_e_instalar_nodejs"
  
  printf "${GREEN}✅ Node.js ${NODE_TARGET} instalado e ativo.${WHITE}\n"
  sleep 2
}

# Funções de atualização
backup_app_atualizar() {

  dummy_carregar_variaveis
  
  # Verifica se a variável empresa está definida
  if [ -z "${empresa}" ]; then
    printf "${RED} >> ERRO: Variável 'empresa' não está definida!\n${WHITE}"
    exit 1
  fi
  
  # Verifica se o arquivo .env existe
  ENV_FILE="/home/deploy/${empresa}/backend/.env"
  if [ ! -f "$ENV_FILE" ]; then
    printf "${YELLOW} >> AVISO: Arquivo .env não encontrado em $ENV_FILE. Pulando backup.\n${WHITE}"
    return 0
  fi
  
  source "$ENV_FILE"
  {
    printf "${WHITE} >> Fazendo backup do banco de dados da empresa ${empresa}...\n"
    db_password=$(grep "DB_PASS=" "$ENV_FILE" | cut -d '=' -f2)
    [ ! -d "/home/deploy/backups" ] && mkdir -p "/home/deploy/backups"
    backup_file="/home/deploy/backups/${empresa}_$(date +%d-%m-%Y_%Hh).sql"
    PGPASSWORD="${db_password}" pg_dump -U ${empresa} -h localhost ${empresa} >"${backup_file}"
    printf "${GREEN} >> Backup do banco de dados ${empresa} concluído. Arquivo de backup: ${backup_file}\n"
    sleep 2
  } || trata_erro "backup_app_atualizar"

# Dados do Whaticket
TOKEN="ultranotificacoes"
QUEUE_ID="15"
USER_ID=""
MENSAGEM="🚨 INICIANDO Atualização do ${nome_titulo}"

# Lista de números
NUMEROS=("${numero_suporte}" "5518988029627")

# Enviar para cada número
for NUMERO in "${NUMEROS[@]}"; do
  curl -s -X POST https://apiweb.ultrawhats.com.br/api/messages/send \
    -H "Authorization: Bearer $TOKEN" \
    -H "Content-Type: application/json" \
    -d '{
      "number": "'"$NUMERO"'",
      "body": "'"$MENSAGEM"'",
      "userId": "'"$USER_ID"'",
      "queueId": "'"$QUEUE_ID"'",
      "sendSignature": false,
      "closeTicket": true
    }'
done
  
}

otimiza_banco_atualizar() {
  printf "${WHITE} >> Realizando Manutenção do Banco de Dados da empresa ${empresa}... \n"
  
  # Verifica se a variável empresa está definida
  if [ -z "${empresa}" ]; then
    printf "${RED} >> ERRO: Variável 'empresa' não está definida!\n${WHITE}"
    exit 1
  fi
  
  # Verifica se o arquivo .env existe
  ENV_FILE="/home/deploy/${empresa}/backend/.env"
  if [ ! -f "$ENV_FILE" ]; then
    printf "${YELLOW} >> AVISO: Arquivo .env não encontrado em $ENV_FILE. Pulando otimização do banco.\n${WHITE}"
    return 0
  fi
  
  [ -f "$ARQUIVO_VARIAVEIS" ] && source "$ARQUIVO_VARIAVEIS" 2>/dev/null
  if [ "${ALTA_PERFORMANCE}" = "1" ]; then
    db_host_opt="127.0.0.1"
    db_port_opt="7532"
  else
    db_host_opt="localhost"
    db_port_opt="5432"
  fi
  
  {
    db_password=$(grep "DB_PASS=" "$ENV_FILE" | cut -d '=' -f2)
    if [ -z "$db_password" ]; then
      printf "${YELLOW} >> AVISO: Senha do banco não encontrada. Pulando otimização.\n${WHITE}"
      return 0
    fi
    sudo su - root <<EOF
    PGPASSWORD="$db_password" vacuumdb -U "${empresa}" -h ${db_host_opt} -p ${db_port_opt} -d "${empresa}" --full --analyze
    PGPASSWORD="$db_password" psql -U ${empresa} -h ${db_host_opt} -p ${db_port_opt} -d ${empresa} -c "REINDEX DATABASE ${empresa};"
    PGPASSWORD="$db_password" psql -U ${empresa} -h ${db_host_opt} -p ${db_port_opt} -d ${empresa} -c "ANALYZE;"
EOF
    sleep 2
  } || trata_erro "otimiza_banco_atualizar"
}

# Após alteração ao .env como root (mktemp+mv), garantir dono deploy (ver instalador_single.sh).
garantir_permissoes_env_backend() {
  local env_file="$1"
  [ -z "$env_file" ] || [ ! -f "$env_file" ] && return 0
  chown deploy:deploy "$env_file" 2>/dev/null || true
  chmod 600 "$env_file" 2>/dev/null || true
}

# Alta Performance: REDIS_URI_ACK = REDIS_URI (ver deve_sincronizar em instalador_single.sh).
deve_sincronizar_redis_uri_ack_com_redis_uri() {
  local env_file="$1"
  grep -q '^DB_PORT=6732' "$env_file" 2>/dev/null && return 0
  [ "${ALTA_PERFORMANCE:-0}" = "1" ] && return 0
  return 1
}

sincronizar_redis_uri_ack_com_redis_uri_se_ap() {
  local env_file="$1"
  [ ! -f "$env_file" ] && return 0
  deve_sincronizar_redis_uri_ack_com_redis_uri "$env_file" || return 0
  local redis_main
  redis_main=$(grep -m1 '^REDIS_URI=' "$env_file" 2>/dev/null | cut -d= -f2- | tr -d '\r')
  [ -z "$redis_main" ] && return 0
  if ! grep -q '^REDIS_URI_ACK=' "$env_file" 2>/dev/null; then
    return 0
  fi
  local tmp
  tmp=$(mktemp)
  while IFS= read -r line || [ -n "$line" ]; do
    if [[ "$line" == REDIS_URI_ACK=* ]]; then
      printf 'REDIS_URI_ACK=%s\n' "$redis_main"
    else
      printf '%s\n' "$line"
    fi
  done < "$env_file" > "$tmp" && mv "$tmp" "$env_file"
  garantir_permissoes_env_backend "$env_file"
  return 0
}

# Ativa REDIS_URI_ACK e Bull Board no .env do backend (backend/package.json >= 7.4.1).
descomentar_env_redis_bull_ack() {
  local env_file="$1"
  local pkg_json="${2:-}"
  local redis_ack_val_append="${3:-}"
  [ -z "$pkg_json" ] && pkg_json="$(dirname "$env_file")/package.json"
  [ ! -f "$env_file" ] && return 0
  [ ! -f "$pkg_json" ] && return 0
  _mf_fix_env_owner_descomentar() { garantir_permissoes_env_backend "$env_file"; }
  trap '_mf_fix_env_owner_descomentar' RETURN
  local ver
  ver=$(grep -m1 '"version"' "$pkg_json" 2>/dev/null | sed -n 's/.*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')
  [ -z "$ver" ] && return 0
  if [ "$(printf '%s\n' "$ver" "7.4.1" | sort -V | head -1)" != "7.4.1" ]; then
    return 0
  fi
  local redis_main_val
  redis_main_val=$(grep -m1 '^REDIS_URI=' "$env_file" 2>/dev/null | cut -d= -f2- | tr -d '\r')
  if grep -q '^REDIS_URI_ACK=' "$env_file" 2>/dev/null; then
    sincronizar_redis_uri_ack_com_redis_uri_se_ap "$env_file"
    printf "${GREEN} >> REDIS_URI_ACK / Bull Board já ativos no .env (backend ${ver}).${WHITE}\n"
    return 0
  fi
  if grep -q '^# REDIS_URI_ACK=' "$env_file" 2>/dev/null; then
    sed -i 's/^# REDIS_URI_ACK=/REDIS_URI_ACK=/' "$env_file"
    sed -i 's/^# BULL_BOARD=/BULL_BOARD=/' "$env_file"
    sed -i 's/^# BULL_USER=/BULL_USER=/' "$env_file"
    sed -i 's/^# BULL_PASS=/BULL_PASS=/' "$env_file"
    sincronizar_redis_uri_ack_com_redis_uri_se_ap "$env_file"
    printf "${GREEN} >> REDIS_URI_ACK / Bull Board ativados no .env (backend ${ver} >= 7.4.1).${WHITE}\n"
    return 0
  fi
  local db_pass bull_user
  db_pass=$(grep '^DB_PASS=' "$env_file" 2>/dev/null | cut -d= -f2- | tr -d '"' | head -1)
  bull_user=$(grep '^MAIL_USER=' "$env_file" 2>/dev/null | cut -d= -f2- | tr -d '"' | head -1)
  [ -z "$db_pass" ] && return 0
  [ -z "$bull_user" ] && bull_user="admin@localhost"
  {
    echo ""
    if [ -n "$redis_ack_val_append" ]; then
      echo "REDIS_URI_ACK=${redis_ack_val_append}"
    elif deve_sincronizar_redis_uri_ack_com_redis_uri "$env_file" && [ -n "$redis_main_val" ]; then
      echo "REDIS_URI_ACK=${redis_main_val}"
    else
      echo "REDIS_URI_ACK=redis://:${db_pass}@127.0.0.1:6379"
    fi
    echo "BULL_BOARD=true"
    echo "BULL_USER=${bull_user}"
    echo "BULL_PASS=${db_pass}"
  } >> "$env_file"
  sincronizar_redis_uri_ack_com_redis_uri_se_ap "$env_file"
  printf "${GREEN} >> REDIS_URI_ACK / Bull Board adicionados ao .env (backend ${ver} >= 7.4.1).${WHITE}\n"
}

baixa_codigo_atualizar() {
  # Verifica se a variável empresa está definida
  if [ -z "${empresa}" ]; then
    printf "${RED} >> ERRO: Variável 'empresa' não está definida!\n${WHITE}"
    dummy_carregar_variaveis
    if [ -z "${empresa}" ]; then
      printf "${RED} >> ERRO: Não foi possível carregar a variável 'empresa'. Abortando.\n${WHITE}"
      exit 1
    fi
  fi
  
  # Verifica se o diretório existe
  if [ ! -d "/home/deploy/${empresa}" ]; then
    printf "${RED} >> ERRO: Diretório /home/deploy/${empresa} não existe!\n${WHITE}"
    exit 1
  fi
  
  printf "${WHITE} >> Recuperando Permissões da empresa ${empresa}... \n"
  sleep 2
  chown deploy -R /home/deploy/${empresa}
  chmod 775 -R /home/deploy/${empresa}

  sleep 2

  printf "${WHITE} >> Parando Instancias da empresa ${empresa}... \n"
  sleep 2
  sudo su - deploy <<STOPPM2
  export PATH="/usr/local/bin:/usr/bin:\${PATH:-}"
  if [ -d /usr/local/n/versions/node/20.19.4/bin ]; then
    export PATH="/usr/local/n/versions/node/20.19.4/bin:\$PATH"
  elif [ -d /usr/local/n/versions/node ]; then
    _mf_nv=\$(ls -1 /usr/local/n/versions/node 2>/dev/null | sort -V | tail -1)
    if [ -n "\$_mf_nv" ] && [ -d "/usr/local/n/versions/node/\$_mf_nv/bin" ]; then
      export PATH="/usr/local/n/versions/node/\$_mf_nv/bin:\$PATH"
    fi
  fi
  # Parar processos da instância (nomes fixos; tabela pm2 list + awk costuma falhar)
  for _p in "${empresa}-backend" "${empresa}-frontend" "${empresa}-transcricao"; do
    pm2 stop "\$_p" 2>/dev/null || true
  done
STOPPM2

  sleep 2

  otimiza_banco_atualizar

  printf "${WHITE} >> Atualizando a Aplicação da Empresa ${empresa}... \n"
  sleep 2

  source /home/deploy/${empresa}/frontend/.env 2>/dev/null || true
  frontend_port=${SERVER_PORT:-3000}
  sudo su - deploy <<UPDATEAPP
  # Configura PATH para Node.js e PM2
  if [ -d /usr/local/n/versions/node/20.19.4/bin ]; then
    export PATH=/usr/local/n/versions/node/20.19.4/bin:/usr/bin:/usr/local/bin:\$PATH
  else
    export PATH=/usr/bin:/usr/local/bin:\$PATH
  fi
  
  APP_DIR="/home/deploy/${empresa}"
  BACKEND_DIR="\${APP_DIR}/backend"
  FRONTEND_DIR="\${APP_DIR}/frontend"
  
  # Verifica se os diretórios existem
  if [ ! -d "\$APP_DIR" ]; then
    echo "ERRO: Diretório da aplicação não existe: \$APP_DIR"
    exit 1
  fi
  
  printf "${WHITE} >> Atualizando Backend...\n"
  echo
  cd "\$APP_DIR"
  
  git fetch origin
  git checkout MULTI100-OFICIAL-u21
  git reset --hard origin/MULTI100-OFICIAL-u21
  
  if [ ! -d "\$BACKEND_DIR" ]; then
    echo "ERRO: Diretório do backend não existe: \$BACKEND_DIR"
    exit 1
  fi
  
  cd "\$BACKEND_DIR"
  
  if [ ! -f "package.json" ]; then
    echo "ERRO: package.json não encontrado em \$BACKEND_DIR"
    exit 1
  fi
  
  npm prune --force > /dev/null 2>&1
  export PUPPETEER_SKIP_DOWNLOAD=true
  rm -rf node_modules 2>/dev/null || true
  rm -f package-lock.json 2>/dev/null || true
  rm -rf dist 2>/dev/null || true
  npm install --force
  npm install puppeteer-core --force
  npm i glob
  npm run build
  sleep 2
  printf "${WHITE} >> Atualizando Banco da empresa ${empresa}...\n"
  echo
  sleep 2
  npx sequelize db:migrate
  sleep 2
  printf "${WHITE} >> Atualizando Frontend da ${empresa}...\n"
  echo
  sleep 2
  
  if [ ! -d "\$FRONTEND_DIR" ]; then
    echo "ERRO: Diretório do frontend não existe: \$FRONTEND_DIR"
    exit 1
  fi
  
  cd "\$FRONTEND_DIR"
  
  if [ ! -f "package.json" ]; then
    echo "ERRO: package.json não encontrado em \$FRONTEND_DIR"
    exit 1
  fi
  
  npm prune --force > /dev/null 2>&1
  rm -rf node_modules 2>/dev/null || true
  rm -f package-lock.json 2>/dev/null || true
  npm install --force
  
  if [ -f "server.js" ]; then
    sed -i 's/3000/'"$frontend_port"'/g' server.js
  fi
  
  NODE_OPTIONS="--max-old-space-size=4096 --openssl-legacy-provider" npm run build
  sleep 2
UPDATEAPP

  descomentar_env_redis_bull_ack "/home/deploy/${empresa}/backend/.env" "/home/deploy/${empresa}/backend/package.json"

  sudo su - deploy <<RESTARTPM2ATUALIZACAO
  if [ -d /usr/local/n/versions/node/20.19.4/bin ]; then
    export PATH=/usr/local/n/versions/node/20.19.4/bin:/usr/bin:/usr/local/bin:\$PATH
  else
    export PATH=/usr/bin:/usr/local/bin:\$PATH
  fi
  for _p in "${empresa}-backend" "${empresa}-frontend" "${empresa}-transcricao"; do
    pm2 restart "\$_p" 2>/dev/null || true
  done
  pm2 save
RESTARTPM2ATUALIZACAO

  sudo su - root <<EOF
    if systemctl is-active --quiet nginx; then
      sudo systemctl restart nginx
    elif systemctl is-active --quiet traefik; then
      sudo systemctl restart traefik.service
    else
      printf "${GREEN}Nenhum serviço de proxy (Nginx ou Traefik) está em execução.${WHITE}"
    fi
EOF

  echo
  printf "${WHITE} >> Atualização do ${nome_titulo} concluída...\n"
  echo
  sleep 5

# Dados do Whaticket
TOKEN="ultranotificacoes"
QUEUE_ID="15"
USER_ID=""
MENSAGEM="🚨 Atualização do ${nome_titulo} FINALIZADA"

# Lista de números
NUMEROS=("${numero_suporte}" "5518988029627")

# Enviar para cada número
for NUMERO in "${NUMEROS[@]}"; do
  curl -s -X POST https://apiweb.ultrawhats.com.br/api/messages/send \
    -H "Authorization: Bearer $TOKEN" \
    -H "Content-Type: application/json" \
    -d '{
      "number": "'"$NUMERO"'",
      "body": "'"$MENSAGEM"'",
      "userId": "'"$USER_ID"'",
      "queueId": "'"$QUEUE_ID"'",
      "sendSignature": false,
      "closeTicket": true
    }'
done

}

# Execução automática do fluxo de atualização

# Verificar e selecionar instância para atualizar
if ! selecionar_instancia_atualizar; then
  printf "${RED} >> Erro ao selecionar instância. Encerrando script...${WHITE}\n"
  exit 1
fi

verificar_e_instalar_nodejs
backup_app_atualizar
baixa_codigo_atualizar
