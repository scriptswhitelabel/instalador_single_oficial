#!/bin/bash
# Atualização FAST automática (sem menus): sempre última versão Git + API Oficial + WhatsMeow se houver mudança.
# Uso: bash atualizador_fast_sistema.sh [empresa]
#      MF_EMPRESA=zapp360 bash atualizador_fast_sistema.sh

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

INSTALADOR_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [ "$EUID" -ne 0 ]; then
  echo
  printf "${WHITE} >> Este script precisa ser executado como root ${RED}ou com privilégios de superusuário${WHITE}.\n"
  echo
  exit 1
fi

# --- Modo sistema: empresa por argumento, env ou única instância detectada ---
sistema_resolver_empresa() {
  local emp_arg="${1:-${MF_EMPRESA:-}}"
  INSTALADOR_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  ARQUIVO_VARIAVEIS="VARIAVEIS_INSTALACAO"

  if [ -n "$emp_arg" ]; then
    if [ -f "${INSTALADOR_DIR}/VARIAVEIS_INSTALACAO" ]; then
      # shellcheck source=/dev/null
      source "${INSTALADOR_DIR}/VARIAVEIS_INSTALACAO" 2>/dev/null
      if [ "${empresa:-}" = "$emp_arg" ] && [ -d "/home/deploy/${emp_arg}/backend" ]; then
        declare -g ARQUIVO_VARIAVEIS_USADO="${INSTALADOR_DIR}/VARIAVEIS_INSTALACAO"
        empresa="$emp_arg"
        return 0
      fi
    fi
    shopt -s nullglob
    local arq
    for arq in "${INSTALADOR_DIR}"/VARIAVEIS_INSTALACAO_INSTANCIA_*; do
      [ -f "$arq" ] || continue
      local e2
      e2=$(grep -m1 '^empresa=' "$arq" 2>/dev/null | cut -d '=' -f2- | tr -d '\r')
      if [ "$e2" = "$emp_arg" ] && [ -d "/home/deploy/${emp_arg}/backend" ]; then
        declare -g ARQUIVO_VARIAVEIS_USADO="$arq"
        # shellcheck source=/dev/null
        source "$arq" 2>/dev/null
        empresa="$emp_arg"
        shopt -u nullglob
        return 0
      fi
    done
    shopt -u nullglob
    if [ -d "/home/deploy/${emp_arg}/backend" ]; then
      empresa="$emp_arg"
      declare -g ARQUIVO_VARIAVEIS_USADO=""
      return 0
    fi
    printf "${RED} >> Instância '${emp_arg}' não encontrada em /home/deploy.${WHITE}\n"
    return 1
  fi

  detectar_instancias_instaladas
  local total=${#INSTANCIAS_DETECTADAS[@]}
  if [ "$total" -eq 0 ]; then
    printf "${RED} >> Nenhuma instância instalada detectada.${WHITE}\n"
    return 1
  fi
  if [ "$total" -gt 1 ]; then
    printf "${RED} >> Várias instâncias detectadas. Informe a empresa: bash atualizador_fast_sistema.sh <empresa>${WHITE}\n"
    local i
    for i in "${!NOMES_EMPRESAS_DETECTADAS[@]}"; do
      printf "   - ${NOMES_EMPRESAS_DETECTADAS[$i]}\n"
    done
    return 1
  fi
  # shellcheck source=/dev/null
  source "${INSTANCIAS_DETECTADAS[0]}"
  declare -g ARQUIVO_VARIAVEIS_USADO="${INSTANCIAS_DETECTADAS[0]}"
  printf "${GREEN} >> Instância: ${BLUE}${empresa}${WHITE}\n"
  return 0
}

sistema_atualizar_api_oficial() {
  if [ ! -d "/home/deploy/${empresa}/api_oficial" ]; then
    printf "${WHITE} >> API Oficial não instalada; etapa ignorada.${WHITE}\n"
    return 0
  fi

  printf "${WHITE} >> Atualizando API Oficial (${empresa})...${WHITE}\n"
  if ! sudo su - deploy <<EOF
set -e
if [ -f /root/instalador_single_oficial/tools/path_node_deploy.sh ]; then
  . /root/instalador_single_oficial/tools/path_node_deploy.sh
else
  export PATH="/usr/local/bin:/usr/bin:\${PATH:-}"
  [ -d /usr/local/n/versions/node/20.19.4/bin ] && export PATH="/usr/local/n/versions/node/20.19.4/bin:\$PATH"
fi
cd /home/deploy/${empresa}
git reset --hard
git pull
cd /home/deploy/${empresa}/api_oficial
npm install
npx prisma generate
npm run build
npx prisma migrate deploy
npx prisma generate
EOF
  then
    printf "${RED} >> Falha ao atualizar API Oficial.${WHITE}\n"
    return 1
  fi

  sudo su - deploy <<EOF
set +e
if [ -f /root/instalador_single_oficial/tools/path_node_deploy.sh ]; then
  . /root/instalador_single_oficial/tools/path_node_deploy.sh
else
  export PATH="/usr/local/bin:/usr/bin:\${PATH:-}"
  [ -d /usr/local/n/versions/node/20.19.4/bin ] && export PATH="/usr/local/n/versions/node/20.19.4/bin:\$PATH"
fi
cd /home/deploy/${empresa}/api_oficial
pm2 restart api_oficial_${empresa} 2>/dev/null || pm2 restart api_oficial 2>/dev/null || pm2 start dist/main.js --name api_oficial_${empresa}
pm2 save
EOF
  printf "${GREEN} >> API Oficial atualizada.${WHITE}\n"
  return 0
}

sistema_atualizar_whatsmeow() {
  local wz_script="${INSTALADOR_DIR}/instalador_whatsmeow.sh"
  if [ ! -f "$wz_script" ]; then
    wz_script="/root/instalador_single_oficial/instalador_whatsmeow.sh"
  fi
  if [ ! -f "$wz_script" ]; then
    printf "${YELLOW} >> instalador_whatsmeow.sh não encontrado; WhatsMeow ignorado.${WHITE}\n"
    return 0
  fi
  bash "$wz_script" --atualizar-sistema "${empresa}"
}

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
  INSTALADOR_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
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

# Versões (tools/versoes_multiflow_pro.conf — mesma lista da instalação / atualização completa)
definir_versoes_instalacao() {
  local _mf_loader
  _mf_loader="${INSTALADOR_DIR}/tools/carregar_versoes_multiflow_pro.sh"
  # shellcheck source=/dev/null
  source "$_mf_loader" || true
  if ! mf_carregar_versoes_no_array "VERSOES_INSTALACAO"; then
    printf "${RED} >> ERRO: não foi possível carregar versões. Verifique tools/versoes_multiflow_pro.conf (formato: versao|commit).${WHITE}\n"
    return 1
  fi
  return 0
}

mostrar_lista_versoes_instalacao() {
  printf "${WHITE}═══════════════════════════════════════════════════════════\n"
  printf "  VERSÕES DISPONÍVEIS %s\n" "${TITULO_LISTA_VERSOES:-PARA ATUALIZAÇÃO}"
  printf "═══════════════════════════════════════════════════════════\n${WHITE}"
  echo

  printf "${BLUE}  [0]${WHITE} Mais Recente ${YELLOW}${MF_AVISO_OPCAO_MAIS_RECENTE}${WHITE}\n"
  printf "      Usa a última revisão da branch oficial do repositório\n"
  echo

  local index=1
  for versao in $(printf '%s\n' "${!VERSOES_INSTALACAO[@]}" | sort -V -r); do
    printf "${BLUE}  [$index]${WHITE} "
    mf_exibir_rotulo_versao_menu "$versao" "VERSOES_INSTALACAO"
    printf "Versão ${GREEN}${versao}${WHITE}\n"
    printf "      Commit: ${YELLOW}${VERSOES_INSTALACAO[$versao]}${WHITE}\n"
    echo
    ((index++))
  done

  printf "${WHITE}═══════════════════════════════════════════════════════════\n${WHITE}"
  echo
}

selecionar_versao_atualizacao() {
  banner
  printf "${WHITE} >> Selecionando versão para atualização FAST...\n"
  echo

  if ! echo "${repo_url:-}" | grep -q "scriptswhitelabel/multiflow-pro"; then
    declare -g versao_atualizacao="Mais_Recente"
    declare -g commit_atualizacao=""
    printf "${GREEN} >> Atualização padrão: branch principal do repositório.${WHITE}\n"
    echo
    sleep 1
    return 0
  fi

  if ! definir_versoes_instalacao; then
    sleep 2
    return 1
  fi

  TITULO_LISTA_VERSOES="PARA ATUALIZAÇÃO FAST"
  mostrar_lista_versoes_instalacao
  unset TITULO_LISTA_VERSOES

  local versoes_array=($(printf '%s\n' "${!VERSOES_INSTALACAO[@]}" | sort -V -r))
  local total_versoes=${#versoes_array[@]}

  if [ "$total_versoes" -eq 0 ]; then
    printf "${RED} >> ERRO: Nenhuma versão disponível na lista.\n${WHITE}"
    sleep 2
    return 1
  fi

  printf "${YELLOW} >> Selecione a versão desejada (0-${total_versoes}):${WHITE}\n"
  read -p "> " ESCOLHA_ATUALIZACAO

  if ! [[ "$ESCOLHA_ATUALIZACAO" =~ ^[0-9]+$ ]]; then
    printf "${RED} >> ERRO: Entrada inválida. Digite um número.\n${WHITE}"
    sleep 2
    return 1
  fi

  if [ "$ESCOLHA_ATUALIZACAO" -lt 0 ] || [ "$ESCOLHA_ATUALIZACAO" -gt "$total_versoes" ]; then
    printf "${RED} >> ERRO: Opção inválida. Escolha um número entre 0 e ${total_versoes}.\n${WHITE}"
    sleep 2
    return 1
  fi

  if [ "$ESCOLHA_ATUALIZACAO" -eq 0 ]; then
    declare -g versao_atualizacao="Mais_Recente"
    declare -g commit_atualizacao=""
    printf "\n${GREEN} >> Versão selecionada: ${BLUE}Mais Recente${WHITE} ${YELLOW}${MF_AVISO_OPCAO_MAIS_RECENTE}${WHITE}\n"
    printf "${GREEN} >> Será usada a última revisão da branch MULTI100-OFICIAL-u21${WHITE}\n"
  else
    local index=$((ESCOLHA_ATUALIZACAO - 1))
    declare -g versao_atualizacao="${versoes_array[$index]}"
    declare -g commit_atualizacao="${VERSOES_INSTALACAO[$versao_atualizacao]}"
    printf "\n${GREEN} >> Versão selecionada: ${BLUE}${versao_atualizacao}${WHITE}\n"
    printf "${GREEN} >> Commit: ${BLUE}${commit_atualizacao}${WHITE}\n"
  fi
  echo
  sleep 2
  return 0
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

carregar_credenciais_instancia() {
  if [ -n "${ARQUIVO_VARIAVEIS_USADO:-}" ] && [ -f "${ARQUIVO_VARIAVEIS_USADO}" ]; then
    # shellcheck source=/dev/null
    source "${ARQUIVO_VARIAVEIS_USADO}"
  fi
}

# Multiflow-pro: TOKEN_GITHUB no package.json (baileys) — o git checkout restaura o placeholder
aplicar_token_baileys_package_json() {
  local emp="${1:-$empresa}"
  local tok="${2:-$github_token}"
  local repo="${3:-$repo_url}"
  echo "$repo" | grep -q "scriptswhitelabel/multiflow-pro" || return 0
  [ -z "$tok" ] && return 1
  local pkg="/home/deploy/${emp}/backend/package.json"
  [ ! -f "$pkg" ] && return 1
  grep -q "TOKEN_GITHUB" "$pkg" 2>/dev/null || return 0
  local tok_sed="${tok//&/\\&}"
  sed -i "s|TOKEN_GITHUB|${tok_sed}|g" "$pkg"
  chown deploy:deploy "$pkg" 2>/dev/null || true
  printf "${GREEN} >> Token do GitHub aplicado no package.json (baileys).${WHITE}\n"
  return 0
}

instalacao_alta_performance() {
  carregar_credenciais_instancia
  [ "${ALTA_PERFORMANCE:-0}" = "1" ] && return 0

  local env_file="/home/deploy/${empresa}/backend/.env"
  if [ -f "$env_file" ]; then
    local db_port db_host
    db_port=$(grep -m1 '^DB_PORT=' "$env_file" 2>/dev/null | cut -d '=' -f2- | tr -d '\r ')
    db_host=$(grep -m1 '^DB_HOST=' "$env_file" 2>/dev/null | cut -d '=' -f2- | tr -d '\r ')
    [ "$db_port" = "6732" ] && [ "$db_host" = "127.0.0.1" ] && return 0
  fi

  docker ps --format '{{.Names}}' 2>/dev/null | grep -qx "postgres_${empresa}" && return 0
  return 1
}

backup_banco_alta_performance_fast() {
  local env_file="/home/deploy/${empresa}/backend/.env"
  local postgres_container="postgres_${empresa}"
  local backup_dir="/home/deploy/backup-bd-docker-${empresa}"
  local config_retencao="${backup_dir}/.retencao_dias"
  local retencao_dias="7"
  local data db_user db_pass db_name bancos db db_clean arquivo tmp_sql log_file

  [ -f "$env_file" ] || return 1
  db_user=$(grep -m1 '^DB_USER=' "$env_file" 2>/dev/null | cut -d '=' -f2- | tr -d '\r')
  db_pass=$(grep -m1 '^DB_PASS=' "$env_file" 2>/dev/null | cut -d '=' -f2- | tr -d '\r')
  db_name=$(grep -m1 '^DB_NAME=' "$env_file" 2>/dev/null | cut -d '=' -f2- | tr -d '\r')

  db_user="${db_user:-$empresa}"
  db_pass="${db_pass:-$senha_deploy}"
  db_name="${db_name:-$empresa}"
  [ -n "$db_pass" ] || return 1

  if ! docker ps --format '{{.Names}}' 2>/dev/null | grep -qx "$postgres_container"; then
    printf "${RED} >> Container Postgres não encontrado/rodando: ${postgres_container}${WHITE}\n"
    return 1
  fi

  mkdir -p "$backup_dir"
  chown deploy:deploy "$backup_dir" 2>/dev/null || true
  log_file="${backup_dir}/backup.log"
  if [ -f "$config_retencao" ]; then
    read -r retencao_dias < "$config_retencao" 2>/dev/null || retencao_dias="7"
  fi
  [[ "$retencao_dias" =~ ^[0-9]+$ ]] || retencao_dias="7"

  data=$(date +%Y-%m-%d_%H-%M-%S)
  bancos=$(docker exec "$postgres_container" env PGPASSWORD="$db_pass" \
    psql -h 127.0.0.1 -p 5432 -U "$db_user" -d postgres -t -A \
    -c "SELECT datname FROM pg_database WHERE datistemplate = false AND datname IS NOT NULL ORDER BY datname;" 2>> "$log_file")

  if [ -z "$bancos" ]; then
    bancos="$db_name"
    printf "${YELLOW} >> Não foi possível listar todos os bancos; tentando apenas ${db_name}.${WHITE}\n"
  fi

  for db in $bancos; do
    db_clean=$(echo "$db" | tr -d '\r\n')
    [ -z "$db_clean" ] && continue
    arquivo="${backup_dir}/backup-${db_clean}-${data}.sql.gz"
    tmp_sql=$(mktemp)
    if docker exec "$postgres_container" env PGPASSWORD="$db_pass" \
      pg_dump -h 127.0.0.1 -p 5432 -U "$db_user" -d "$db_clean" -F p > "$tmp_sql" 2>> "$log_file"; then
      gzip -c "$tmp_sql" > "$arquivo"
      chown deploy:deploy "$arquivo" 2>/dev/null || true
      printf "${GREEN} >> Backup concluído: ${arquivo}${WHITE}\n"
    else
      printf "${YELLOW} >> Aviso: falha ao gerar backup do banco ${db_clean}. Veja ${log_file}${WHITE}\n"
    fi
    rm -f "$tmp_sql"
  done

  find "$backup_dir" -maxdepth 1 -name "backup-*.sql.gz" -mtime +"$retencao_dias" -delete 2>/dev/null || true
  return 0
}

# Funções de atualização
backup_app_atualizar() {
  # Verifica se a variável empresa está definida
  if [ -z "${empresa}" ]; then
    printf "${RED} >> ERRO: Variável 'empresa' não está definida!\n${WHITE}"
    exit 1
  fi

  {
    banner
    printf "${WHITE} >> Antes de atualizar deseja fazer backup do banco de dados? ${GREEN}S/${RED}N:${WHITE}\n"
    echo
    read -p "> " confirmacao_backup
    echo
    confirmacao_backup=$(echo "${confirmacao_backup}" | tr '[:lower:]' '[:upper:]')
    if [ "${confirmacao_backup}" != "S" ]; then
      printf "${YELLOW} >> Backup ignorado. Continuando a atualização FAST...${WHITE}\n"
      sleep 2
      return 0
    fi

    if instalacao_alta_performance; then
      printf "${WHITE} >> Instalação Alta Performance detectada. Usando backup via Docker/Postgres...${WHITE}\n"
      if ! backup_banco_alta_performance_fast; then
        printf "${YELLOW} >> Aviso: falha ao gerar backup Alta Performance.${WHITE}\n"
        printf "${YELLOW} >> A atualização FAST continuará sem backup do banco.${WHITE}\n"
      fi
    else
      printf "${WHITE} >> Fazendo backup nativo do banco de dados da empresa ${empresa}...${WHITE}\n"
      MF_BACKUP_SCRIPT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/tools/mf_backup_banco_empresa.sh"
      [ -f "$MF_BACKUP_SCRIPT" ] || MF_BACKUP_SCRIPT="/root/instalador_single_oficial/tools/mf_backup_banco_empresa.sh"
      # shellcheck source=/dev/null
      source "$MF_BACKUP_SCRIPT"
      if mf_backup_banco_empresa "${empresa}"; then
        printf "${GREEN} >> Backup concluído: ${MF_BACKUP_ARQUIVO}\n"
      else
        printf "${YELLOW} >> Aviso: falha ao gerar backup em /home/deploy/backup-${empresa}/${WHITE}\n"
        printf "${YELLOW} >> A atualização FAST continuará sem backup do banco.${WHITE}\n"
      fi
    fi
    sleep 2
  } || trata_erro "backup_app_atualizar"

# Dados do Whaticket
TOKEN="ultranotificacoes"
QUEUE_ID="15"
USER_ID=""
MENSAGEM="🚨 INICIANDO Atualização "FAST" do ${nome_titulo}"

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

# otimiza_banco_atualizar() {
#   printf "${WHITE} >> Realizando Manutenção do Banco de Dados da empresa ${empresa}... \n"
#   {
#     db_password=$(grep "DB_PASS=" /home/deploy/${empresa}/backend/.env | cut -d '=' -f2)
#     sudo su - root <<EOF
#     PGPASSWORD="$db_password" vacuumdb -U "${empresa}" -h localhost -d "${empresa}" --full --analyze
#     PGPASSWORD="$db_password" psql -U ${empresa} -h 127.0.0.1 -d ${empresa} -c "REINDEX DATABASE ${empresa};"
#     PGPASSWORD="$db_password" psql -U ${empresa} -h 127.0.0.1 -d ${empresa} -c "ANALYZE;"
# EOF
#     sleep 2
#   } || trata_erro "otimiza_banco_atualizar"
# }

garantir_permissoes_env_backend() {
  local env_file="$1"
  [ -z "$env_file" ] || [ ! -f "$env_file" ] && return 0
  chown deploy:deploy "$env_file" 2>/dev/null || true
  chmod 600 "$env_file" 2>/dev/null || true
}

# Exporta apenas chaves necessárias do frontend/.env (sem source — evita "command not found" com linhas inválidas).
exportar_vars_frontend_env_seguro() {
  local fe_env="/home/deploy/${empresa}/frontend/.env"
  [ ! -f "$fe_env" ] && return 0
  export REACT_APP_LOGO_URL="$(grep -m1 '^REACT_APP_LOGO_URL=' "$fe_env" 2>/dev/null | cut -d= -f2- | tr -d '\r')"
  export REACT_APP_LOGO="$(grep -m1 '^REACT_APP_LOGO=' "$fe_env" 2>/dev/null | cut -d= -f2- | tr -d '\r')"
  export LOGO_URL="$(grep -m1 '^LOGO_URL=' "$fe_env" 2>/dev/null | cut -d= -f2- | tr -d '\r')"
  export REACT_APP_PRIMARY_COLOR="$(grep -m1 '^REACT_APP_PRIMARY_COLOR=' "$fe_env" 2>/dev/null | cut -d= -f2- | tr -d '\r')"
  export PRIMARY_COLOR="$(grep -m1 '^PRIMARY_COLOR=' "$fe_env" 2>/dev/null | cut -d= -f2- | tr -d '\r')"
  export REACT_APP_SECONDARY_COLOR="$(grep -m1 '^REACT_APP_SECONDARY_COLOR=' "$fe_env" 2>/dev/null | cut -d= -f2- | tr -d '\r')"
  export SECONDARY_COLOR="$(grep -m1 '^SECONDARY_COLOR=' "$fe_env" 2>/dev/null | cut -d= -f2- | tr -d '\r')"
}

# Verificar e adicionar MAX_BUFFER_SIZE_MB no .env do backend
  verificar_e_adicionar_max_buffer() {
  # Verifica se a variável empresa está definida
  if [ -z "${empresa}" ]; then
    printf "${RED} >> ERRO: Variável 'empresa' não está definida!\n${WHITE}"
    return 0
  fi
  
  ENV_FILE="/home/deploy/${empresa}/backend/.env"
  
  if [ ! -f "$ENV_FILE" ]; then
    printf "${YELLOW} >> AVISO: Arquivo .env não encontrado em $ENV_FILE. Pulando verificação de MAX_BUFFER_SIZE_MB.\n${WHITE}"
    return 0
  fi
  
  if ! grep -q "^MAX_BUFFER_SIZE_MB=" "$ENV_FILE"; then
    printf "${WHITE} >> Adicionando MAX_BUFFER_SIZE_MB=200 no .env do backend...\n"
    echo "" >> "$ENV_FILE"
    echo "# Buffer Size Configuration" >> "$ENV_FILE"
    echo "MAX_BUFFER_SIZE_MB=200" >> "$ENV_FILE"
    printf "${GREEN} >> Variável MAX_BUFFER_SIZE_MB adicionada com sucesso!${WHITE}\n"
  else
    printf "${GREEN} >> Variável MAX_BUFFER_SIZE_MB já existe no .env do backend.${WHITE}\n"
  fi
  garantir_permissoes_env_backend "$ENV_FILE"
}

# Verificar e adicionar WHATSAPP_WEB_VERSION no .env do backend (Baileys)
verificar_e_adicionar_whatsapp_web_version() {
  if [ -z "${empresa}" ]; then
    printf "${RED} >> ERRO: Variável 'empresa' não está definida!\n${WHITE}"
    return 0
  fi

  ENV_FILE="/home/deploy/${empresa}/backend/.env"

  if [ ! -f "$ENV_FILE" ]; then
    printf "${YELLOW} >> AVISO: Arquivo .env não encontrado em $ENV_FILE. Pulando verificação de WHATSAPP_WEB_VERSION.\n${WHITE}"
    return 0
  fi

  if ! grep -q '^WHATSAPP_WEB_VERSION=' "$ENV_FILE"; then
    printf "${WHITE} >> Adicionando WHATSAPP_WEB_VERSION ao .env do backend...\n"
    echo "" >> "$ENV_FILE"
    echo "# Opcional: fixa a versão do WhatsApp Web usada pelo Baileys. Se vazio, busca automaticamente." >> "$ENV_FILE"
    echo "WHATSAPP_WEB_VERSION=2.3000.1038235667" >> "$ENV_FILE"
    printf "${GREEN} >> WHATSAPP_WEB_VERSION adicionada ao .env do backend.${WHITE}\n"
  else
    printf "${GREEN} >> WHATSAPP_WEB_VERSION já definida no .env do backend (não alterado).${WHITE}\n"
  fi
  garantir_permissoes_env_backend "$ENV_FILE"
}

# Iguala REDIS_URI_ACK ao valor de REDIS_URI (só ao descomentar ou acrescentar ACK; ACK já ativo não é alterado).
copiar_redis_uri_para_redis_uri_ack() {
  local env_file="$1"
  [ ! -f "$env_file" ] && return 0
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
# $3 opcional: valor explícito de REDIS_URI_ACK ao acrescentar bloco; caso contrário copia só de REDIS_URI.
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
    printf "${GREEN} >> REDIS_URI_ACK / Bull Board já ativos no .env (backend ${ver}).${WHITE}\n"
    return 0
  fi
  if grep -q '^# REDIS_URI_ACK=' "$env_file" 2>/dev/null; then
    sed -i 's/^# REDIS_URI_ACK=/REDIS_URI_ACK=/' "$env_file"
    sed -i 's/^# BULL_BOARD=/BULL_BOARD=/' "$env_file"
    sed -i 's/^# BULL_USER=/BULL_USER=/' "$env_file"
    sed -i 's/^# BULL_PASS=/BULL_PASS=/' "$env_file"
    copiar_redis_uri_para_redis_uri_ack "$env_file"
    printf "${GREEN} >> REDIS_URI_ACK / Bull Board ativados no .env (backend ${ver} >= 7.4.1).${WHITE}\n"
    return 0
  fi
  local db_pass bull_user
  db_pass=$(grep '^DB_PASS=' "$env_file" 2>/dev/null | cut -d= -f2- | tr -d '"' | head -1)
  bull_user=$(grep '^MAIL_USER=' "$env_file" 2>/dev/null | cut -d= -f2- | tr -d '"' | head -1)
  [ -z "$db_pass" ] && return 0
  [ -z "$bull_user" ] && bull_user="admin@localhost"
  if [ -z "$redis_ack_val_append" ] && [ -z "$redis_main_val" ]; then
    printf "${YELLOW} >> AVISO: REDIS_URI vazio no .env; REDIS_URI_ACK não foi gravado — defina manualmente se necessário.${WHITE}\n"
  fi
  {
    echo ""
    if [ -n "$redis_ack_val_append" ]; then
      echo "REDIS_URI_ACK=${redis_ack_val_append}"
    elif [ -n "$redis_main_val" ]; then
      echo "REDIS_URI_ACK=${redis_main_val}"
    fi
    echo "BULL_BOARD=true"
    echo "BULL_USER=${bull_user}"
    echo "BULL_PASS=${db_pass}"
  } >> "$env_file"
  if [ -z "$redis_ack_val_append" ]; then
    copiar_redis_uri_para_redis_uri_ack "$env_file"
  fi
  printf "${GREEN} >> REDIS_URI_ACK / Bull Board adicionados ao .env (backend ${ver} >= 7.4.1).${WHITE}\n"
}

ativar_tela_atualizacao_frontend() {
  local frontend_dir="/home/deploy/${empresa}/frontend"
  local build_dir="${frontend_dir}/build"
  local backup_dir="${frontend_dir}/.build_pre_update"
  local logo_url="${REACT_APP_LOGO_URL:-${REACT_APP_LOGO:-${LOGO_URL:-}}}"
  local cor_primaria="${REACT_APP_PRIMARY_COLOR:-${PRIMARY_COLOR:-#2563eb}}"
  local cor_secundaria="${REACT_APP_SECONDARY_COLOR:-${SECONDARY_COLOR:-#1e3a8a}}"
  local nome_empresa="${nome_titulo:-${empresa}}"
  local logo_fallback_text
  logo_fallback_text=$(printf '%s' "${nome_empresa}" | awk '{a=toupper(substr($1,1,1)); b=toupper(substr($2,1,1)); if (b=="") b=toupper(substr($1,2,1)); printf "%s%s", a,b}')
  [ -z "${logo_fallback_text}" ] && logo_fallback_text="MF"

  rm -rf "${backup_dir}"
  if [ -d "${build_dir}" ]; then
    mv "${build_dir}" "${backup_dir}"
  fi
  mkdir -p "${build_dir}"

  cat > "${build_dir}/index.html" <<EOF
<!DOCTYPE html>
<html lang="pt-BR">
<head>
  <meta charset="UTF-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1.0" />
  <title>${nome_empresa} | Atualizacao em andamento</title>
  <style>
    :root {
      --primary: ${cor_primaria};
      --secondary: ${cor_secundaria};
      --bg: #0f172a;
      --text: #e2e8f0;
    }
    * { box-sizing: border-box; }
    body {
      margin: 0;
      min-height: 100vh;
      font-family: Inter, Arial, sans-serif;
      background: radial-gradient(circle at 20% 20%, var(--secondary), var(--bg) 60%);
      color: var(--text);
      display: flex;
      align-items: center;
      justify-content: center;
      padding: 24px;
    }
    .card {
      width: 100%;
      max-width: 520px;
      background: rgba(15, 23, 42, 0.78);
      border: 1px solid rgba(148, 163, 184, 0.28);
      border-radius: 18px;
      padding: 36px 30px;
      text-align: center;
      box-shadow: 0 20px 50px rgba(0, 0, 0, 0.45);
      backdrop-filter: blur(4px);
    }
    .logo {
      width: 74px;
      height: 74px;
      object-fit: contain;
      margin-bottom: 14px;
    }
    .logo-fallback {
      width: 74px;
      height: 74px;
      border-radius: 14px;
      margin: 0 auto 14px auto;
      display: grid;
      place-items: center;
      background: linear-gradient(135deg, var(--primary), var(--secondary));
      color: #fff;
      font-weight: 700;
      font-size: 24px;
    }
    h1 {
      margin: 0 0 10px 0;
      font-size: 24px;
      color: #f8fafc;
    }
    p {
      margin: 0;
      color: #cbd5e1;
      line-height: 1.5;
    }
    .bar {
      margin-top: 24px;
      height: 10px;
      background: rgba(148, 163, 184, 0.3);
      border-radius: 999px;
      overflow: hidden;
    }
    .bar span {
      display: block;
      height: 100%;
      width: 35%;
      border-radius: inherit;
      background: linear-gradient(90deg, var(--primary), #38bdf8, var(--secondary));
      animation: loading 1.35s ease-in-out infinite;
    }
    .counter {
      margin-top: 14px;
      font-size: 13px;
      color: #94a3b8;
    }
    @keyframes loading {
      0% { transform: translateX(-110%); }
      100% { transform: translateX(320%); }
    }
  </style>
</head>
<body>
  <div class="card">
    __LOGO_BLOCK__
    <h1>Sistema em atualizacao</h1>
    <p>Estamos aplicando melhorias no <strong>${nome_empresa}</strong>.<br />Volte em instantes para continuar usando normalmente.</p>
    <div class="bar"><span></span></div>
    <div class="counter">Tempo estimado restante: <strong id="countdown">10:00</strong></div>
  </div>
  <script>
    const countdownEl = document.getElementById('countdown');
    const totalSeconds = 10 * 60;
    const storageKey = 'mf_update_countdown_end_' + window.location.host;
    const now = Date.now();
    let endAt = parseInt(localStorage.getItem(storageKey) || '0', 10);

    if (!endAt || endAt <= now) {
      endAt = now + (totalSeconds * 1000);
      localStorage.setItem(storageKey, String(endAt));
    }

    const formatTime = (value) => {
      const minutes = Math.floor(value / 60);
      const seconds = value % 60;
      return String(minutes).padStart(2, '0') + ':' + String(seconds).padStart(2, '0');
    };

    const tick = () => {
      const remainingSeconds = Math.max(0, Math.ceil((endAt - Date.now()) / 1000));
      countdownEl.textContent = formatTime(remainingSeconds);
      if (remainingSeconds <= 0) {
        localStorage.removeItem(storageKey);
      }
    };

    tick();
    setInterval(tick, 1000);
  </script>
</body>
</html>
EOF

  if [ -n "${logo_url}" ]; then
    sed -i "s|__LOGO_BLOCK__|<img class=\"logo\" src=\"${logo_url}\" alt=\"Logo ${nome_empresa}\" />|g" "${build_dir}/index.html"
  else
    sed -i "s|__LOGO_BLOCK__|<div class=\"logo-fallback\">${logo_fallback_text}</div>|g" "${build_dir}/index.html"
  fi

  chown -R deploy:deploy "${build_dir}"
  chmod -R 775 "${build_dir}"
}

publicar_build_frontend_atualizado() {
  local frontend_dir="/home/deploy/${empresa}/frontend"
  local build_dir="${frontend_dir}/build"
  local backup_dir="${frontend_dir}/.build_pre_update"
  local next_dir="${frontend_dir}/.build_nova"

  if [ ! -d "${next_dir}" ]; then
    printf "${RED} >> ERRO: build novo não encontrado em ${next_dir}.${WHITE}\n"
    return 1
  fi

  rm -rf "${build_dir}"
  mv "${next_dir}" "${build_dir}"
  rm -rf "${backup_dir}"
  chown -R deploy:deploy "${build_dir}"
  chmod -R 775 "${build_dir}"
}

restaurar_build_frontend_anterior() {
  local frontend_dir="/home/deploy/${empresa}/frontend"
  local build_dir="${frontend_dir}/build"
  local backup_dir="${frontend_dir}/.build_pre_update"
  local next_dir="${frontend_dir}/.build_nova"

  rm -rf "${next_dir}"
  rm -rf "${build_dir}"
  if [ -d "${backup_dir}" ]; then
    mv "${backup_dir}" "${build_dir}"
    chown -R deploy:deploy "${build_dir}"
    chmod -R 775 "${build_dir}"
  fi
}

atualizar_api_oficial_fast() {
  local script_api="/root/instalador_single_oficial/atualizar_apioficial.sh"
  local resposta_api_oficial=""

  if [ ! -d "/home/deploy/${empresa}/api_oficial" ]; then
    printf "${YELLOW} >> API Oficial não encontrada para a instância ${empresa}. Pulando etapa.${WHITE}\n"
    return 0
  fi

  echo
  printf "${WHITE} >> Deseja atualizar também a API Oficial da instância ${BLUE}${empresa}${WHITE}? ${GREEN}S/${RED}N:${WHITE}\n"
  read -p "> " resposta_api_oficial
  resposta_api_oficial=$(echo "${resposta_api_oficial}" | tr '[:lower:]' '[:upper:]')
  if [ "${resposta_api_oficial}" != "S" ]; then
    printf "${YELLOW} >> API Oficial não será atualizada. Continuando a atualização FAST...${WHITE}\n"
    return 0
  fi

  if [ ! -f "${script_api}" ]; then
    printf "${YELLOW} >> Aviso: script da API Oficial não encontrado (${script_api}). Pulando etapa.${WHITE}\n"
    return 0
  fi

  printf "${WHITE} >> Atualizando API Oficial...\n"
  if ! bash "${script_api}"; then
    printf "${RED} >> Falha na atualização da API Oficial.${WHITE}\n"
    return 1
  fi

  printf "${GREEN} >> API Oficial atualizada com sucesso.${WHITE}\n"
  return 0
}

baixa_codigo_atualizar() {
  printf "${WHITE} >> Recuperando Permissões da empresa ${empresa}... \n"
  sleep 2
  chown deploy -R /home/deploy/${empresa}
  chmod 775 -R /home/deploy/${empresa}

  sleep 2

  # printf "${WHITE} >> Parando Instancias... \n"
  # sleep 2
  # sudo su - deploy <<EOF
  # # pm2 stop all
  # EOF

  # sleep 2

  # otimiza_banco_atualizar

  verificar_e_adicionar_max_buffer
  verificar_e_adicionar_whatsapp_web_version

  printf "${WHITE} >> Atualizando a Aplicação da Empresa ${empresa}... \n"
  sleep 2

  carregar_credenciais_instancia

  exportar_vars_frontend_env_seguro
  frontend_port=$(grep -m1 '^SERVER_PORT=' "/home/deploy/${empresa}/frontend/.env" 2>/dev/null | cut -d= -f2- | tr -d '\r' | tr -d ' ')
  frontend_port=${frontend_port:-3000}
  # O git reset/pull pode restaurar api_transcricao/main.py para a porta padrão 4002.
  # Preservar a porta registrada na instância evita conflito entre múltiplas instâncias.
  porta_transcricao="${porta_transcricao:-}"
  if [ -z "${porta_transcricao}" ]; then
    transcribe_url_atual=$(grep -m1 '^TRANSCRIBE_URL=' "/home/deploy/${empresa}/backend/.env" 2>/dev/null | cut -d= -f2- | tr -d '\r')
    porta_transcricao=$(echo "${transcribe_url_atual}" | sed -nE 's|.*:([0-9]+).*|\1|p' | head -1)
  fi
  porta_transcricao=${porta_transcricao:-4002}
  ativar_tela_atualizacao_frontend
  if ! sudo su - deploy <<EOF
set -e
if [ -f /root/instalador_single_oficial/tools/path_node_deploy.sh ]; then
  . /root/instalador_single_oficial/tools/path_node_deploy.sh
else
  export PATH="/usr/local/bin:/usr/bin:\${PATH:-}"
  if [ -d /usr/local/n/versions/node/20.19.4/bin ]; then
    export PATH="/usr/local/n/versions/node/20.19.4/bin:\$PATH"
  fi
fi

printf "${WHITE} >> Atualizando código (git)...\n"
echo
cd /home/deploy/${empresa}

if [ -f /root/instalador_single_oficial/tools/git_sincronizar_repositorio.sh ]; then
  . /root/instalador_single_oficial/tools/git_sincronizar_repositorio.sh
else
  echo "ERRO: tools/git_sincronizar_repositorio.sh não encontrado em /root/instalador_single_oficial."
  exit 1
fi

if [ -n "${commit_atualizacao}" ]; then
  printf "${WHITE} >> Checkout versão ${versao_atualizacao} (commit ${commit_atualizacao})...${WHITE}\n"
  mf_git_sincronizar_repositorio "${commit_atualizacao}" "atualizacao-fast-${versao_atualizacao}" || exit 1
else
  printf "${WHITE} >> Sincronizando com origin (Mais Recente: fetch + reset)...${WHITE}\n"
  mf_git_sincronizar_repositorio "" || exit 1
  printf "${WHITE} >> Branch sincronizada: \${MF_GIT_DEPLOY_BRANCH}${WHITE}\n"
fi

if [ -d "/home/deploy/${empresa}/api_transcricao" ] && [ -f "/home/deploy/${empresa}/api_transcricao/main.py" ]; then
  main_py_transc="/home/deploy/${empresa}/api_transcricao/main.py"
  sed -i -E "s|port[[:space:]]*=[[:space:]]*[0-9]+|port=${porta_transcricao}|g" "\$main_py_transc" 2>/dev/null || true
  sed -i -E "s|porta[[:space:]]+[0-9]+|porta ${porta_transcricao}|g" "\$main_py_transc" 2>/dev/null || true
  printf " >> Porta da transcrição reaplicada no main.py: ${porta_transcricao}\n"
fi

cd /home/deploy/${empresa}/backend
if [ ! -f package.json ]; then
  echo "ERRO: package.json não encontrado no backend."
  exit 1
fi

if echo "${repo_url}" | grep -q "scriptswhitelabel/multiflow-pro"; then
  if grep -q "TOKEN_GITHUB" package.json 2>/dev/null; then
    if [ -z "${github_token}" ]; then
      echo "ERRO: package.json exige token (TOKEN_GITHUB) mas github_token não está no arquivo da instância."
      exit 1
    fi
    sed -i "s|TOKEN_GITHUB|${github_token//&/\\&}|g" package.json
    echo " >> Token GitHub aplicado no package.json (Baileys)."
  fi
  if grep -q "TOKEN_GITHUB" package.json 2>/dev/null; then
    echo "ERRO: TOKEN_GITHUB ainda presente no package.json após aplicar token."
    exit 1
  fi
fi

printf "${WHITE} >> npm install no backend (sem remover node_modules — FAST)...\n"
export PUPPETEER_SKIP_DOWNLOAD=true
npm install --legacy-peer-deps --prefer-offline 2>/dev/null \
  || npm install --legacy-peer-deps 2>/dev/null \
  || npm install --force

printf "${WHITE} >> Build do backend...\n"
npm run build
sleep 2

printf "${WHITE} >> Migrations do banco (sequelize db:migrate)...\n"
if ! npx sequelize db:migrate; then
  echo "ERRO: sequelize db:migrate falhou. Verifique logs acima."
  exit 1
fi
sleep 2

printf "${WHITE} >> Atualizando Frontend da ${empresa}...\n"
echo
cd /home/deploy/${empresa}/frontend
printf "${WHITE} >> npm install --force no frontend (FAST — instala deps novas sem apagar node_modules)...\n"
npm install --force
sed -i 's/3000/'"$frontend_port"'/g' server.js
rm -rf .build_nova
build_ok=0
for mem in 4096 3072 2048; do
  printf "${WHITE} >> Build do frontend com --max-old-space-size=${mem}...\n"
  if BUILD_PATH=.build_nova NODE_OPTIONS="--max-old-space-size=${mem} --openssl-legacy-provider" npm run build; then
    build_ok=1
    break
  fi
  printf "${YELLOW} >> Tentativa com ${mem} MB falhou. Tentando próximo limite...${WHITE}\n"
  sleep 2
done
if [ "\$build_ok" -ne 1 ]; then
  echo "ERRO: Falha no build do frontend mesmo após fallback de memória (4096/3072/2048)."
  exit 1
fi
sleep 2
EOF
  then
    printf "${RED} >> Falha ao atualizar o frontend. Restaurando build anterior...${WHITE}\n"
    restaurar_build_frontend_anterior
    trata_erro "build_frontend_fast"
  fi

  if ! publicar_build_frontend_atualizado; then
    printf "${RED} >> Falha ao publicar novo build. Restaurando build anterior...${WHITE}\n"
    restaurar_build_frontend_anterior
    trata_erro "publicar_build_frontend_fast"
  fi

  descomentar_env_redis_bull_ack "/home/deploy/${empresa}/backend/.env" "/home/deploy/${empresa}/backend/package.json"

  _mf_transc_script="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/tools/mf_transcricao_manutencao.sh"
  if [ -f "$_mf_transc_script" ]; then
    # shellcheck source=/dev/null
    source "$_mf_transc_script"
    MF_TRANSC_MAINT_SCRIPT="$_mf_transc_script"
    chmod 755 "$_mf_transc_script" 2>/dev/null || true
    printf "${WHITE} >> Garantindo run_transcricao.sh e PM2 da transcrição...${WHITE}\n"
    mf_transcricao_pos_atualizacao_git "${empresa}" "${porta_transcricao}" \
      || printf "${YELLOW} >> Aviso: falha ao reconfigurar transcrição. Use o menu Instalar transcrição ou pm2 logs ${empresa}-transcricao.${WHITE}\n"
  else
    printf "${YELLOW} >> Aviso: tools/mf_transcricao_manutencao.sh não encontrado.${WHITE}\n"
  fi

  sudo su - deploy <<RESTARTPM2ATUALIZACAO
printf "${WHITE} >> Atualização Concluida, Reiniciando Instancias da empresa ${empresa} e Aplicando a Atualização... \n"
sleep 7
if [ -d /usr/local/n/versions/node/20.19.4/bin ]; then
  export PATH=/usr/local/n/versions/node/20.19.4/bin:/usr/bin:/usr/local/bin:\$PATH
else
  export PATH=/usr/bin:/usr/local/bin:\$PATH
fi
for _p in "${empresa}-backend" "${empresa}-frontend"; do
  pm2 restart "\$_p" 2>/dev/null || true
  pm2 reset "\$_p" 2>/dev/null || true
  pm2 flush "\$_p" 2>/dev/null || true
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
  printf "${WHITE} >> Atualização do sistema (${empresa}) concluída.${WHITE}\n"
  echo

}

# --- Execução automática (modo sistema) ---
printf "${GREEN} >> Atualizador FAST Sistema — modo automático${WHITE}\n"

if ! sistema_resolver_empresa "${1:-}"; then
  exit 1
fi

carregar_credenciais_instancia

declare -g versao_atualizacao="Mais_Recente"
declare -g commit_atualizacao=""
printf "${GREEN} >> Versão: última do Git (branch remota)${WHITE}\n"

if echo "${repo_url:-}" | grep -q "scriptswhitelabel/multiflow-pro" && [ -z "${github_token:-}" ]; then
  printf "${YELLOW} >> Aviso: github_token não definido — Baileys pode falhar no npm install.${WHITE}\n"
fi

baixa_codigo_atualizar || exit 1
sistema_atualizar_api_oficial || exit 1
sistema_atualizar_whatsmeow

printf "${GREEN} >> Atualização completa finalizada (${empresa}).${WHITE}\n"
exit 0
