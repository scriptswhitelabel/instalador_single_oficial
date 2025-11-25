#!/bin/bash

GREEN='\033[1;32m'
BLUE='\033[1;34m'
WHITE='\033[1;37m'
RED='\033[1;31m'
YELLOW='\033[1;33m'

# O arquivo VARIAVEIS_INSTALACAO está na pasta anterior (raiz do instalador)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ARQUIVO_VARIAVEIS="${SCRIPT_DIR}/../VARIAVEIS_INSTALACAO"

# Carregar variáveis
carregar_variaveis() {
  if [ -f $ARQUIVO_VARIAVEIS ]; then
    source $ARQUIVO_VARIAVEIS
  else
    empresa="multiflow"
  fi
}

carregar_variaveis

BACKEND_ENV="/home/deploy/${empresa}/backend/.env"
FRONTEND_ENV="/home/deploy/${empresa}/frontend/.env"

printf "${BLUE}"
printf "\n"
printf "██████╗ ██╗   ██╗███████╗██╗  ██╗\n"
printf "██╔══██╗██║   ██║██╔════╝██║  ██║\n"
printf "██████╔╝██║   ██║███████╗███████║\n"
printf "██╔═══╝ ██║   ██║╚════██║██╔══██║\n"
printf "██║     ╚██████╔╝███████║██║  ██║\n"
printf "╚═╝      ╚═════╝ ╚══════╝╚═╝  ╚═╝\n"
printf "    INSTALADOR PUSH NOTIFICATIONS\n"
printf "${WHITE}\n"

# Verificar se o diretório do backend existe
if [ ! -d "/home/deploy/${empresa}/backend" ]; then
  printf "${RED} >> Erro: Diretório /home/deploy/${empresa}/backend não encontrado!${WHITE}\n"
  printf "${RED} >> Certifique-se de que a instalação principal foi concluída.${WHITE}\n"
  exit 1
fi

# Verificar se o arquivo .env do backend existe
if [ ! -f "$BACKEND_ENV" ]; then
  printf "${RED} >> Erro: Arquivo .env do backend não encontrado!${WHITE}\n"
  exit 1
fi

printf "${WHITE} >> Verificando se as chaves VAPID já estão configuradas...\n"
echo

# Verificar se as variáveis VAPID já existem e têm valores
VAPID_PUBLIC=$(grep "^VAPID_PUBLIC_KEY=" "$BACKEND_ENV" | cut -d '=' -f2)
VAPID_PRIVATE=$(grep "^VAPID_PRIVATE_KEY=" "$BACKEND_ENV" | cut -d '=' -f2)
VAPID_SUBJECT=$(grep "^VAPID_SUBJECT=" "$BACKEND_ENV" | cut -d '=' -f2)

if [ -n "$VAPID_PUBLIC" ] && [ -n "$VAPID_PRIVATE" ] && [ -n "$VAPID_SUBJECT" ]; then
  printf "${GREEN} >> ✅ Push Notifications já está instalado!${WHITE}\n"
  echo
  printf "${WHITE} >> Chaves VAPID encontradas no arquivo .env:${WHITE}\n"
  printf "${YELLOW}    VAPID_PUBLIC_KEY=${VAPID_PUBLIC}${WHITE}\n"
  printf "${YELLOW}    VAPID_PRIVATE_KEY=${VAPID_PRIVATE}${WHITE}\n"
  printf "${YELLOW}    VAPID_SUBJECT=${VAPID_SUBJECT}${WHITE}\n"
  echo
  printf "${WHITE} >> Nenhuma ação necessária.${WHITE}\n"
  exit 0
fi

printf "${YELLOW} >> Chaves VAPID não encontradas. Iniciando instalação...${WHITE}\n"
echo

# Verificar se web-push está instalado
printf "${WHITE} >> Verificando dependência web-push...${WHITE}\n"
echo

cd /home/deploy/${empresa}/backend

if ! npm list web-push >/dev/null 2>&1; then
  printf "${WHITE} >> Instalando web-push...${WHITE}\n"
  sudo -u deploy npm install web-push --save >/dev/null 2>&1
fi

printf "${WHITE} >> 🔑 Gerando chaves VAPID para Push Notifications...${WHITE}\n"
echo

