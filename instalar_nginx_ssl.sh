#!/bin/bash

GREEN='\033[1;32m'
BLUE='\033[1;34m'
WHITE='\033[1;37m'
RED='\033[1;31m'
YELLOW='\033[1;33m'

# Arquivo de variáveis
ARQUIVO_VARIAVEIS="VARIAVEIS_INSTALACAO"

# Verificar se está rodando como root
if [ "$EUID" -ne 0 ]; then
  echo
  printf "${WHITE} >> Este script precisa ser executado como root ${RED}ou com privilégios de superusuário${WHITE}.\n"
  echo
  sleep 2
  exit 1
fi

# Banner
banner() {
  printf " ${BLUE}"
  printf "\n\n"
  printf "██╗███╗   ██╗███████╗████████╗ █████╗ ██╗     ██╗     ███████╗██╗    ██╗██╗\n"
  printf "██║████╗  ██║██╔════╝╚══██╔══╝██╔══██╗██║     ██║     ██╔════╝██║    ██║██║\n"
  printf "██║██╔██╗ ██║███████    ██║   ███████║██║     ██║     ███████╗██║ █╗ ██║██║\n"
  printf "██║██║╚██╗██║╚════██║   ██║   ██╔══██║██║     ██║     ╚════██║██║███╗██║██║\n"
  printf "██║██║ ╚████║███████╗   ██║   ██║  ██║███████╗███████╗███████║╚███╔███╔╝███████╗\n"
  printf "╚═╝╚═╝  ╚═══╝╚══════╝   ╚═╝   ╚═╝  ╚═╝╚══════╝╚══════╝╚══════╝ ╚══╝╚══╝ ╚══════╝\n"
  printf "                         INSTALADOR NGINX + SSL\n"
  printf "\n\n"
}

# Função para tratar erros
trata_erro() {
  printf "${RED}Erro encontrado: $1. Encerrando o script.${WHITE}\n"
  exit 1
}

# Verificar conectividade de rede e DNS
verificar_conectividade() {
  printf "${WHITE} >> Verificando conectividade de rede...\n"
  
  # Verificar se consegue fazer ping no Google DNS
  if ! ping -c 1 -W 2 8.8.8.8 >/dev/null 2>&1; then
    printf "${RED} >> ERRO: Sem conectividade de rede (não consegue alcançar 8.8.8.8)${WHITE}\n"
    printf "${YELLOW} >> Verifique sua conexão de internet.${WHITE}\n"
    return 1
  fi
  
  # Verificar resolução DNS
  if ! ping -c 1 -W 2 google.com >/dev/null 2>&1; then
    printf "${RED} >> ERRO: Problema com resolução DNS${WHITE}\n"
    printf "${YELLOW} >> Verifique a configuração do DNS em /etc/resolv.conf${WHITE}\n"
    printf "${YELLOW} >> Você pode tentar:${WHITE}\n"
    printf "${YELLOW} >>   echo 'nameserver 8.8.8.8' >> /etc/resolv.conf${WHITE}\n"
    printf "${YELLOW} >>   echo 'nameserver 8.8.4.4' >> /etc/resolv.conf${WHITE}\n"
    return 1
  fi
  
  printf "${GREEN} >> Conectividade de rede OK!${WHITE}\n"
  return 0
}

# Tentar corrigir problemas de DNS
tentar_corrigir_dns() {
  printf "${WHITE} >> Tentando corrigir problemas de DNS...\n"
  
  # Adicionar Google DNS se não estiver presente
  if ! grep -q "8.8.8.8" /etc/resolv.conf 2>/dev/null; then
    printf "${WHITE} >> Adicionando Google DNS (8.8.8.8)...\n"
    echo "nameserver 8.8.8.8" >> /etc/resolv.conf
    echo "nameserver 8.8.4.4" >> /etc/resolv.conf
  fi
  
  # Tentar usar systemd-resolve se disponível
  if command -v systemd-resolve &> /dev/null; then
    systemd-resolve --flush-caches >/dev/null 2>&1 || true
  fi
  
  sleep 2
}

