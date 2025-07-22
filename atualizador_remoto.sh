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
  dummy_carregar_variaveis
  source /home/deploy/${empresa}/backend/.env
  {
    printf "${WHITE} >> Fazendo backup do banco de dados...\n"
    db_password=$(grep "DB_PASS=" /home/deploy/${empresa}/backend/.env | cut -d '=' -f2)
    [ ! -d "/home/deploy/backups" ] && mkdir -p "/home/deploy/backups"
    backup_file="/home/deploy/backups/${empresa}_$(date +%d-%m-%Y_%Hh).sql"
    PGPASSWORD="${db_password}" pg_dump -U ${empresa} -h localhost ${empresa} >"${backup_file}"
    printf "${GREEN} >> Backup do banco de dados ${empresa} concluído. Arquivo de backup: ${backup_file}\n"
    sleep 2
  } || trata_erro "backup_app_atualizar"
}

otimiza_banco_atualizar() {
  printf "${WHITE} >> Realizando Manutenção do Banco de Dados... \n"
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
  printf "${WHITE} >> Recuperando Permissões... \n"
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

  printf "${WHITE} >> Atualizando a Aplicação... \n"
  sleep 2

  source /home/deploy/${empresa}/frontend/.env
  frontend_port=${SERVER_PORT:-3000}
  sudo su - deploy <<EOF
printf "${WHITE} >> Atualizando Backend...\n"
echo
cd /home/deploy/${empresa}
git reset --hard
git pull
cd /home/deploy/${empresa}/backend
npm prune --force > /dev/null 2>&1
export PUPPETEER_SKIP_DOWNLOAD=true
rm -r node_modules
rm package-lock.json
npm install --force
npm install puppeteer-core --force
npm i glob
npm install jimp@^1.6.0
npm run build
sleep 2
printf "${WHITE} >> Atualizando Banco...\n"
echo
sleep 2
npx sequelize db:migrate
sleep 2
printf "${WHITE} >> Atualizando Frontend...\n"
echo
sleep 2
cd /home/deploy/${empresa}/frontend
npm prune --force > /dev/null 2>&1
npm install --force
sed -i 's/3000/'"$frontend_port"'/g' server.js
NODE_OPTIONS="--max-old-space-size=4096 --openssl-legacy-provider" npm run build
sleep 2
pm2 flush
pm2 start all
EOF

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
}

# Execução automática do fluxo de atualização
backup_app_atualizar
baixa_codigo_atualizar
