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
  INSTALADOR_DIR="/root/instalador_single_oficial"
  ARQUIVO_VARIAVEIS_INSTALADOR="${INSTALADOR_DIR}/VARIAVEIS_INSTALACAO"
  
  # Primeiro tenta carregar do diretório do instalador
  if [ -f "$ARQUIVO_VARIAVEIS_INSTALADOR" ]; then
    source "$ARQUIVO_VARIAVEIS_INSTALADOR"
  # Depois tenta do diretório atual
  elif [ -f $ARQUIVO_VARIAVEIS ]; then
    source $ARQUIVO_VARIAVEIS
  else
    empresa="multiflow"
    nome_titulo="MultiFlow"
  fi
}

# Função para verificar se a instalação foi feita pelo instalador
verificar_instalacao_original() {
  printf "${WHITE} >> Verificando se a instalação foi feita pelo instalador...\n"
  echo
  
  INSTALADOR_DIR="/root/instalador_single_oficial"
  ARQUIVO_VARIAVEIS_INSTALADOR="${INSTALADOR_DIR}/VARIAVEIS_INSTALACAO"
  
  if [ ! -d "$INSTALADOR_DIR" ]; then
    printf "${RED}❌ ERRO: A pasta ${INSTALADOR_DIR} não foi encontrada.\n"
    printf "${RED}   Não é possível continuar a atualização, pois os dados da instalação original não foram encontrados.${WHITE}\n"
    echo
    exit 1
  fi
  
  if [ ! -f "$ARQUIVO_VARIAVEIS_INSTALADOR" ]; then
    printf "${RED}❌ ERRO: O arquivo ${ARQUIVO_VARIAVEIS_INSTALADOR} não foi encontrado.\n"
    printf "${RED}   Não é possível continuar a atualização, pois os dados da instalação original não foram encontrados.${WHITE}\n"
    echo
    exit 1
  fi
  
  printf "${GREEN}✅ Verificação concluída: Instalação original encontrada. Prosseguindo com a atualização...${WHITE}\n"
  echo
  sleep 2
}

# Função para verificar se já está na versão PRO
verificar_versao_pro() {
  printf "${WHITE} >> Verificando se já está configurado para a versão PRO...\n"
  echo
  
  # Carregar variáveis para obter o nome da empresa
  dummy_carregar_variaveis
  
  GIT_CONFIG_FILE="/home/deploy/${empresa}/.git/config"
  
  # Verificar se o arquivo .git/config existe
  if [ ! -f "$GIT_CONFIG_FILE" ]; then
    printf "${YELLOW}⚠️  AVISO: O arquivo ${GIT_CONFIG_FILE} não foi encontrado. Continuando...${WHITE}\n"
    echo
    sleep 2
    return 0
  fi
  
  # Verificar se a URL já contém multiflow-pro
  if grep -q "multiflow-pro" "$GIT_CONFIG_FILE"; then
    printf "${YELLOW}══════════════════════════════════════════════════════════════════${WHITE}\n"
    printf "${GREEN}✅ A versão PRO já está configurada!${WHITE}\n"
    echo
    printf "${WHITE}   O repositório já está apontando para ${BLUE}multiflow-pro${WHITE}.\n"
    printf "${WHITE}   Não é necessário executar este atualizador.${WHITE}\n"
    echo
    printf "${YELLOW}   Para atualizar sua instalação, execute a ${WHITE}atualização normal${YELLOW}.${WHITE}\n"
    printf "${YELLOW}══════════════════════════════════════════════════════════════════${WHITE}\n"
    echo
    exit 0
  fi
  
  printf "${BLUE} >> Versão PRO não detectada. Prosseguindo com a migração para PRO...${WHITE}\n"
  echo
  sleep 2
}