# Carregar variáveis do arquivo VARIAVEIS_INSTALACAO
carregar_variaveis() {
  if [ ! -f "$ARQUIVO_VARIAVEIS" ]; then
    printf "${RED} >> ERRO: Arquivo ${ARQUIVO_VARIAVEIS} não encontrado!${WHITE}\n"
    printf "${YELLOW} >> Certifique-se de que o arquivo existe no diretório atual.${WHITE}\n"
    exit 1
  fi
  
  source "$ARQUIVO_VARIAVEIS"
  
  # Verificar se as variáveis essenciais foram carregadas
  if [ -z "${subdominio_backend}" ] || [ -z "${subdominio_frontend}" ] || [ -z "${email_deploy}" ] || [ -z "${empresa}" ]; then
    printf "${RED} >> ERRO: Variáveis essenciais não encontradas no arquivo ${ARQUIVO_VARIAVEIS}${WHITE}\n"
    printf "${YELLOW} >> Variáveis necessárias: subdominio_backend, subdominio_frontend, email_deploy, empresa${WHITE}\n"
    exit 1
  fi
  
  # Definir valores padrão para portas se não estiverem definidas
  if [ -z "${backend_port}" ]; then
    backend_port=8080
  fi
  
  if [ -z "${frontend_port}" ]; then
    frontend_port=3000
  fi
  
  printf "${GREEN} >> Variáveis carregadas com sucesso!${WHITE}\n"
  printf "${WHITE}   Backend: ${subdominio_backend}:${backend_port}\n"
  printf "${WHITE}   Frontend: ${subdominio_frontend}:${frontend_port}\n"
  printf "${WHITE}   Empresa: ${empresa}\n"
  printf "${WHITE}   Email: ${email_deploy}\n"
  echo
  sleep 2
}

