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

# Token do Git - Variável Fixa
GIT_TOKEN="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"

# Capturar sinais de interrupção
trap 'printf "\n${YELLOW}Script interrompido pelo usuário.${WHITE}\n"; exit 1' INT TERM

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

# Função para verificar se o processo foi interrompido
verifica_interrupcao() {
  if [ $? -ne 0 ]; then
    printf "${YELLOW}Processo interrompido. Tentando continuar...${WHITE}\n"
    sleep 2
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

# Função para atualizar token do Git
atualiza_token_git() {
  printf "${WHITE} >> Atualizando token do Git para a empresa ${empresa}...\n"
  {
    git_config_file="/home/deploy/${empresa}/.git/config"
    
    if [ -f "$git_config_file" ]; then
      # Fazer backup do arquivo original
      cp "$git_config_file" "${git_config_file}.backup"
      
      # Atualizar o token na URL do GitHub
      sed -i "s|https://ghp_[^@]*@github.com|https://${GIT_TOKEN}@github.com|g" "$git_config_file"
      
      printf "${GREEN} >> Token do Git atualizado com sucesso para a empresa ${empresa}\n"
    else
      printf "${YELLOW} >> Arquivo de configuração do Git não encontrado para a empresa ${empresa}\n"
    fi
    
    sleep 2
  } || trata_erro "atualiza_token_git"
}

# Funções de atualização
backup_app_atualizar() {

  dummy_carregar_variaveis
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
  {
    db_password=$(grep "DB_PASS=" /home/deploy/${empresa}/backend/.env | cut -d '=' -f2)
    sudo su - root <<EOF
    PGPASSWORD="$db_password" vacuumdb -U "${empresa}" -h localhost -d "${empresa}" --full --analyze
    PGPASSWORD="$db_password" psql -U ${empresa} -h 127.0.0.1 -d ${empresa} -c "REINDEX DATABASE ${empresa};"
    PGPASSWORD="$db_password" psql -U ${empresa} -h 127.0.0.1 -d ${empresa} -c "ANALYZE;"
EOF
    sleep 2
  } || trata_erro "otimiza_banco_atualizar"
}

baixa_codigo_atualizar() {
  printf "${WHITE} >> Recuperando Permissões da empresa ${empresa}... \n"
  sleep 2
  chown deploy -R /home/deploy/${empresa}
  chmod 775 -R /home/deploy/${empresa}

  sleep 2

  printf "${WHITE} >> Parando Instancias... \n"
  sleep 2
  sudo su - deploy <<EOF
  pm2 stop all
EOF

  sleep 2

  otimiza_banco_atualizar

  printf "${WHITE} >> Atualizando a Aplicação da Empresa ${empresa}... \n"
  sleep 2

  # Atualizar token do Git antes de fazer o pull
  atualiza_token_git
  verifica_interrupcao

  source /home/deploy/${empresa}/frontend/.env
  frontend_port=${SERVER_PORT:-3000}
  
  # Verificar se o diretório existe
  if [ ! -d "/home/deploy/${empresa}" ]; then
    printf "${RED} >> Diretório da empresa ${empresa} não encontrado!${WHITE}\n"
    trata_erro "verificacao_diretorio"
  fi
  
  printf "${WHITE} >> Atualizando Backend...\n"
  echo
  
  # Mudar para o diretório da empresa
  cd /home/deploy/${empresa}
  
  # Executar comandos Git como usuário deploy
  sudo -u deploy git reset --hard
  verifica_interrupcao
  
  sudo -u deploy git pull
  verifica_interrupcao
  
  # Atualizar Backend
  cd /home/deploy/${empresa}/backend
  sudo -u deploy npm prune --force > /dev/null 2>&1
  sudo -u deploy bash -c 'export PUPPETEER_SKIP_DOWNLOAD=true'
  sudo -u deploy rm -rf node_modules
  sudo -u deploy rm -f package-lock.json
  sudo -u deploy npm install --force
  verifica_interrupcao
  
  sudo -u deploy npm install puppeteer-core --force
  verifica_interrupcao
  
  sudo -u deploy npm i glob
  verifica_interrupcao
  
  # sudo -u deploy npm install jimp@^1.6.0
  sudo -u deploy npm run build
  verifica_interrupcao
  
  sleep 2
  
  printf "${WHITE} >> Atualizando Banco da empresa ${empresa}...\n"
  echo
  sleep 2
  
  sudo -u deploy npx sequelize db:migrate
  
  sleep 2
  
  printf "${WHITE} >> Atualizando Frontend da ${empresa}...\n"
  echo
  sleep 2
  
  cd /home/deploy/${empresa}/frontend
  sudo -u deploy npm prune --force > /dev/null 2>&1
  sudo -u deploy npm install --force
  sudo -u deploy sed -i 's/3000/'"$frontend_port"'/g' server.js
  sudo -u deploy bash -c 'NODE_OPTIONS="--max-old-space-size=4096 --openssl-legacy-provider" npm run build'
  
  sleep 2
  
  # Reiniciar PM2
  sudo -u deploy pm2 flush
  sudo -u deploy pm2 reset all
  sudo -u deploy pm2 start all

  # Reiniciar serviços de proxy
  if systemctl is-active --quiet nginx; then
    systemctl restart nginx
    printf "${GREEN} >> Nginx reiniciado com sucesso${WHITE}\n"
  elif systemctl is-active --quiet traefik; then
    systemctl restart traefik.service
    printf "${GREEN} >> Traefik reiniciado com sucesso${WHITE}\n"
  else
    printf "${YELLOW} >> Nenhum serviço de proxy (Nginx ou Traefik) está em execução.${WHITE}\n"
  fi

  echo
  printf "${WHITE} >> Atualização do ${nome_titulo} concluída...\n"
  echo
  sleep 5

# Extrair versão atual do package.json
versao_atual=$(grep '"version":' /home/deploy/${empresa}/frontend/package.json | cut -d'"' -f4)

# Dados do Whaticket
TOKEN="ultranotificacoes"
QUEUE_ID="15"
USER_ID=""
MENSAGEM="🚨 Atualização do ${nome_titulo} FINALIZADA - Versão ${versao_atual}"

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
backup_app_atualizar
baixa_codigo_atualizar