# Função para coletar token e atualizar .git/config
atualizar_git_config() {
  printf "${WHITE} >> Coletando token de autorização e atualizando configuração do Git...\n"
  echo
  
  # Solicitar o token do usuário (fora do bloco para garantir escopo global)
  printf "${WHITE} >> Digite o TOKEN de autorização do GitHub para acesso ao repositório multiflow-pro:${WHITE}\n"
  echo
  read -p "> " TOKEN_AUTH
  
  # Verificar se o token foi informado
  if [ -z "$TOKEN_AUTH" ]; then
    printf "${RED}❌ ERRO: Token de autorização não pode estar vazio.${WHITE}\n"
    exit 1
  fi
  
  printf "${BLUE} >> Token de autorização recebido.${WHITE}\n"
  echo
  
  {
    # Carregar variável empresa se ainda não estiver definida
    if [ -z "$empresa" ]; then
      dummy_carregar_variaveis
    fi
    
    # Carregar o token antigo do arquivo VARIAVEIS_INSTALACAO
    INSTALADOR_DIR="/root/instalador_single_oficial"
    ARQUIVO_VARIAVEIS_INSTALADOR="${INSTALADOR_DIR}/VARIAVEIS_INSTALACAO"
    
    if [ -f "$ARQUIVO_VARIAVEIS_INSTALADOR" ]; then
      source "$ARQUIVO_VARIAVEIS_INSTALADOR"
    else
      printf "${RED}❌ ERRO: Não foi possível carregar o arquivo de variáveis do instalador.${WHITE}\n"
      exit 1
    fi
    
    # Verificar se o token antigo existe
    if [ -z "$github_token" ]; then
      printf "${RED}❌ ERRO: Token de autorização (github_token) não encontrado no arquivo de variáveis.${WHITE}\n"
      exit 1
    fi
    
    TOKEN_ANTIGO="$github_token"
    printf "${BLUE} >> Token antigo carregado do arquivo VARIAVEIS_INSTALACAO.${WHITE}\n"
    
    GIT_CONFIG_FILE="/home/deploy/${empresa}/.git/config"
    
    # Verificar se o arquivo .git/config existe
    if [ ! -f "$GIT_CONFIG_FILE" ]; then
      printf "${RED}❌ ERRO: O arquivo ${GIT_CONFIG_FILE} não foi encontrado.${WHITE}\n"
      exit 1
    fi
    
    # Fazer backup do arquivo original
    cp "$GIT_CONFIG_FILE" "${GIT_CONFIG_FILE}.backup.$(date +%Y%m%d_%H%M%S)"
    printf "${BLUE} >> Backup do arquivo .git/config criado.${WHITE}\n"
    
    # Atualizar a URL do repositório usando o token antigo do arquivo VARIAVEIS_INSTALACAO
    # Usar grep -F para busca literal (sem regex) do token
    if grep -Fq "${TOKEN_ANTIGO}@github.com/scriptswhitelabel/multiflow" "$GIT_CONFIG_FILE"; then
      # Escapar caracteres especiais do token para uso em sed
      TOKEN_ANTIGO_ESCAPED=$(printf '%s\n' "$TOKEN_ANTIGO" | sed 's/[[\.*^$()+?{|]/\\&/g')
      sed -i "s|url = https://${TOKEN_ANTIGO_ESCAPED}@github.com/scriptswhitelabel/multiflow|url = https://${TOKEN_AUTH}@github.com/scriptswhitelabel/multiflow-pro|g" "$GIT_CONFIG_FILE"
      printf "${GREEN}✅ URL do repositório atualizada com sucesso.${WHITE}\n"
    else
      # Tentar padrão mais genérico caso o token específico não seja encontrado
      if grep -q "url = https://.*@github.com/scriptswhitelabel/multiflow" "$GIT_CONFIG_FILE"; then
        sed -i "s|url = https://.*@github.com/scriptswhitelabel/multiflow|url = https://${TOKEN_AUTH}@github.com/scriptswhitelabel/multiflow-pro|g" "$GIT_CONFIG_FILE"
        printf "${GREEN}✅ URL do repositório atualizada com sucesso (padrão genérico).${WHITE}\n"
      else
        printf "${YELLOW}⚠️  AVISO: Padrão de URL não encontrado no arquivo .git/config. Verificando manualmente...${WHITE}\n"
        # Tentar substituir qualquer URL que contenha scriptswhitelabel/multiflow
        sed -i "s|\(url = https://\)[^@]*\(@github.com/scriptswhitelabel/multiflow\)|\1${TOKEN_AUTH}\2-pro|g" "$GIT_CONFIG_FILE"
        printf "${GREEN}✅ Tentativa de atualização realizada.${WHITE}\n"
      fi
    fi
    
    echo
    sleep 2
    
    # Testar o token fazendo um git clone de teste
    printf "${WHITE} >> Validando token com teste de git clone...\n"
    echo
    
    TEST_DIR="${INSTALADOR_DIR}/test_clone_$(date +%s)"
    REPO_URL="https://${TOKEN_AUTH}@github.com/scriptswhitelabel/multiflow-pro.git"
    
    # Tentar fazer clone de teste
    if git clone --depth 1 "${REPO_URL}" "${TEST_DIR}" >/dev/null 2>&1; then
      # Clone bem-sucedido, remover diretório de teste
      rm -rf "${TEST_DIR}" >/dev/null 2>&1
      printf "${GREEN}✅ Token validado com sucesso! Git clone funcionou corretamente.${WHITE}\n"
      echo
      sleep 2
    else
      # Clone falhou, token inválido
      rm -rf "${TEST_DIR}" >/dev/null 2>&1
      printf "${RED}❌ ERRO: Token de autorização inválido!${WHITE}\n"
      printf "${RED}   O teste de git clone falhou. Verifique se o token está correto e tem as permissões necessárias.${WHITE}\n"
      printf "${RED}   Atualização interrompida.${WHITE}\n"
      echo
      exit 1
    fi
    
  } || {
    printf "${RED}❌ ERRO: Falha ao atualizar configuração do Git na etapa atualizar_git_config.${WHITE}\n"
    trata_erro "atualizar_git_config"
  }
}