# Instalar Nginx e dependências
instalar_nginx() {
  banner
  printf "${WHITE} >> Instalando Nginx...\n"
  echo
  
  # Verificar conectividade antes de continuar
  if ! verificar_conectividade; then
    printf "${YELLOW} >> Tentando corrigir problemas de DNS...${WHITE}\n"
    tentar_corrigir_dns
    
    # Verificar novamente
    if ! verificar_conectividade; then
      printf "${RED} >> ERRO: Problemas de conectividade não resolvidos.${WHITE}\n"
      printf "${YELLOW} >> Por favor, resolva os problemas de rede antes de continuar.${WHITE}\n"
      printf "${YELLOW} >> Você pode tentar:${WHITE}\n"
      printf "${YELLOW} >>   1. Verificar conexão de internet${WHITE}\n"
      printf "${YELLOW} >>   2. Configurar DNS manualmente${WHITE}\n"
      printf "${YELLOW} >>   3. Verificar firewall/proxy${WHITE}\n"
      trata_erro "Problemas de conectividade de rede"
    fi
  fi
  
  # Atualizar lista de pacotes
  printf "${WHITE} >> Atualizando lista de pacotes...\n"
  if ! apt update -y 2>&1 | tee /tmp/apt_update.log; then
    printf "${YELLOW} >> Aviso: Erro ao atualizar lista de pacotes.${WHITE}\n"
    printf "${YELLOW} >> Verificando se é problema de DNS...${WHITE}\n"
    
    # Tentar corrigir DNS novamente
    tentar_corrigir_dns
    
    # Tentar novamente
    printf "${WHITE} >> Tentando atualizar novamente...\n"
    if ! apt update -y 2>&1 | tee /tmp/apt_update.log; then
      printf "${RED} >> ERRO: Falha ao atualizar lista de pacotes após correções.${WHITE}\n"
      printf "${YELLOW} >> Logs salvos em /tmp/apt_update.log${WHITE}\n"
      trata_erro "Falha ao atualizar lista de pacotes"
    fi
  fi
  
  # Verificar se Nginx já está instalado
  if command -v nginx &> /dev/null; then
    printf "${YELLOW} >> Nginx já está instalado. Continuando...${WHITE}\n"
  else
    # Instalar Nginx
    printf "${WHITE} >> Instalando pacote Nginx...\n"
    if ! apt install -y nginx 2>&1 | tee /tmp/nginx_install.log; then
      printf "${RED} >> ERRO: Falha ao instalar Nginx.${WHITE}\n"
      printf "${YELLOW} >> Logs salvos em /tmp/nginx_install.log${WHITE}\n"
      printf "${YELLOW} >> Verifique os logs acima para mais detalhes.${WHITE}\n"
      printf "${YELLOW} >> Possíveis soluções:${WHITE}\n"
      printf "${YELLOW} >>   1. Verificar conectividade de internet${WHITE}\n"
      printf "${YELLOW} >>   2. Configurar DNS: echo 'nameserver 8.8.8.8' >> /etc/resolv.conf${WHITE}\n"
      printf "${YELLOW} >>   3. Tentar: apt-get update --fix-missing${WHITE}\n"
      printf "${YELLOW} >>   4. Verificar se há firewall bloqueando conexões${WHITE}\n"
      trata_erro "Falha ao instalar Nginx"
    fi
  fi
  
  # Remover configuração padrão
  if [ -f /etc/nginx/sites-enabled/default ]; then
    printf "${WHITE} >> Removendo configuração padrão do Nginx...\n"
    rm /etc/nginx/sites-enabled/default
  fi
  
  # Configurar client_max_body_size
  printf "${WHITE} >> Configurando client_max_body_size...\n"
  mkdir -p /etc/nginx/conf.d
  echo "client_max_body_size 100M;" > /etc/nginx/conf.d/${empresa}.conf
  
  # Verificar configuração do Nginx
  printf "${WHITE} >> Verificando configuração do Nginx...\n"
  if ! nginx -t; then
    printf "${YELLOW} >> Aviso: Configuração do Nginx pode ter problemas, mas continuando...${WHITE}\n"
  fi
  
  # Reiniciar Nginx
  printf "${WHITE} >> Reiniciando Nginx...\n"
  if ! systemctl restart nginx; then
    printf "${YELLOW} >> Aviso: Falha ao reiniciar Nginx. Tentando iniciar...${WHITE}\n"
    systemctl start nginx || trata_erro "Falha ao iniciar Nginx"
  fi
  
  # Habilitar Nginx para iniciar automaticamente
  systemctl enable nginx >/dev/null 2>&1 || true
  
  printf "${GREEN} >> Nginx instalado e configurado com sucesso!${WHITE}\n"
  sleep 2
}

# Instalar Certbot
instalar_certbot() {
  banner
  printf "${WHITE} >> Instalando Certbot...\n"
  echo
  
  # Verificar se Certbot já está instalado
  if command -v certbot &> /dev/null; then
    printf "${YELLOW} >> Certbot já está instalado. Continuando...${WHITE}\n"
    sleep 2
    return 0
  fi
  
  # Instalar snapd se não estiver instalado
  if ! command -v snap &> /dev/null; then
    printf "${WHITE} >> Instalando snapd...\n"
    if ! apt install -y snapd; then
      trata_erro "Falha ao instalar snapd"
    fi
    
    printf "${WHITE} >> Instalando snap core...\n"
    if ! snap install core; then
      trata_erro "Falha ao instalar snap core"
    fi
    
    printf "${WHITE} >> Atualizando snap core...\n"
    snap refresh core || true
  fi
  
  # Remover certbot antigo se existir (via apt)
  if dpkg -l | grep -q "^ii.*certbot"; then
    printf "${WHITE} >> Removendo versão antiga do Certbot (apt)...\n"
    apt-get remove certbot -y >/dev/null 2>&1 || true
  fi
  
  # Instalar certbot via snap
  printf "${WHITE} >> Instalando Certbot via snap...\n"
  if ! snap install --classic certbot; then
    trata_erro "Falha ao instalar Certbot via snap"
  fi
  
  # Criar link simbólico se não existir
  if [ ! -f /usr/bin/certbot ]; then
    printf "${WHITE} >> Criando link simbólico para Certbot...\n"
    ln -s /snap/bin/certbot /usr/bin/certbot
  fi
  
  # Verificar se Certbot está funcionando
  if ! certbot --version >/dev/null 2>&1; then
    trata_erro "Certbot instalado mas não está funcionando corretamente"
  fi
  
  printf "${GREEN} >> Certbot instalado com sucesso!${WHITE}\n"
  sleep 2
}

