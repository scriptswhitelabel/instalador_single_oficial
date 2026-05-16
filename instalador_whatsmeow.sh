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
ARQUIVO_VARIAVEIS=""
ip_atual=$(curl -s http://checkip.amazonaws.com)
default_wuzapi_port=8090
WUZAPI_COMPOSE_PROJECT=""

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
    
    # Parar e remover containers Docker se existirem
    if [ -f "/home/deploy/${empresa}/wuzapi/docker-compose.yml" ]; then
      printf "${WHITE} >> Parando containers Docker do WhatsMeow...${WHITE}\n"
      cd /home/deploy/${empresa}/wuzapi
      local proj="wuzapi_${empresa}"
      docker compose -p "$proj" down -v 2>/dev/null || docker-compose -p "$proj" down -v 2>/dev/null || true
      echo
      sleep 2
    fi
    
    # Remover a pasta wuzapi
    printf "${WHITE} >> Removendo pasta wuzapi existente...${WHITE}\n"
    rm -rf /home/deploy/${empresa}/wuzapi
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
WUZAPI_GLOBAL_ENCRYPTION_KEY=${senha_deploy}

# Global HMAC Key for webhook signing (minimum 32 characters)
WUZAPI_GLOBAL_HMAC_KEY=${senha_deploy}

# Global webhook URL
WUZAPI_GLOBAL_WEBHOOK=https://${subdominio_limpo}/webhook

# "json" or "form" for the default
WEBHOOK_FORMAT=json

# WuzAPI Session Configuration
SESSION_DEVICE_NAME=WuzAPI

# Database configuration
DB_USER=${db_user}
DB_PASSWORD=${senha_deploy}
DB_NAME=${db_name}
DB_HOST=db
DB_PORT=5432
DB_SSLMODE=false
TZ=America/Sao_Paulo

# RabbitMQ configuration Optional (rede interna do compose)
RABBITMQ_URL=amqp://${db_user}:${senha_deploy}@rabbitmq:5672/%2F
RABBITMQ_QUEUE=whatsapp_events_${empresa}
EOF

    printf "${GREEN} >> Arquivo .env do wuzapi configurado com sucesso!${WHITE}\n"
    sleep 2
  } || trata_erro "configurar_env_wuzapi"
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
    
    # Criar arquivo docker-compose.yml
    cat > /home/deploy/${empresa}/wuzapi/docker-compose.yml <<DOCKERCOMPOSE
name: ${WUZAPI_COMPOSE_PROJECT}
services:
  wuzapi-server:
    container_name: ${WUZAPI_COMPOSE_PROJECT}-server
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
      - SESSION_DEVICE_NAME=\${SESSION_DEVICE_NAME:-WuzAPI}
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
    restart: always

  db:
    container_name: ${WUZAPI_COMPOSE_PROJECT}-db
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
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U \${DB_USER:-wuzapi}"]
      interval: 5s
      timeout: 5s
      retries: 5
    restart: always

  rabbitmq:
    container_name: ${WUZAPI_COMPOSE_PROJECT}-rabbitmq
    image: rabbitmq:3-management
    hostname: rabbitmq-${empresa}
    environment:
      RABBITMQ_DEFAULT_USER: \${DB_USER:-${db_user}}
      RABBITMQ_DEFAULT_PASS: \${DB_PASSWORD:-wuzapi}
      RABBITMQ_DEFAULT_VHOST: /
    # Sem bind na host — evita conflito 5672/15672 entre instâncias
    volumes:
      - rabbitmq_data:/var/lib/rabbitmq
    networks:
      - wuzapi-network
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

# Atualizar .env do backend
atualizar_env_backend() {
  banner
  printf "${WHITE} >> Atualizando .env do backend com configurações do WhatsMeow...\n"
  echo
  {
    # Carregar variáveis necessárias
    source $ARQUIVO_VARIAVEIS
    
    # Limpar subdomínio (remover https:// se presente)
    subdominio_limpo=$(echo "${subdominio_whatsmeow}" | sed 's|https\?://||')
    
    # Adicionar variáveis do WhatsMeow ao .env do backend
    cat >> /home/deploy/${empresa}/backend/.env <<EOF

# WhatsMeow Configuration
WUZAPI_URL=https://${subdominio_limpo}
WUZAPI_ADMIN_TOKEN=${senha_deploy}
WUZAPI_TOKEN=${senha_deploy}
EOF
    
    printf "${GREEN} >> .env do backend atualizado com sucesso!${WHITE}\n"
    sleep 2
  } || trata_erro "atualizar_env_backend"
}

