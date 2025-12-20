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
ip_atual=$(curl -s http://checkip.amazonaws.com)
default_wuzapi_port=8090

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

# Carregar variáveis
carregar_variaveis() {
  if [ -f $ARQUIVO_VARIAVEIS ]; then
    source $ARQUIVO_VARIAVEIS
  else
    empresa="multiflow"
    nome_titulo="MultiFlow"
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
    printf "${WHITE}   Deseja continuar mesmo assim? (s/n):${WHITE}\n"
    read -p "> " resposta
    
    if [ "$resposta" != "s" ] && [ "$resposta" != "S" ]; then
      printf "${YELLOW} >> Instalação cancelada pelo usuário.${WHITE}\n"
      echo
      exit 0
    fi
    
    printf "${GREEN} >> Continuando com a instalação...${WHITE}\n"
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
  echo "subdominio_whatsmeow=${subdominio_whatsmeow}" >>$ARQUIVO_VARIAVEIS
  sleep 2
}

# Solicitar porta da API WhatsMeow
solicitar_porta_whatsmeow() {
  banner
  printf "${WHITE} >> Qual porta a API WhatsMeow vai rodar?${WHITE}\n"
  echo
  printf "${WHITE}   Porta padrão: ${YELLOW}${default_wuzapi_port}${WHITE}\n"
  echo
  printf "${WHITE}   Deseja usar a porta padrão (${default_wuzapi_port})? (s/n):${WHITE}\n"
  read -p "> " usar_porta_padrao
  
  if [ "$usar_porta_padrao" = "s" ] || [ "$usar_porta_padrao" = "S" ]; then
    wuzapi_port=${default_wuzapi_port}
    printf "${GREEN} >> Usando porta padrão: ${wuzapi_port}${WHITE}\n"
  else
    printf "${WHITE} >> Digite a porta desejada:${WHITE}\n"
    read -p "> " wuzapi_port
    printf "${GREEN} >> Porta configurada: ${wuzapi_port}${WHITE}\n"
  fi
  
  echo "wuzapi_port=${wuzapi_port}" >>$ARQUIVO_VARIAVEIS
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
    sleep 5
    exit 1
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
upstream api_whatsmeow {
        server 127.0.0.1:${wuzapi_port};
        keepalive 32;
    }
server {
  server_name ${whatsmeow_hostname};
  location / {
    proxy_pass http://api_whatsmeow;
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
    # Carregar variáveis necessárias
    source $ARQUIVO_VARIAVEIS
    
    # Gerar chaves de criptografia
    gerar_chaves_criptografia
    
    # Limpar subdomínio (remover https:// se presente)
    subdominio_limpo=$(echo "${subdominio_whatsmeow}" | sed 's|https\?://||')
    
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
DB_USER=wuzapi
DB_PASSWORD=wuzapi
DB_NAME=wuzapi
DB_HOST=db
DB_PORT=5432
DB_SSLMODE=false
TZ=America/Sao_Paulo

# RabbitMQ configuration Optional
RABBITMQ_URL=amqp://wuzapi:wuzapi@localhost:5672/%2F
RABBITMQ_QUEUE=whatsapp_events
EOF

    printf "${GREEN} >> Arquivo .env do wuzapi configurado com sucesso!${WHITE}\n"
    sleep 2
  } || trata_erro "configurar_env_wuzapi"
}

# Configurar docker-compose.yml
configurar_docker_compose() {
  banner
  printf "${WHITE} >> Configurando docker-compose.yml...\n"
  echo
  {
    # Carregar variáveis necessárias
    source $ARQUIVO_VARIAVEIS
    
    # Criar arquivo docker-compose.yml
    cat > /home/deploy/${empresa}/wuzapi/docker-compose.yml <<DOCKERCOMPOSE
services:
  wuzapi-server:
    build:
      context: .
      dockerfile: Dockerfile
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
      - RABBITMQ_URL=amqp://wuzapi:wuzapi@rabbitmq:5672/
      - RABBITMQ_QUEUE=whatsapp_events
    depends_on:
      db:
        condition: service_healthy
      rabbitmq:
        condition: service_healthy
    networks:
      - wuzapi-network
    restart: always

  db:
    image: postgres:16
    environment:
      POSTGRES_USER: \${DB_USER:-wuzapi}
      POSTGRES_PASSWORD: \${DB_PASSWORD:-wuzapi}
      POSTGRES_DB: \${DB_NAME:-wuzapi}
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
    image: rabbitmq:3-management
    hostname: rabbitmq
    environment:
      RABBITMQ_DEFAULT_USER: wuzapi
      RABBITMQ_DEFAULT_PASS: wuzapi
      RABBITMQ_DEFAULT_VHOST: /
    ports:
      - "5672:5672" # AMQP port
      - "15672:15672" # Management UI port
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
}

# Subir containers do WhatsMeow
subir_containers_whatsmeow() {
  banner
  printf "${WHITE} >> Subindo containers do WhatsMeow...\n"
  echo
  
  {
    cd /home/deploy/${empresa}/wuzapi
    
    printf "${WHITE} >> Executando docker compose up -d...\n"
    echo
    
    # Executar docker compose e capturar saída
    docker_output=$(docker compose up -d 2>&1)
    docker_exit_code=$?
    
    echo "$docker_output"
    echo
    
    if [ $docker_exit_code -eq 0 ]; then
      # Verificar se os containers estão rodando
      printf "${WHITE} >> Aguardando containers iniciarem...\n"
      sleep 10
      
      # Verificar status dos containers
      if docker compose ps | grep -qE "(Healthy|Running|Up)"; then
        printf "${GREEN}✅ Containers do WhatsMeow iniciados com sucesso!${WHITE}\n"
        echo
        docker compose ps
        echo
        sleep 2
      else
        printf "${YELLOW}⚠️  Containers iniciados, mas alguns podem estar iniciando ainda...${WHITE}\n"
        printf "${WHITE}   Verifique o status com: cd /home/deploy/${empresa}/wuzapi && docker compose ps${WHITE}\n"
        echo
        sleep 2
      fi
    else
      printf "${RED}❌ ERRO: Falha ao subir os containers do WhatsMeow.${WHITE}\n"
      printf "${RED}   Verifique os logs com: cd /home/deploy/${empresa}/wuzapi && docker compose logs${WHITE}\n"
      exit 1
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

# Função principal
main() {
  aviso_versao_pro
  carregar_variaveis
  verificar_instalacao_existente
  solicitar_subdominio_whatsmeow
  solicitar_porta_whatsmeow
  verificar_dns_whatsmeow
  configurar_nginx_whatsmeow
  clonar_repositorio_wuzapi
  configurar_env_wuzapi
  configurar_docker_compose
  atualizar_env_backend
  verificar_e_instalar_docker
  subir_containers_whatsmeow
  reiniciar_servicos
  
  # Carregar variáveis finais
  source $ARQUIVO_VARIAVEIS
  
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
