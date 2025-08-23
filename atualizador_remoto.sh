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

# --- Identidade Git p/ commits/merges automáticos ---
GIT_USER_NAME="${GIT_USER_NAME:-Cliente Atualizador}"
GIT_USER_EMAIL="${GIT_USER_EMAIL:-cliente@scriptswhitelabel.com.br}"
# ----------------------------------------------------

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

  source /home/deploy/${empresa}/frontend/.env
  frontend_port=${SERVER_PORT:-3000}
  sudo su - deploy <<EOF
printf "${WHITE} >> Atualizando Backend...\n"
echo
cd /home/deploy/${empresa}

# ===== Atualização segura sem commits/merges =====
BRANCH="${GIT_BRANCH:-MULTI100-OFICIAL-u21}"
# Coloque sua URL com PAT aqui OU deixe vazio para manter a atual
# Ex.: https://<PAT>@github.com/scriptswhitelabel/multiflow
REMOTE_URL_DEFAULT=""
REMOTE_URL="${GIT_REMOTE_URL:-$REMOTE_URL_DEFAULT}"

# Se quiser forçar a URL do origin a cada update (igual ao gitconfig que funciona):
if [ -n "$REMOTE_URL" ]; then
  git remote set-url origin "$REMOTE_URL"
fi

# Garante configurações equivalentes ao seu gitconfig
git config pull.rebase false
git config branch."$BRANCH".remote origin
git config branch."$BRANCH".merge "refs/heads/$BRANCH"

# Busca últimas refs e limpa refs antigas
git fetch --tags --prune origin

# Garante que estamos na branch desejada
if git rev-parse --verify "$BRANCH" >/dev/null 2>&1; then
  git checkout "$BRANCH"
else
  # cria a branch local rastreando a remota
  git checkout -B "$BRANCH" "origin/$BRANCH"
fi

# Evita qualquer merge/commit: força estado igual ao remoto
git reset --hard "origin/$BRANCH"
# Remove arquivos/pastas não rastreados (ex.: build antigos)
git clean -fd
# ================================================

cd /home/deploy/${empresa}/backend
npm prune --force > /dev/null 2>&1
export PUPPETEER_SKIP_DOWNLOAD=true
rm -r node_modules
rm package-lock.json
npm install --force
npm install puppeteer-core --force
npm i glob
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
npm prune --force > /dev/null 2>&1
npm install --force
sed -i 's/3000/'"$frontend_port"'/g' server.js
NODE_OPTIONS="--max-old-space-size=4096 --openssl-legacy-provider" npm run build
sleep 2
pm2 flush
pm2 reset all
pm2 start all
pm2 save
pm2 startup
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
backup_app_atualizar
baixa_codigo_atualizar