# Verificar e instalar Docker
verificar_e_instalar_docker() {
  banner
  printf "${WHITE} >> Verificando se o Docker está instalado...\n"
  echo
  
  if command -v docker >/dev/null 2>&1; then
    printf "${GREEN} >> Docker já está instalado.${WHITE}\n"
    docker --version
    echo
    sleep 2
  else
    printf "${YELLOW} >> Docker não encontrado. Iniciando instalação...${WHITE}\n"
    echo
    
    {
      # Instalar Docker
      sudo apt-get update -y >/dev/null 2>&1
      sudo apt-get install -y ca-certificates curl gnupg lsb-release >/dev/null 2>&1
      
      sudo install -m 0755 -d /etc/apt/keyrings
      curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg >/dev/null 2>&1
      sudo chmod a+r /etc/apt/keyrings/docker.gpg
      
      echo \
        "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
        $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
      
      sudo apt-get update -y >/dev/null 2>&1
      sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin >/dev/null 2>&1
      
      printf "${GREEN} >> Docker instalado com sucesso!${WHITE}\n"
      docker --version
      echo
      sleep 2
    } || trata_erro "verificar_e_instalar_docker"
  fi
  
  # Verificar se docker compose está disponível
  if ! docker compose version >/dev/null 2>&1; then
    printf "${YELLOW} >> Instalando docker-compose-plugin...${WHITE}\n"
    sudo apt-get install -y docker-compose-plugin >/dev/null 2>&1
  fi
  
  # Garantir que Docker está no PATH e funcionando
  if ! command -v docker >/dev/null 2>&1; then
    printf "${YELLOW} >> Docker não encontrado no PATH. Tentando atualizar PATH...${WHITE}\n"
    export PATH=$PATH:/usr/bin:/usr/local/bin
    # Tentar encontrar docker
    if [ -f /usr/bin/docker ]; then
      export PATH=/usr/bin:$PATH
    elif [ -f /usr/local/bin/docker ]; then
      export PATH=/usr/local/bin:$PATH
    fi
  fi
  
  # Verificar novamente se docker está disponível
  if ! command -v docker >/dev/null 2>&1; then
    printf "${RED}❌ ERRO: Docker não está disponível após instalação!${WHITE}\n"
    printf "${WHITE}   Tente executar manualmente:${WHITE}\n"
    printf "${WHITE}   sudo apt-get install -y docker.io docker-compose${WHITE}\n"
    exit 1
  fi
  
  # Verificar se serviço Docker está rodando
  if ! systemctl is-active --quiet docker 2>/dev/null; then
    printf "${WHITE} >> Iniciando serviço Docker...${WHITE}\n"
    systemctl start docker
    sleep 3
  fi
  
  # Verificar se docker compose funciona
  if ! docker compose version >/dev/null 2>&1; then
    printf "${YELLOW}⚠️  Aviso: docker compose não está funcionando.${WHITE}\n"
    printf "${WHITE}   Tentando usar docker-compose (versão antiga)...${WHITE}\n"
    if command -v docker-compose >/dev/null 2>&1; then
      printf "${GREEN} >> docker-compose encontrado!${WHITE}\n"
    else
      printf "${RED}❌ ERRO: docker compose não está disponível!${WHITE}\n"
      exit 1
    fi
  else
    printf "${GREEN} >> Docker e docker compose verificados e funcionando!${WHITE}\n"
  fi
  
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

# Reiniciar PM2 do backend da empresa (para aplicar configuração WhatsMeow)
reiniciar_pm2_backend() {
  banner
  printf "${WHITE} >> Reiniciando backend da empresa para aplicar a instalação do WhatsMeow...\n"
  echo
  {
    # Carregar variáveis necessárias
    source $ARQUIVO_VARIAVEIS
    
    # Verificar se PM2 está instalado
    if command -v pm2 >/dev/null 2>&1; then
      # Reiniciar apenas o backend desta empresa (nome: ${empresa}-backend)
      sudo -u deploy bash <<RESTARTBACKEND
        export PATH="\$HOME/.nvm/versions/node/*/bin:/usr/local/bin:/usr/bin:\$PATH"
        if pm2 list 2>/dev/null | grep -qE "${empresa}-backend[[:space:]]"; then
          pm2 restart ${empresa}-backend
          pm2 save
          printf "${GREEN} >> Backend ${empresa}-backend reiniciado com sucesso!${WHITE}\n"
        else
          printf "${YELLOW}⚠️  Processo ${empresa}-backend não encontrado no PM2.${WHITE}\n"
          printf "${WHITE}   Reinicie o backend manualmente para aplicar as configurações do WhatsMeow.${WHITE}\n"
        fi
RESTARTBACKEND
      sleep 2
    else
      printf "${YELLOW}⚠️  PM2 não está instalado ou não está no PATH.${WHITE}\n"
      printf "${WHITE}   Reinicie o backend manualmente para aplicar as configurações do WhatsMeow.${WHITE}\n"
      sleep 2
    fi
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
  printf "${GREEN}══════════════════════════════════════════════════════════════════${WHITE}\n"
  echo
  sleep 5
}

# Executar função principal
main