# Gerar chaves VAPID usando Node.js
VAPID_OUTPUT=$(sudo -u deploy node -e "
const webpush = require('web-push');
const vapidKeys = webpush.generateVAPIDKeys();
console.log(JSON.stringify({
  publicKey: vapidKeys.publicKey,
  privateKey: vapidKeys.privateKey
}));
" 2>/dev/null)

if [ -z "$VAPID_OUTPUT" ]; then
  printf "${RED} >> Erro ao gerar chaves VAPID!${WHITE}\n"
  printf "${RED} >> Verifique se o web-push está instalado corretamente.${WHITE}\n"
  exit 1
fi

# Extrair as chaves do JSON
VAPID_PUBLIC_KEY=$(echo "$VAPID_OUTPUT" | grep -oP '"publicKey":\s*"\K[^"]+')
VAPID_PRIVATE_KEY=$(echo "$VAPID_OUTPUT" | grep -oP '"privateKey":\s*"\K[^"]+')
VAPID_SUBJECT_VALUE="mailto:scriptswhitelabel@gmail.com"

printf "${GREEN} >> ✅ Chaves geradas com sucesso!${WHITE}\n"
echo

printf "${WHITE} >> 📋 Adicionando variáveis no arquivo .env do BACKEND...${WHITE}\n"
echo

# Remover linhas antigas se existirem (mesmo vazias)
sed -i '/^VAPID_PUBLIC_KEY=/d' "$BACKEND_ENV"
sed -i '/^VAPID_PRIVATE_KEY=/d' "$BACKEND_ENV"
sed -i '/^VAPID_SUBJECT=/d' "$BACKEND_ENV"

# Adicionar novas variáveis ao backend .env
echo "" >> "$BACKEND_ENV"
echo "# Push Notifications - VAPID Keys" >> "$BACKEND_ENV"
echo "VAPID_PUBLIC_KEY=${VAPID_PUBLIC_KEY}" >> "$BACKEND_ENV"
echo "VAPID_PRIVATE_KEY=${VAPID_PRIVATE_KEY}" >> "$BACKEND_ENV"
echo "VAPID_SUBJECT=${VAPID_SUBJECT_VALUE}" >> "$BACKEND_ENV"

printf "${GREEN}    VAPID_PUBLIC_KEY=${VAPID_PUBLIC_KEY}${WHITE}\n"
printf "${GREEN}    VAPID_PRIVATE_KEY=${VAPID_PRIVATE_KEY}${WHITE}\n"
printf "${GREEN}    VAPID_SUBJECT=${VAPID_SUBJECT_VALUE}${WHITE}\n"
echo

printf "${WHITE} >> 📋 Adicionando variável no arquivo .env do FRONTEND...${WHITE}\n"
echo

# Verificar se o arquivo .env do frontend existe
if [ -f "$FRONTEND_ENV" ]; then
  # Remover linha antiga se existir
  sed -i '/^REACT_APP_VAPID_PUBLIC_KEY=/d' "$FRONTEND_ENV"
  
  # Adicionar nova variável ao frontend .env
  echo "" >> "$FRONTEND_ENV"
  echo "# Push Notifications - VAPID Public Key" >> "$FRONTEND_ENV"
  echo "REACT_APP_VAPID_PUBLIC_KEY=${VAPID_PUBLIC_KEY}" >> "$FRONTEND_ENV"
  
  printf "${GREEN}    REACT_APP_VAPID_PUBLIC_KEY=${VAPID_PUBLIC_KEY}${WHITE}\n"
  echo
  
  printf "${WHITE} >> 🔨 Compilando o Frontend...${WHITE}\n"
  echo
  
  sudo -u deploy bash -c "cd /home/deploy/${empresa}/frontend && NODE_OPTIONS='--max-old-space-size=4096 --openssl-legacy-provider' npm run build"
  
  sleep 5
else
  printf "${YELLOW} >> Aviso: Arquivo .env do frontend não encontrado. Adicione manualmente:${WHITE}\n"
  printf "${YELLOW}    REACT_APP_VAPID_PUBLIC_KEY=${VAPID_PUBLIC_KEY}${WHITE}\n"
  echo
fi

printf "${WHITE} >> 🔄 Reiniciando aplicações com PM2...${WHITE}\n"
echo

sudo -u deploy bash -c "pm2 flush && pm2 restart all"

echo
printf "${GREEN} >> ✨ Push Notifications instalado com sucesso!${WHITE}\n"
echo
printf "${WHITE} >> Resumo da instalação:${WHITE}\n"
printf "${BLUE}    Backend .env:  ${WHITE}${BACKEND_ENV}${WHITE}\n"
printf "${BLUE}    Frontend .env: ${WHITE}${FRONTEND_ENV}${WHITE}\n"
echo
