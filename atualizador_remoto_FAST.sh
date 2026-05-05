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

# Funções de atualização
backup_app_atualizar() {
  # Verifica se a variável empresa está definida
  if [ -z "${empresa}" ]; then
    printf "${RED} >> ERRO: Variável 'empresa' não está definida!\n${WHITE}"
    exit 1
  fi
  
  source /home/deploy/${empresa}/backend/.env
  {
    printf "${WHITE} >> Fazendo backup do banco de dados da empresa ${empresa}...\n"
    db_password=$(grep "DB_PASS=" /home/deploy/${empresa}/backend/.env | cut -d '=' -f2)
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
    <div class="counter">Tempo de atualizacao: <strong id="seconds">0s</strong></div>
  </div>
  <script>
    let seconds = 0;
    setInterval(() => {
      seconds += 1;
      document.getElementById('seconds').textContent = seconds + 's';
    }, 1000);
  </script>
</body>
</html>
EOF

  if [ -n "${logo_url}" ]; then
    sed -i "s|__LOGO_BLOCK__|<img class=\"logo\" src=\"${logo_url}\" alt=\"Logo ${nome_empresa}\" />|g" "${build_dir}/index.html"
  else
    sed -i "s|__LOGO_BLOCK__|<div class=\"logo-fallback\">MF</div>|g" "${build_dir}/index.html"
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

  source /home/deploy/${empresa}/frontend/.env
  frontend_port=${SERVER_PORT:-3000}
  ativar_tela_atualizacao_frontend
  if ! sudo su - deploy <<EOF
set -e
printf "${WHITE} >> Atualizando Backend...\n"
echo
cd /home/deploy/${empresa}

# git fetch origin
# git checkout MULTI100-OFICIAL-u21
# git reset --hard origin/MULTI100-OFICIAL-u21

git reset --hard
git pull

cd /home/deploy/${empresa}/backend
# npm prune --force > /dev/null 2>&1
# export PUPPETEER_SKIP_DOWNLOAD=true
# rm -r node_modules
# rm package-lock.json
# npm install --force
# npm install puppeteer-core --force
# npm i glob
# npm install jimp@^1.6.0
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
cd /home/deploy/${empresa}/frontend
# npm prune --force > /dev/null 2>&1
# npm install --force
sed -i 's/3000/'"$frontend_port"'/g' server.js
rm -rf .build_nova
BUILD_PATH=.build_nova NODE_OPTIONS="--max-old-space-size=4096 --openssl-legacy-provider" npm run build
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

  if ! atualizar_api_oficial_fast; then
    trata_erro "atualizar_api_oficial_fast"
  fi

  sudo su - deploy <<RESTARTPM2ATUALIZACAO
printf "${WHITE} >> Atualização Concluida, Reiniciando Instancias da empresa ${empresa} e Aplicando a Atualização... \n"
sleep 7
if [ -d /usr/local/n/versions/node/20.19.4/bin ]; then
  export PATH=/usr/local/n/versions/node/20.19.4/bin:/usr/bin:/usr/local/bin:\$PATH
else
  export PATH=/usr/bin:/usr/local/bin:\$PATH
fi
pm2 restart all
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
MENSAGEM="🚨 Atualização "FAST" do ${nome_titulo} FINALIZADA"

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

backup_app_atualizar
baixa_codigo_atualizar