# Função para atualizar o token no arquivo VARIAVEIS_INSTALACAO
atualizar_token_variaveis() {
  printf "${WHITE} >> Atualizando token no arquivo VARIAVEIS_INSTALACAO...\n"
  echo
  
  {
    INSTALADOR_DIR="/root/instalador_single_oficial"
    ARQUIVO_VARIAVEIS_INSTALADOR="${INSTALADOR_DIR}/VARIAVEIS_INSTALACAO"
    
    # Verificar se o arquivo existe
    if [ ! -f "$ARQUIVO_VARIAVEIS_INSTALADOR" ]; then
      printf "${RED}❌ ERRO: O arquivo ${ARQUIVO_VARIAVEIS_INSTALADOR} não foi encontrado.${WHITE}\n"
      exit 1
    fi
    
    # Verificar se TOKEN_AUTH foi definido
    if [ -z "$TOKEN_AUTH" ]; then
      printf "${RED}❌ ERRO: TOKEN_AUTH não foi definido.${WHITE}\n"
      exit 1
    fi
    
    # Fazer backup do arquivo original
    cp "$ARQUIVO_VARIAVEIS_INSTALADOR" "${ARQUIVO_VARIAVEIS_INSTALADOR}.backup.$(date +%Y%m%d_%H%M%S)"
    printf "${BLUE} >> Backup do arquivo VARIAVEIS_INSTALACAO criado.${WHITE}\n"
    
    # Atualizar a linha github_token no arquivo
    if grep -q "^github_token=" "$ARQUIVO_VARIAVEIS_INSTALADOR"; then
      # Substituir a linha existente
      sed -i "s|^github_token=.*|github_token=${TOKEN_AUTH}|g" "$ARQUIVO_VARIAVEIS_INSTALADOR"
      printf "${GREEN}✅ Token atualizado no arquivo VARIAVEIS_INSTALACAO com sucesso.${WHITE}\n"
    else
      # Se não existir a linha, adicionar no final do arquivo
      echo "github_token=${TOKEN_AUTH}" >> "$ARQUIVO_VARIAVEIS_INSTALADOR"
      printf "${GREEN}✅ Token adicionado ao arquivo VARIAVEIS_INSTALACAO com sucesso.${WHITE}\n"
    fi
    
    echo
    sleep 2
    
  } || {
    printf "${RED}❌ ERRO: Falha ao atualizar token no arquivo VARIAVEIS_INSTALACAO na etapa atualizar_token_variaveis.${WHITE}\n"
    trata_erro "atualizar_token_variaveis"
  }
}