# Configurar Nginx para Frontend
configurar_nginx_frontend() {
  banner
  printf "${WHITE} >> Configurando Nginx para ${BLUE}frontend${WHITE}...\n"
  echo
  
  {
    frontend_hostname=$(echo "${subdominio_frontend}" | sed 's|https://||' | sed 's|http://||' | sed 's|/.*||')
    
    cat > /etc/nginx/sites-available/${empresa}-frontend << EOF
server {
  server_name ${frontend_hostname};
  location / {
    proxy_pass http://127.0.0.1:${frontend_port};
    proxy_http_version 1.1;
    proxy_set_header Upgrade \$http_upgrade;
    proxy_set_header Connection 'upgrade';
    proxy_set_header Host \$host;
    proxy_set_header X-Real-IP \$remote_addr;
    proxy_set_header X-Forwarded-Proto \$scheme;
    proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    proxy_cache_bypass \$http_upgrade;
  }
}
EOF
    
    # Criar link simbólico se não existir
    if [ ! -L /etc/nginx/sites-enabled/${empresa}-frontend ]; then
      ln -s /etc/nginx/sites-available/${empresa}-frontend /etc/nginx/sites-enabled/${empresa}-frontend
    fi
    
    # Testar configuração do Nginx
    nginx -t >/dev/null 2>&1 || trata_erro "Configuração do Nginx inválida para frontend"
    
    # Reiniciar Nginx
    systemctl restart nginx || trata_erro "Falha ao reiniciar Nginx após configuração do frontend"
    
    printf "${GREEN} >> Configuração do frontend concluída!${WHITE}\n"
    sleep 2
  } || trata_erro "configurar_nginx_frontend"
}

