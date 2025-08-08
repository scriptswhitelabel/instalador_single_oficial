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
jwt_refresh_secret=$(openssl rand -base64 32)
default_apioficial_port=6000

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
  echo "║                    INSTALADOR API OFICIAL                    ║"
  echo "║                                                              ║"
  echo "║                    MultiFlow System                          ║"
  echo "╚══════════════════════════════════════════════════════════════╝"
  printf "${WHITE}"
  echo
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

# Solicitar dados do subdomínio da API Oficial
solicitar_dados_apioficial() {
  banner
  printf "${WHITE} >> Insira o subdomínio da API Oficial: \n"
  echo
  read -p "> " subdominio_oficial
  echo
  printf "   ${WHITE}Subdominio API Oficial: ---->> ${YELLOW}${subdominio_oficial}\n"
  echo "subdominio_oficial=${subdominio_oficial}" >>$ARQUIVO_VARIAVEIS
}

# Validação de DNS
verificar_dns_apioficial() {
  banner
  printf "${WHITE} >> Verificando o DNS do subdomínio da API Oficial...\n"
  echo
  sleep 2
  sudo apt-get install dnsutils -y >/dev/null 2>&1

  local domain=${subdominio_oficial}
  local resolved_ip
  local cname_target

  cname_target=$(dig +short CNAME ${domain})

  if [ -n "${cname_target}" ]; then
    resolved_ip=$(dig +short ${cname_target})
  else
    resolved_ip=$(dig +short ${domain})
  fi

  if [ "${resolved_ip}" != "${ip_atual}" ]; then
    echo "O domínio ${domain} (resolvido para ${resolved_ip}) não está apontando para o IP público atual (${ip_atual})."
    echo
    printf "${RED} >> Verifique o apontamento de DNS do subdomínio: ${subdominio_oficial}${WHITE}\n"
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

# Configurar Nginx para API Oficial
configurar_nginx_apioficial() {
  banner
  printf "${WHITE} >> Configurando Nginx para API Oficial...\n"
  echo
  {
    oficial_hostname=$(echo "${subdominio_oficial/https:\/\//}")
    sudo su - root <<EOF
cat > /etc/nginx/sites-available/${empresa}-oficial << 'END'
upstream oficial {
        server 127.0.0.1:${default_apioficial_port};
        keepalive 32;
    }
server {
  server_name ${oficial_hostname};
  location / {
    proxy_pass http://oficial;
    proxy_http_version 1.1;
    proxy_set_header Upgrade \$http_upgrade;
    proxy_set_header Connection 'upgrade';
    proxy_set_header Host \$host;
    proxy_set_header X-Real-IP \$remote_addr;
    proxy_set_header X-Forwarded-Proto \$scheme;
    proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    proxy_cache_bypass \$http_upgrade;
    proxy_buffering on;
  }
}
END
ln -s /etc/nginx/sites-available/${empresa}-oficial /etc/nginx/sites-enabled
EOF

    sleep 2

    banner
    printf "${WHITE} >> Emitindo SSL do ${subdominio_oficial}...\n"
    echo
    oficial_domain=$(echo "${subdominio_oficial/https:\/\//}")
    sudo su - root <<EOF
    certbot -m ${email_deploy} \
            --nginx \
            --agree-tos \
            -n \
            -d ${oficial_domain}
EOF

    sleep 2
  } || trata_erro "configurar_nginx_apioficial"
}

# Criar banco de dados para API Oficial
criar_banco_apioficial() {
  banner
  printf "${WHITE} >> Criando banco de dados para API Oficial...\n"
  echo
  {
    sudo -u postgres psql <<EOF
CREATE DATABASE oficialseparado;
\q
EOF
    printf "${GREEN} >> Banco de dados 'oficialseparado' criado com sucesso!${WHITE}\n"
    sleep 2
  } || trata_erro "criar_banco_apioficial"
}

# Configurar arquivo .env da API Oficial
configurar_env_apioficial() {
  banner
  printf "${WHITE} >> Configurando arquivo .env da API Oficial...\n"
  echo
  {
    # Carregar variáveis necessárias
    source $ARQUIVO_VARIAVEIS
    
    # Criar diretório da API Oficial se não existir
    mkdir -p /home/deploy/${empresa}/api_oficial
    
    # Criar arquivo .env
    cat > /home/deploy/${empresa}/api_oficial/.env <<EOF
DATABASE_LINK=postgresql://${empresa}:${senha_deploy}@localhost:5432/oficialseparado?schema=public
DATABASE_URL=localhost
DATABASE_PORT=5432
DATABASE_USER=${empresa}
DATABASE_PASSWORD=${senha_deploy}
DATABASE_NAME=oficialseparado
TOKEN_ADMIN=adminpro
URL_BACKEND_MULT100=https://servermulti100apioficial.scriptswhitelabel.com.br 
REDIS_URI=redis://:${senha_deploy}@127.0.0.1:6379
PORT=${default_apioficial_port}
NAME_ADMIN=SetupAutomatizado
EMAIL_ADMIN=admin@multi100.com.br
PASSWORD_ADMIN=adminpro
JWT_REFRESH_SECRET=${jwt_refresh_secret}
URL_API_OFICIAL=https://${subdominio_oficial}
EOF

    printf "${GREEN} >> Arquivo .env da API Oficial configurado com sucesso!${WHITE}\n"
    sleep 2
  } || trata_erro "configurar_env_apioficial"
}

# Instalar e configurar API Oficial
instalar_apioficial() {
  banner
  printf "${WHITE} >> Instalando e configurando API Oficial...\n"
  echo
  {
    cd /home/deploy/${empresa}/api_oficial
    
    printf "${WHITE} >> Instalando dependências...\n"
    npm install
    
    printf "${WHITE} >> Gerando Prisma...\n"
    npx prisma generate
    
    printf "${WHITE} >> Buildando aplicação...\n"
    npm run build
    
    printf "${WHITE} >> Executando migrações...\n"
    npx prisma migrate dev
    
    printf "${WHITE} >> Gerando cliente Prisma...\n"
    npx prisma generate client
    
    printf "${WHITE} >> Iniciando aplicação com PM2...\n"
    pm2 start dist/main.js --name=api_oficial
    
    printf "${GREEN} >> API Oficial instalada e configurada com sucesso!${WHITE}\n"
    sleep 2
  } || trata_erro "instalar_apioficial"
}

# Atualizar .env do backend com URL da API Oficial
atualizar_env_backend() {
  banner
  printf "${WHITE} >> Atualizando .env do backend com URL da API Oficial...\n"
  echo
  {
    # Adicionar URL_API_OFICIAL ao .env do backend
    echo "URL_API_OFICIAL=https://${subdominio_oficial}" >> /home/deploy/${empresa}/backend/.env
    
    printf "${GREEN} >> .env do backend atualizado com sucesso!${WHITE}\n"
    sleep 2
  } || trata_erro "atualizar_env_backend"
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
  carregar_variaveis
  solicitar_dados_apioficial
  verificar_dns_apioficial
  configurar_nginx_apioficial
  criar_banco_apioficial
  configurar_env_apioficial
  instalar_apioficial
  atualizar_env_backend
  reiniciar_servicos
  
  banner
  printf "${GREEN} >> Instalação da API Oficial concluída com sucesso!${WHITE}\n"
  echo
  printf "${WHITE} >> API Oficial disponível em: ${YELLOW}https://${subdominio_oficial}${WHITE}\n"
  printf "${WHITE} >> Porta da API Oficial: ${YELLOW}${default_apioficial_port}${WHITE}\n"
  echo
  sleep 5
}

# Executar função principal
main