# Função para verificar e instalar Node.js 20.19.4
verificar_e_instalar_nodejs() {
  printf "${WHITE} >> Verificando versão do Node.js instalada...\n"
  
  # Verificar se o Node.js está instalado e qual versão
  if command -v node >/dev/null 2>&1; then
    NODE_VERSION=$(node -v | sed 's/v//')
    printf "${BLUE} >> Versão atual do Node.js: ${NODE_VERSION}\n"
    
    # Verificar se a versão é diferente de 20.19.4
    if [ "$NODE_VERSION" != "20.19.4" ]; then
      printf "${YELLOW} >> Versão do Node.js diferente de 20.19.4. Iniciando atualização...\n"
      
      {
        echo "=== Removendo Node.js antigo (apt) ==="
        sudo apt remove -y nodejs npm || true
        sudo apt purge -y nodejs || true
        sudo apt autoremove -y || true

        echo "=== Limpando links antigos ==="
        sudo rm -f /usr/bin/node || true
        sudo rm -f /usr/bin/npm || true

        echo "=== Instalando Node.js temporário para ter npm ==="
        curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -
        sudo apt install -y nodejs

        echo "=== Instalando gerenciador 'n' ==="
        sudo npm install -g n

        echo "=== Instalando Node.js 20.19.4 ==="
        sudo n 20.19.4

        echo "=== Ajustando links globais para a versão correta ==="
        sudo ln -sf /usr/local/n/versions/node/20.19.4/bin/node /usr/bin/node
        sudo ln -sf /usr/local/n/versions/node/20.19.4/bin/npm /usr/bin/npm

        echo "=== Versões instaladas ==="
        node -v
        npm -v

        printf "${GREEN}✅ Instalação finalizada! Node.js 20.19.4 está ativo.\n"
        
      } || trata_erro "verificar_e_instalar_nodejs"
      
    else
      printf "${GREEN} >> Node.js já está na versão correta (20.19.4). Prosseguindo...\n"
    fi
  else
    printf "${YELLOW} >> Node.js não encontrado. Iniciando instalação...\n"
    
    {
      echo "=== Instalando Node.js temporário para ter npm ==="
      curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -
      sudo apt install -y nodejs

      echo "=== Instalando gerenciador 'n' ==="
      sudo npm install -g n

      echo "=== Instalando Node.js 20.19.4 ==="
      sudo n 20.19.4

      echo "=== Ajustando links globais para a versão correta ==="
      sudo ln -sf /usr/local/n/versions/node/20.19.4/bin/node /usr/bin/node
      sudo ln -sf /usr/local/n/versions/node/20.19.4/bin/npm /usr/bin/npm

      echo "=== Versões instaladas ==="
      node -v
      npm -v

      printf "${GREEN}✅ Instalação finalizada! Node.js 20.19.4 está ativo.\n"
      
    } || trata_erro "verificar_e_instalar_nodejs"
  fi
  
  sleep 2
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
MENSAGEM="🚨 INICIANDO Atualização do ${nome_titulo} para MULTIFLOW-PRO"

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
  # pm2 stop all
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

git fetch origin
git checkout MULTI100-OFICIAL-u21
git reset --hard origin/MULTI100-OFICIAL-u21

# git reset --hard
# git pull

cd /home/deploy/${empresa}/backend
npm prune --force > /dev/null 2>&1
export PUPPETEER_SKIP_DOWNLOAD=true
rm -r node_modules
rm package-lock.json
rm -r dist
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
rm -r node_modules
rm package-lock.json
npm install --force
sed -i 's/3000/'"$frontend_port"'/g' server.js
NODE_OPTIONS="--max-old-space-size=4096 --openssl-legacy-provider" npm run build
sleep 2
pm2 flush
pm2 reset all
pm2 restart all
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
MENSAGEM="🚨 Atualização do ${nome_titulo} FINALIZADA para MULTIFLOW-PRO"

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
verificar_instalacao_original
verificar_versao_pro
atualizar_git_config
verificar_e_instalar_nodejs
backup_app_atualizar
baixa_codigo_atualizar
atualizar_token_variaveis