# Configurar Nginx para Backend
configurar_nginx_backend() {
  banner
  printf "${WHITE} >> Configurando Nginx para ${BLUE}backend${WHITE}...\n"
  echo
  
  {
    backend_hostname=$(echo "${subdominio_backend}" | sed 's|https://||' | sed 's|http://||' | sed 's|/.*||')
    
    cat > /etc/nginx/sites-available/${empresa}-backend << EOF
upstream backend {
  server 127.0.0.1:${backend_port};
  keepalive 32;
}

server {
  server_name ${backend_hostname};
  location / {
    proxy_pass http://backend;
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
EOF
    
    # Criar link simbólico se não existir
    if [ ! -L /etc/nginx/sites-enabled/${empresa}-backend ]; then
      ln -s /etc/nginx/sites-available/${empresa}-backend /etc/nginx/sites-enabled/${empresa}-backend
    fi
    
    # Testar configuração do Nginx
    nginx -t >/dev/null 2>&1 || trata_erro "Configuração do Nginx inválida para backend"
    
    # Reiniciar Nginx
    systemctl restart nginx || trata_erro "Falha ao reiniciar Nginx após configuração do backend"
    
    printf "${GREEN} >> Configuração do backend concluída!${WHITE}\n"
    sleep 2
  } || trata_erro "configurar_nginx_backend"
}

# Aplicar certificado SSL para Backend
aplicar_ssl_backend() {
  banner
  printf "${WHITE} >> Aplicando certificado SSL para ${BLUE}backend${WHITE}...\n"
  echo
  
  {
    backend_domain=$(echo "${subdominio_backend}" | sed 's|https://||' | sed 's|http://||' | sed 's|/.*||')
    
    certbot -m ${email_deploy} \
            --nginx \
            --agree-tos \
            -n \
            -d ${backend_domain} \
            --redirect 2>&1 || {
      printf "${YELLOW} >> Aviso: Certificado SSL para backend pode ter falhado. Verifique manualmente.${WHITE}\n"
      printf "${YELLOW} >> Comando: certbot --nginx -d ${backend_domain}${WHITE}\n"
    }
    
    printf "${GREEN} >> Certificado SSL do backend aplicado!${WHITE}\n"
    sleep 2
  } || printf "${YELLOW} >> Aviso: Erro ao aplicar certificado SSL do backend. Continue manualmente.${WHITE}\n"
}

# Aplicar certificado SSL para Frontend
aplicar_ssl_frontend() {
  banner
  printf "${WHITE} >> Aplicando certificado SSL para ${BLUE}frontend${WHITE}...\n"
  echo
  
  {
    frontend_domain=$(echo "${subdominio_frontend}" | sed 's|https://||' | sed 's|http://||' | sed 's|/.*||')
    
    certbot -m ${email_deploy} \
            --nginx \
            --agree-tos \
            -n \
            -d ${frontend_domain} \
            --redirect 2>&1 || {
      printf "${YELLOW} >> Aviso: Certificado SSL para frontend pode ter falhado. Verifique manualmente.${WHITE}\n"
      printf "${YELLOW} >> Comando: certbot --nginx -d ${frontend_domain}${WHITE}\n"
    }
    
    printf "${GREEN} >> Certificado SSL do frontend aplicado!${WHITE}\n"
    sleep 2
  } || printf "${YELLOW} >> Aviso: Erro ao aplicar certificado SSL do frontend. Continue manualmente.${WHITE}\n"
}

# Função principal
main() {
  banner
  
  printf "${WHITE} >> Este script irá:${WHITE}\n"
  printf "${WHITE}   1. Carregar variáveis do arquivo ${ARQUIVO_VARIAVEIS}${WHITE}\n"
  printf "${WHITE}   2. Instalar Nginx${WHITE}\n"
  printf "${WHITE}   3. Instalar Certbot${WHITE}\n"
  printf "${WHITE}   4. Configurar Nginx para Frontend e Backend${WHITE}\n"
  printf "${WHITE}   5. Aplicar certificados SSL${WHITE}\n"
  echo
  printf "${WHITE} >> Deseja continuar? (S/N):${WHITE}\n"
  read -p "> " confirmacao
  confirmacao=$(echo "${confirmacao}" | tr '[:lower:]' '[:upper:]')
  
  if [ "${confirmacao}" != "S" ]; then
    printf "${GREEN} >> Operação cancelada.${WHITE}\n"
    exit 0
  fi
  
  # Carregar variáveis
  carregar_variaveis
  
  # Verificar conectividade inicial
  printf "${WHITE} >> Verificando conectividade de rede antes de iniciar...\n"
  if ! verificar_conectividade; then
    printf "${YELLOW} >> Tentando corrigir problemas de DNS automaticamente...${WHITE}\n"
    tentar_corrigir_dns
    
    if ! verificar_conectividade; then
      printf "${RED} >> ERRO: Não foi possível estabelecer conectividade de rede.${WHITE}\n"
      printf "${YELLOW} >> Por favor, resolva os problemas de rede antes de continuar.${WHITE}\n"
      exit 1
    fi
  fi
  
  # Instalar Nginx
  instalar_nginx
  
  # Instalar Certbot
  instalar_certbot
  
  # Configurar Nginx
  configurar_nginx_frontend
  configurar_nginx_backend
  
  # Aplicar certificados SSL (Let's Encrypt)
  aplicar_ssl_backend
  aplicar_ssl_frontend
  
  # Reiniciar Nginx final
  systemctl restart nginx
  
  banner
  printf "${GREEN} >> Instalação e configuração do Nginx concluída!${WHITE}\n"
  echo
  printf "${WHITE}   Backend: ${BLUE}${subdominio_backend}${WHITE}\n"
  printf "${WHITE}   Frontend: ${BLUE}${subdominio_frontend}${WHITE}\n"
  echo
  printf "${GREEN} >> Verifique se os certificados SSL (Let's Encrypt) foram aplicados corretamente.${WHITE}\n"
  echo
}

# Executar função principal
main

