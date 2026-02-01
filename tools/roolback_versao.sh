#!/bin/bash

GREEN='\033[1;32m'
BLUE='\033[1;34m'
WHITE='\033[1;37m'
RED='\033[1;31m'
YELLOW='\033[1;33m'

# Variáveis Padrão
ARQUIVO_VARIAVEIS="VARIAVEIS_INSTALACAO"
INSTALADOR_DIR="/root/instalador_single_oficial"
ARQUIVO_VARIAVEIS_INSTALADOR="${INSTALADOR_DIR}/VARIAVEIS_INSTALACAO"

# Verificar se está rodando como root
if [ "$EUID" -ne 0 ]; then
  echo
  printf "${WHITE} >> Este script precisa ser executado como root ${RED}ou com privilégios de superusuário${WHITE}.\n"
  echo
  sleep 2
  exit 1
fi

# Carregar variáveis da instalação
carregar_variaveis() {
  # Primeiro tenta carregar do diretório do instalador
  if [ -f "$ARQUIVO_VARIAVEIS_INSTALADOR" ]; then
    source "$ARQUIVO_VARIAVEIS_INSTALADOR"
    printf "${GREEN} >> Variáveis carregadas de: ${ARQUIVO_VARIAVEIS_INSTALADOR}\n${WHITE}"
  # Depois tenta do diretório atual
  elif [ -f "$ARQUIVO_VARIAVEIS" ]; then
    source "$ARQUIVO_VARIAVEIS"
    printf "${GREEN} >> Variáveis carregadas de: ${ARQUIVO_VARIAVEIS}\n${WHITE}"
  else
    printf "${YELLOW} >> Arquivo de variáveis não encontrado. Usando valores padrão.\n${WHITE}"
    empresa="multiflow"
    nome_titulo="MultiFlow"
  fi
}

# Banner
banner() {
  printf "${BLUE}"
  printf "\n\n"
  printf "██████╗  ██████╗  ██████╗ ██╗     ██████╗  █████╗  ██████╗██╗  ██╗\n"
  printf "██╔══██╗██╔═══██╗██╔═══██╗██║     ██╔══██╗██╔══██╗██╔════╝██║ ██╔╝\n"
  printf "██████╔╝██║   ██║██║   ██║██║     ██████╔╝███████║██║     █████╔╝ \n"
  printf "██╔══██╗██║   ██║██║   ██║██║     ██╔══██╗██╔══██║██║     ██╔═██╗ \n"
  printf "██║  ██║╚██████╔╝╚██████╔╝███████╗██████╔╝██║  ██║╚██████╗██║  ██╗\n"
  printf "╚═╝  ╚═╝ ╚═════╝  ╚═════╝ ╚══════╝╚═════╝ ╚═╝  ╚═╝ ╚═════╝╚═╝  ╚═╝\n"
  printf "                          DE VERSÃO DO SISTEMA\n"
  printf "\n\n${WHITE}"
}

# Função para tratar erros
trata_erro() {
  printf "${RED}Erro encontrado na etapa: $1. Encerrando o script.${WHITE}\n"
  exit 1
}

# Definir lista de versões disponíveis
# Formato: "versao:commit_hash"
definir_versoes() {
  declare -gA VERSOES
  VERSOES["6.6"]="1692f830009b4364126c763fa7702bf401280989"
  VERSOES["6.4.5"]="251c6f693b67c76468311b0ca9c41f89f8a3aca0"
  VERSOES["6.4.4"]="b5de35ebb4acb10694ce4e8b8d6068b31eeabef9"
  VERSOES["6.4.3"]="6aa224db151bd8cbbf695b07a8624c976e89db00"
  VERSOES["6.5.2"]="6607976a25f86127bd494bba20017fe6bbd9f50a"
  VERSOES["6.5"]="ab5565df5937f6113bbbb6b2ce9c526e25e525ef"
   # Adicione mais versões aqui conforme necessário
  # VERSOES["6.4.2"]="outro_commit_hash_aqui"
  # VERSOES["6.4.1"]="outro_commit_hash_aqui"
}

# Mostrar lista de versões disponíveis
mostrar_lista_versoes() {
  printf "${WHITE}═══════════════════════════════════════════════════════════\n"
  printf "  VERSÕES DISPONÍVEIS PARA ROLLBACK\n"
  printf "═══════════════════════════════════════════════════════════\n${WHITE}"
  echo
  
  local index=1
  for versao in $(printf '%s\n' "${!VERSOES[@]}" | sort -V -r); do
    printf "${BLUE}  [$index]${WHITE} Versão ${GREEN}${versao}${WHITE}\n"
    printf "      Commit: ${YELLOW}${VERSOES[$versao]}${WHITE}\n"
    echo
    ((index++))
  done
  
  printf "${WHITE}═══════════════════════════════════════════════════════════\n${WHITE}"
  echo
}

# Validar token do GitHub
validar_token_github() {
  banner
  printf "${WHITE} >> Validação de Token do GitHub${WHITE}\n"
  echo
  
  # Verificar se já existe token salvo nas variáveis
  if [ -n "${github_token}" ]; then
    printf "${GREEN} >> Token do GitHub encontrado nas variáveis.${WHITE}\n"
    printf "${YELLOW} >> Deseja usar o token salvo ou informar um novo? (usar/novo):${WHITE}\n"
    read -p "> " usar_token_salvo
    
    if [ "$usar_token_salvo" != "novo" ] && [ "$usar_token_salvo" != "NOVO" ]; then
      TOKEN_AUTH="${github_token}"
      printf "${GREEN} >> Usando token salvo.${WHITE}\n"
      echo
    else
      printf "${WHITE} >> Digite o TOKEN de autorização do GitHub para acesso ao repositório multiflow-pro:${WHITE}\n"
      echo
      read -p "> " TOKEN_AUTH
    fi
  else
    printf "${WHITE} >> Digite o TOKEN de autorização do GitHub para acesso ao repositório multiflow-pro:${WHITE}\n"
    echo
    read -p "> " TOKEN_AUTH
  fi
  
  # Verificar se o token foi informado
  if [ -z "$TOKEN_AUTH" ]; then
    printf "${RED}❌ ERRO: Token de autorização não pode estar vazio.${WHITE}\n"
    sleep 2
    exit 1
  fi
  
  printf "${BLUE} >> Token de autorização recebido. Validando...${WHITE}\n"
  echo
  
  # Validar o token usando teste de git clone
  INSTALADOR_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  TEST_DIR="${INSTALADOR_DIR}/test_clone_$(date +%s)"
  REPO_URL="https://${TOKEN_AUTH}@github.com/scriptswhitelabel/multiflow-pro.git"
  
  printf "${WHITE} >> Validando token com teste de git clone...\n"
  echo
  
  # Tentar fazer clone de teste
  if git clone --depth 1 "${REPO_URL}" "${TEST_DIR}" >/dev/null 2>&1; then
    # Clone bem-sucedido, remover diretório de teste
    rm -rf "${TEST_DIR}" >/dev/null 2>&1
    printf "${GREEN}✅ Token validado com sucesso! Git clone funcionou corretamente.${WHITE}\n"
    echo
    sleep 2
    
    # Salvar token validado como variável global
    declare -g GITHUB_TOKEN_VALIDATED="$TOKEN_AUTH"
  else
    # Clone falhou, token inválido
    rm -rf "${TEST_DIR}" >/dev/null 2>&1
    printf "${RED}═══════════════════════════════════════════════════════════${WHITE}\n"
    printf "${RED}❌ ERRO: Token de autorização inválido!${WHITE}\n"
    echo
    printf "${RED}   O teste de git clone falhou. O token informado não tem acesso ao repositório multiflow-pro.${WHITE}\n"
    echo
    printf "${YELLOW}   ⚠️  IMPORTANTE:${WHITE}\n"
    printf "${YELLOW}   O MultiFlow PRO é um projeto fechado e requer autorização especial.${WHITE}\n"
    printf "${YELLOW}   Para solicitar acesso ou analisar a disponibilidade,${WHITE}\n"
    printf "${YELLOW}   entre em contato com o suporte.${WHITE}\n"
    echo
    printf "${RED}═══════════════════════════════════════════════════════════${WHITE}\n"
    echo
    sleep 5
    exit 1
  fi
}

# Selecionar versão da lista
selecionar_versao() {
  local versoes_array=($(printf '%s\n' "${!VERSOES[@]}" | sort -V -r))
  local total_versoes=${#versoes_array[@]}
  
  if [ $total_versoes -eq 0 ]; then
    printf "${RED} >> ERRO: Nenhuma versão disponível na lista.\n${WHITE}"
    exit 1
  fi
  
  mostrar_lista_versoes
  
  printf "${YELLOW} >> Selecione a versão desejada (1-${total_versoes}):${WHITE}\n"
  read -p "> " ESCOLHA
  
  # Validar entrada
  if ! [[ "$ESCOLHA" =~ ^[0-9]+$ ]]; then
    printf "${RED} >> ERRO: Entrada inválida. Digite um número.\n${WHITE}"
    exit 1
  fi
  
  if [ "$ESCOLHA" -lt 1 ] || [ "$ESCOLHA" -gt $total_versoes ]; then
    printf "${RED} >> ERRO: Opção inválida. Escolha um número entre 1 e ${total_versoes}.\n${WHITE}"
    exit 1
  fi
  
  # Obter versão e commit selecionados (variáveis globais)
  local index=$((ESCOLHA - 1))
  declare -g VERSION_SELECTED="${versoes_array[$index]}"
  declare -g COMMIT_SELECTED="${VERSOES[$VERSION_SELECTED]}"
  
  printf "\n${GREEN} >> Versão selecionada: ${BLUE}${VERSION_SELECTED}${WHITE}\n"
  printf "${GREEN} >> Commit: ${BLUE}${COMMIT_SELECTED}${WHITE}\n"
  echo
}

# Função principal de rollback
rollback_versao() {
  banner
  
  # Carregar variáveis
  carregar_variaveis
  
  # Verificar se a variável empresa está definida
  if [ -z "${empresa}" ]; then
    printf "${RED} >> ERRO: Variável 'empresa' não está definida!\n${WHITE}"
    printf "${YELLOW} >> Por favor, informe o nome da empresa:${WHITE}\n"
    read -p "> " empresa
    if [ -z "${empresa}" ]; then
      printf "${RED} >> ERRO: Nome da empresa não pode ser vazio. Abortando.\n${WHITE}"
      exit 1
    fi
  fi
  
  # Definir diretório da aplicação
  APP_DIR="/home/deploy/${empresa}"
  
  # Verificar se o diretório existe
  if [ ! -d "$APP_DIR" ]; then
    printf "${RED} >> ERRO: Diretório da aplicação não existe: ${APP_DIR}\n${WHITE}"
    exit 1
  fi
  
  printf "${WHITE} >> Diretório da aplicação: ${BLUE}${APP_DIR}${WHITE}\n"
  echo
  
  # Validar token do GitHub antes de continuar
  validar_token_github
  
  # Definir versões disponíveis
  definir_versoes
  
  # Selecionar versão da lista
  selecionar_versao
  
  # Usar commit selecionado
  COMMIT_ALVO="$COMMIT_SELECTED"
  VERSION_ALVO="$VERSION_SELECTED"
  
  printf "\n${YELLOW} ⚠️  ATENÇÃO: Esta operação irá:${WHITE}\n"
  printf "${YELLOW}    - Apagar todas as alterações locais não commitadas${WHITE}\n"
  printf "${YELLOW}    - Fazer rollback para a versão: ${BLUE}${VERSION_ALVO}${WHITE}\n"
  printf "${YELLOW}    - Commit: ${BLUE}${COMMIT_ALVO}${WHITE}\n"
  printf "${YELLOW}    - Reinstalar dependências e rebuild${WHITE}\n"
  printf "${YELLOW}    - Reiniciar aplicações no PM2${WHITE}\n"
  echo
  printf "${RED} >> Deseja continuar? (s/N):${WHITE}\n"
  read -p "> " CONFIRMA
  
  if [ "$CONFIRMA" != "s" ] && [ "$CONFIRMA" != "S" ]; then
    printf "${YELLOW} >> Operação cancelada pelo usuário.${WHITE}\n"
    exit 0
  fi
  
  echo
  printf "${WHITE} >> Iniciando rollback de versão...\n"
  echo
  
  # 1) Entrar na pasta do projeto e corrigir permissões
  printf "${WHITE} [1/11] Entrando na pasta do projeto e corrigindo permissões...\n"
  cd "$APP_DIR" || trata_erro "cd para pasta do projeto"
  
  # Corrigir permissões do diretório .git e todo o repositório
  printf "${WHITE} >> Corrigindo permissões do repositório...\n"
  chown -R deploy:deploy "$APP_DIR" 2>/dev/null || true
  
  # Garantir permissões específicas para .git e .git/objects
  if [ -d "$APP_DIR/.git" ]; then
    chmod -R 755 "$APP_DIR/.git" 2>/dev/null || true
    chown -R deploy:deploy "$APP_DIR/.git" 2>/dev/null || true
    
    # Garantir permissões de escrita no diretório objects
    if [ -d "$APP_DIR/.git/objects" ]; then
      chmod -R 775 "$APP_DIR/.git/objects" 2>/dev/null || true
      chown -R deploy:deploy "$APP_DIR/.git/objects" 2>/dev/null || true
    fi
  fi
  
  chmod -R 775 "$APP_DIR" 2>/dev/null || true
  
  printf "${GREEN} ✓ Diretório atual: $(pwd)\n${WHITE}"
  printf "${GREEN} ✓ Permissões corrigidas\n${WHITE}"
  echo
  
  # 2) Configurar remote com token e fazer git fetch
  printf "${WHITE} [2/11] Configurando remote e executando git fetch --all --prune...\n"
  sudo su - deploy <<FETCH
cd "$APP_DIR"

# Garantir permissões corretas antes do fetch
chmod -R u+w .git 2>/dev/null || true
chown -R deploy:deploy .git 2>/dev/null || true

# Verificar se o remote origin existe e atualizar com token
if git remote get-url origin >/dev/null 2>&1; then
  # Extrair URL do repositório (remover token antigo se existir)
  CURRENT_URL=\$(git remote get-url origin | sed 's|https://[^@]*@|https://|')
  # Se não começar com https://, pode ser SSH, então não alteramos
  if [[ "\$CURRENT_URL" == https://* ]]; then
    # Atualizar remote com token validado
    NEW_URL="https://${GITHUB_TOKEN_VALIDATED}@\$(echo \$CURRENT_URL | sed 's|https://||')"
    git remote set-url origin "\$NEW_URL"
  fi
fi

# Executar git fetch com tratamento de erros
if ! git fetch --all --prune; then
  # Se falhar, tentar corrigir permissões novamente e tentar mais uma vez
  echo "Tentando corrigir permissões e refazer fetch..."
  chmod -R 755 .git
  chown -R deploy:deploy .git
  git fetch --all --prune || {
    echo "ERRO: Falha ao executar git fetch mesmo após corrigir permissões"
    exit 1
  }
fi
FETCH
  if [ $? -ne 0 ]; then
    trata_erro "git fetch"
  fi
  printf "${GREEN} ✓ Git fetch concluído\n${WHITE}"
  echo
  
  # 3) Verificar se o commit existe
  printf "${WHITE} [3/11] Verificando se o commit existe...\n"
  sudo su - deploy <<VERIFY
cd "$APP_DIR"
git cat-file -e "$COMMIT_ALVO^{commit}" 2>/dev/null
VERIFY
  if [ $? -ne 0 ]; then
    printf "${RED} >> ERRO: Commit ${COMMIT_ALVO} não encontrado no repositório.\n${WHITE}"
    printf "${YELLOW} >> Verifique se o commit hash está correto e se você fez git fetch.\n${WHITE}"
    exit 1
  fi
  printf "${GREEN} ✓ Commit encontrado\n${WHITE}"
  echo
  
  # 4) Limpar alterações locais
  printf "${WHITE} [4/11] Limpando alterações locais (git reset --hard)...\n"
  sudo su - deploy <<CLEAN
cd "$APP_DIR"
git reset --hard
CLEAN
  if [ $? -ne 0 ]; then
    trata_erro "git reset --hard"
  fi
  printf "${GREEN} ✓ Alterações locais removidas\n${WHITE}"
  echo
  
  # 5) Limpar arquivos não rastreados
  printf "${WHITE} [5/11] Limpando arquivos não rastreados (git clean -fd)...\n"
  sudo su - deploy <<CLEANFD
cd "$APP_DIR"
git clean -fd
CLEANFD
  if [ $? -ne 0 ]; then
    trata_erro "git clean -fd"
  fi
  printf "${GREEN} ✓ Arquivos não rastreados removidos\n${WHITE}"
  echo
  
  # 6) Fazer checkout para o commit alvo (criando branch de rollback)
  printf "${WHITE} [6/11] Fazendo checkout para o commit alvo (criando branch rollback)...\n"
  BRANCH_ROLLBACK="rollback-$(date +%Y%m%d-%H%M%S)"
  sudo su - deploy <<CHECKOUT
cd "$APP_DIR"
git checkout -b "$BRANCH_ROLLBACK" "$COMMIT_ALVO"
CHECKOUT
  if [ $? -ne 0 ]; then
    trata_erro "git checkout"
  fi
  printf "${GREEN} ✓ Checkout concluído (branch: ${BRANCH_ROLLBACK})\n${WHITE}"
  echo
  
  # 7) Parar aplicações PM2
  printf "${WHITE} [7/11] Parando instâncias PM2...\n"
  sudo su - deploy <<STOPPM2
# Configura PATH para Node.js e PM2
if [ -d /usr/local/n/versions/node/20.19.4/bin ]; then
  export PATH=/usr/local/n/versions/node/20.19.4/bin:/usr/bin:/usr/local/bin:\$PATH
else
  export PATH=/usr/bin:/usr/local/bin:\$PATH
fi
pm2 stop all || true
STOPPM2
  printf "${GREEN} ✓ PM2 parado\n${WHITE}"
  echo
  
  # 8) Reinstalar dependências do Backend
  printf "${WHITE} [8/11] Reinstalando dependências do Backend...\n"
  BACKEND_DIR="${APP_DIR}/backend"
  if [ ! -d "$BACKEND_DIR" ]; then
    printf "${YELLOW} >> Aviso: Diretório backend não encontrado. Pulando...\n${WHITE}"
  else
    sudo su - deploy <<BACKEND
# Configura PATH para Node.js
if [ -d /usr/local/n/versions/node/20.19.4/bin ]; then
  export PATH=/usr/local/n/versions/node/20.19.4/bin:/usr/bin:/usr/local/bin:\$PATH
else
  export PATH=/usr/bin:/usr/local/bin:\$PATH
fi

BACKEND_DIR="$BACKEND_DIR"

if [ ! -d "\$BACKEND_DIR" ]; then
  echo "ERRO: Diretório do backend não existe: \$BACKEND_DIR"
  exit 1
fi

cd "\$BACKEND_DIR"

if [ ! -f "package.json" ]; then
  echo "ERRO: package.json não encontrado em \$BACKEND_DIR"
  exit 1
fi

npm prune --force > /dev/null 2>&1
export PUPPETEER_SKIP_DOWNLOAD=true
rm -rf node_modules 2>/dev/null || true
rm -f package-lock.json 2>/dev/null || true
rm -rf dist 2>/dev/null || true
npm install --force
npm install puppeteer-core --force
npm i glob
npm run build
sleep 2
BACKEND
    if [ $? -ne 0 ]; then
      printf "${RED} >> ERRO ao instalar dependências do backend\n${WHITE}"
      trata_erro "npm install backend"
    fi
    printf "${GREEN} ✓ Dependências do Backend instaladas e buildado\n${WHITE}"
    
    # Executar migração do banco de dados
    printf "${WHITE} >> Executando migração do banco de dados...\n"
    sudo su - deploy <<MIGRATE
# Configura PATH para Node.js
if [ -d /usr/local/n/versions/node/20.19.4/bin ]; then
  export PATH=/usr/local/n/versions/node/20.19.4/bin:/usr/bin:/usr/local/bin:\$PATH
else
  export PATH=/usr/bin:/usr/local/bin:\$PATH
fi

cd "$BACKEND_DIR"
npx sequelize db:migrate
sleep 2
MIGRATE
    if [ $? -ne 0 ]; then
      printf "${YELLOW} >> Aviso: Migração do banco pode ter falhado. Continuando...\n${WHITE}"
    else
      printf "${GREEN} ✓ Migração do banco concluída\n${WHITE}"
    fi
  fi
  echo
  
  # 9) Reinstalar dependências e build do Frontend
  printf "${WHITE} [9/11] Reinstalando dependências e build do Frontend...\n"
  FRONTEND_DIR="${APP_DIR}/frontend"
  
  # Carregar porta do frontend do .env se existir
  source "$FRONTEND_DIR/.env" 2>/dev/null || true
  frontend_port=${SERVER_PORT:-3000}
  
  if [ ! -d "$FRONTEND_DIR" ]; then
    printf "${YELLOW} >> Aviso: Diretório frontend não encontrado. Pulando...\n${WHITE}"
  else
    sudo su - deploy <<FRONTEND
# Configura PATH para Node.js
if [ -d /usr/local/n/versions/node/20.19.4/bin ]; then
  export PATH=/usr/local/n/versions/node/20.19.4/bin:/usr/bin:/usr/local/bin:\$PATH
else
  export PATH=/usr/bin:/usr/local/bin:\$PATH
fi

FRONTEND_DIR="$FRONTEND_DIR"

if [ ! -d "\$FRONTEND_DIR" ]; then
  echo "ERRO: Diretório do frontend não existe: \$FRONTEND_DIR"
  exit 1
fi

cd "\$FRONTEND_DIR"

if [ ! -f "package.json" ]; then
  echo "ERRO: package.json não encontrado em \$FRONTEND_DIR"
  exit 1
fi

npm prune --force > /dev/null 2>&1
rm -rf node_modules 2>/dev/null || true
rm -f package-lock.json 2>/dev/null || true
npm install --force

if [ -f "server.js" ]; then
  sed -i 's/3000/'"$frontend_port"'/g' server.js
fi

NODE_OPTIONS="--max-old-space-size=4096 --openssl-legacy-provider" npm run build
sleep 2
FRONTEND
    if [ $? -ne 0 ]; then
      printf "${RED} >> ERRO ao instalar dependências ou build do frontend\n${WHITE}"
      trata_erro "npm install/build frontend"
    fi
    printf "${GREEN} ✓ Frontend instalado e buildado\n${WHITE}"
  fi
  echo
  
  # 10) Reiniciar PM2
  printf "${WHITE} [10/11] Reiniciando aplicações no PM2...\n"
  sudo su - deploy <<RESTARTPM2
# Configura PATH para Node.js e PM2
if [ -d /usr/local/n/versions/node/20.19.4/bin ]; then
  export PATH=/usr/local/n/versions/node/20.19.4/bin:/usr/bin:/usr/local/bin:\$PATH
else
  export PATH=/usr/bin:/usr/local/bin:\$PATH
fi
pm2 flush
pm2 reset all
pm2 restart all
pm2 save
pm2 startup
RESTARTPM2
  if [ $? -ne 0 ]; then
    printf "${YELLOW} >> Aviso: Algum problema ao reiniciar PM2. Verifique manualmente.\n${WHITE}"
  else
    printf "${GREEN} ✓ PM2 reiniciado e salvo\n${WHITE}"
  fi
  echo
  
  # Resumo final
  printf "\n${GREEN}═══════════════════════════════════════════════════════════\n"
  printf "  ✓ ROLLBACK CONCLUÍDO COM SUCESSO!\n"
  printf "═══════════════════════════════════════════════════════════\n${WHITE}"
  printf "\n${WHITE} >> Resumo da operação:${WHITE}\n"
  printf "   - Empresa: ${BLUE}${empresa}${WHITE}\n"
  printf "   - Diretório: ${BLUE}${APP_DIR}${WHITE}\n"
  printf "   - Versão: ${BLUE}${VERSION_ALVO}${WHITE}\n"
  printf "   - Commit alvo: ${BLUE}${COMMIT_ALVO}${WHITE}\n"
  printf "   - Branch criada: ${BLUE}${BRANCH_ROLLBACK}${WHITE}\n"
  printf "\n${YELLOW} >> Para verificar o status do PM2, execute:${WHITE}\n"
  printf "   ${BLUE}sudo su - deploy -c 'pm2 status'${WHITE}\n"
  printf "\n${YELLOW} >> Para ver os logs do PM2, execute:${WHITE}\n"
  printf "   ${BLUE}sudo su - deploy -c 'pm2 logs'${WHITE}\n"
  printf "\n"
}

# Função para retornar à versão principal
retornar_versao_principal() {
  banner
  
  # Carregar variáveis
  carregar_variaveis
  
  # Verificar se a variável empresa está definida
  if [ -z "${empresa}" ]; then
    printf "${RED} >> ERRO: Variável 'empresa' não está definida!\n${WHITE}"
    printf "${YELLOW} >> Por favor, informe o nome da empresa:${WHITE}\n"
    read -p "> " empresa
    if [ -z "${empresa}" ]; then
      printf "${RED} >> ERRO: Nome da empresa não pode ser vazio. Abortando.\n${WHITE}"
      exit 1
    fi
  fi
  
  # Definir diretório da aplicação
  APP_DIR="/home/deploy/${empresa}"
  
  # Verificar se o diretório existe
  if [ ! -d "$APP_DIR" ]; then
    printf "${RED} >> ERRO: Diretório da aplicação não existe: ${APP_DIR}\n${WHITE}"
    exit 1
  fi
  
  printf "${WHITE} >> Diretório da aplicação: ${BLUE}${APP_DIR}${WHITE}\n"
  echo
  
  printf "\n${YELLOW} ⚠️  ATENÇÃO: Esta operação irá:${WHITE}\n"
  printf "${YELLOW}    - Fazer checkout para a branch MULTI100-OFICIAL-u21${WHITE}\n"
  printf "${YELLOW}    - Atualizar código com git pull${WHITE}\n"
  printf "${YELLOW}    - Reinstalar dependências e rebuild${WHITE}\n"
  printf "${YELLOW}    - Reiniciar aplicações no PM2${WHITE}\n"
  echo
  printf "${RED} >> Deseja continuar? (s/N):${WHITE}\n"
  read -p "> " CONFIRMA
  
  if [ "$CONFIRMA" != "s" ] && [ "$CONFIRMA" != "S" ]; then
    printf "${YELLOW} >> Operação cancelada pelo usuário.${WHITE}\n"
    exit 0
  fi
  
  echo
  printf "${WHITE} >> Iniciando retorno para versão principal...\n"
  echo
  
  # 1) Entrar na pasta do projeto e corrigir permissões
  printf "${WHITE} [1/9] Entrando na pasta do projeto e corrigindo permissões...\n"
  cd "$APP_DIR" || trata_erro "cd para pasta do projeto"
  
  # Corrigir permissões do diretório .git e todo o repositório
  printf "${WHITE} >> Corrigindo permissões do repositório...\n"
  chown -R deploy:deploy "$APP_DIR" 2>/dev/null || true
  
  # Garantir permissões específicas para .git e .git/objects
  if [ -d "$APP_DIR/.git" ]; then
    chmod -R 755 "$APP_DIR/.git" 2>/dev/null || true
    chown -R deploy:deploy "$APP_DIR/.git" 2>/dev/null || true
    
    # Garantir permissões de escrita no diretório objects
    if [ -d "$APP_DIR/.git/objects" ]; then
      chmod -R 775 "$APP_DIR/.git/objects" 2>/dev/null || true
      chown -R deploy:deploy "$APP_DIR/.git/objects" 2>/dev/null || true
    fi
  fi
  
  chmod -R 775 "$APP_DIR" 2>/dev/null || true
  
  printf "${GREEN} ✓ Diretório atual: $(pwd)\n${WHITE}"
  printf "${GREEN} ✓ Permissões corrigidas\n${WHITE}"
  echo
  
  # 2) Fazer checkout para branch oficial
  printf "${WHITE} [2/9] Fazendo checkout para branch MULTI100-OFICIAL-u21...\n"
  sudo su - deploy <<CHECKOUT
cd "$APP_DIR"

# Garantir permissões corretas
chmod -R u+w .git 2>/dev/null || true
chown -R deploy:deploy .git 2>/dev/null || true

git fetch origin
git checkout MULTI100-OFICIAL-u21
git reset --hard origin/MULTI100-OFICIAL-u21
CHECKOUT
  if [ $? -ne 0 ]; then
    trata_erro "git checkout"
  fi
  printf "${GREEN} ✓ Checkout para branch oficial concluído\n${WHITE}"
  echo
  
  # 3) Atualizar código com git pull
  printf "${WHITE} [3/9] Atualizando código com git pull...\n"
  sudo su - deploy <<PULL
cd "$APP_DIR"
git pull
PULL
  if [ $? -ne 0 ]; then
    printf "${YELLOW} >> Aviso: git pull pode ter tido problemas. Continuando...\n${WHITE}"
  else
    printf "${GREEN} ✓ Código atualizado\n${WHITE}"
  fi
  echo
  
  # 4) Parar aplicações PM2
  printf "${WHITE} [4/9] Parando instâncias PM2...\n"
  sudo su - deploy <<STOPPM2
# Configura PATH para Node.js e PM2
if [ -d /usr/local/n/versions/node/20.19.4/bin ]; then
  export PATH=/usr/local/n/versions/node/20.19.4/bin:/usr/bin:/usr/local/bin:\$PATH
else
  export PATH=/usr/bin:/usr/local/bin:\$PATH
fi
pm2 stop all || true
STOPPM2
  printf "${GREEN} ✓ PM2 parado\n${WHITE}"
  echo
  
  # 5) Reinstalar dependências do Backend
  printf "${WHITE} [5/9] Reinstalando dependências do Backend...\n"
  BACKEND_DIR="${APP_DIR}/backend"
  if [ ! -d "$BACKEND_DIR" ]; then
    printf "${YELLOW} >> Aviso: Diretório backend não encontrado. Pulando...\n${WHITE}"
  else
    sudo su - deploy <<BACKEND
# Configura PATH para Node.js
if [ -d /usr/local/n/versions/node/20.19.4/bin ]; then
  export PATH=/usr/local/n/versions/node/20.19.4/bin:/usr/bin:/usr/local/bin:\$PATH
else
  export PATH=/usr/bin:/usr/local/bin:\$PATH
fi

BACKEND_DIR="$BACKEND_DIR"

if [ ! -d "\$BACKEND_DIR" ]; then
  echo "ERRO: Diretório do backend não existe: \$BACKEND_DIR"
  exit 1
fi

cd "\$BACKEND_DIR"

if [ ! -f "package.json" ]; then
  echo "ERRO: package.json não encontrado em \$BACKEND_DIR"
  exit 1
fi

npm prune --force > /dev/null 2>&1
export PUPPETEER_SKIP_DOWNLOAD=true
rm -rf node_modules 2>/dev/null || true
rm -f package-lock.json 2>/dev/null || true
rm -rf dist 2>/dev/null || true
npm install --force
npm install puppeteer-core --force
npm i glob
npm run build
sleep 2
BACKEND
    if [ $? -ne 0 ]; then
      printf "${RED} >> ERRO ao instalar dependências do backend\n${WHITE}"
      trata_erro "npm install backend"
    fi
    printf "${GREEN} ✓ Dependências do Backend instaladas e buildado\n${WHITE}"
    
    # Executar migração do banco de dados
    printf "${WHITE} >> Executando migração do banco de dados...\n"
    sudo su - deploy <<MIGRATE
# Configura PATH para Node.js
if [ -d /usr/local/n/versions/node/20.19.4/bin ]; then
  export PATH=/usr/local/n/versions/node/20.19.4/bin:/usr/bin:/usr/local/bin:\$PATH
else
  export PATH=/usr/bin:/usr/local/bin:\$PATH
fi

cd "$BACKEND_DIR"
npx sequelize db:migrate
sleep 2
MIGRATE
    if [ $? -ne 0 ]; then
      printf "${YELLOW} >> Aviso: Migração do banco pode ter falhado. Continuando...\n${WHITE}"
    else
      printf "${GREEN} ✓ Migração do banco concluída\n${WHITE}"
    fi
  fi
  echo
  
  # 6) Reinstalar dependências e build do Frontend
  printf "${WHITE} [6/9] Reinstalando dependências e build do Frontend...\n"
  FRONTEND_DIR="${APP_DIR}/frontend"
  
  # Carregar porta do frontend do .env se existir
  source "$FRONTEND_DIR/.env" 2>/dev/null || true
  frontend_port=${SERVER_PORT:-3000}
  
  if [ ! -d "$FRONTEND_DIR" ]; then
    printf "${YELLOW} >> Aviso: Diretório frontend não encontrado. Pulando...\n${WHITE}"
  else
    sudo su - deploy <<FRONTEND
# Configura PATH para Node.js
if [ -d /usr/local/n/versions/node/20.19.4/bin ]; then
  export PATH=/usr/local/n/versions/node/20.19.4/bin:/usr/bin:/usr/local/bin:\$PATH
else
  export PATH=/usr/bin:/usr/local/bin:\$PATH
fi

FRONTEND_DIR="$FRONTEND_DIR"

if [ ! -d "\$FRONTEND_DIR" ]; then
  echo "ERRO: Diretório do frontend não existe: \$FRONTEND_DIR"
  exit 1
fi

cd "\$FRONTEND_DIR"

if [ ! -f "package.json" ]; then
  echo "ERRO: package.json não encontrado em \$FRONTEND_DIR"
  exit 1
fi

npm prune --force > /dev/null 2>&1
rm -rf node_modules 2>/dev/null || true
rm -f package-lock.json 2>/dev/null || true
npm install --force

if [ -f "server.js" ]; then
  sed -i 's/3000/'"$frontend_port"'/g' server.js
fi

NODE_OPTIONS="--max-old-space-size=4096 --openssl-legacy-provider" npm run build
sleep 2
FRONTEND
    if [ $? -ne 0 ]; then
      printf "${RED} >> ERRO ao instalar dependências ou build do frontend\n${WHITE}"
      trata_erro "npm install/build frontend"
    fi
    printf "${GREEN} ✓ Frontend instalado e buildado\n${WHITE}"
  fi
  echo
  
  # 7) Reiniciar PM2
  printf "${WHITE} [7/9] Reiniciando aplicações no PM2...\n"
  sudo su - deploy <<RESTARTPM2
# Configura PATH para Node.js e PM2
if [ -d /usr/local/n/versions/node/20.19.4/bin ]; then
  export PATH=/usr/local/n/versions/node/20.19.4/bin:/usr/bin:/usr/local/bin:\$PATH
else
  export PATH=/usr/bin:/usr/local/bin:\$PATH
fi
pm2 flush
pm2 reset all
pm2 restart all
pm2 save
pm2 startup
RESTARTPM2
  if [ $? -ne 0 ]; then
    printf "${YELLOW} >> Aviso: Algum problema ao reiniciar PM2. Verifique manualmente.\n${WHITE}"
  else
    printf "${GREEN} ✓ PM2 reiniciado e salvo\n${WHITE}"
  fi
  echo
  
  # 8) Reiniciar serviços (Nginx/Traefik)
  printf "${WHITE} [8/9] Reiniciando serviços de proxy...\n"
  sudo su - root <<EOF
    if systemctl is-active --quiet nginx; then
      sudo systemctl restart nginx
      echo "Nginx reiniciado"
    elif systemctl is-active --quiet traefik; then
      sudo systemctl restart traefik.service
      echo "Traefik reiniciado"
    else
      echo "Nenhum serviço de proxy (Nginx ou Traefik) está em execução."
    fi
EOF
  printf "${GREEN} ✓ Serviços reiniciados\n${WHITE}"
  echo
  
  # Resumo final
  printf "\n${GREEN}═══════════════════════════════════════════════════════════\n"
  printf "  ✓ RETORNO PARA VERSÃO PRINCIPAL CONCLUÍDO!\n"
  printf "═══════════════════════════════════════════════════════════\n${WHITE}"
  printf "\n${WHITE} >> Resumo da operação:${WHITE}\n"
  printf "   - Empresa: ${BLUE}${empresa}${WHITE}\n"
  printf "   - Diretório: ${BLUE}${APP_DIR}${WHITE}\n"
  printf "   - Branch: ${BLUE}MULTI100-OFICIAL-u21${WHITE}\n"
  printf "\n${YELLOW} >> Para verificar o status do PM2, execute:${WHITE}\n"
  printf "   ${BLUE}sudo su - deploy -c 'pm2 status'${WHITE}\n"
  printf "\n${YELLOW} >> Para ver os logs do PM2, execute:${WHITE}\n"
  printf "   ${BLUE}sudo su - deploy -c 'pm2 logs'${WHITE}\n"
  printf "\n"
}

# Menu principal
menu_principal() {
  while true; do
    banner
    printf "${WHITE} Selecione a opção desejada: \n"
    echo
    printf "   [${BLUE}1${WHITE}] Fazer Rollback para Versão Específica\n"
    printf "   [${BLUE}2${WHITE}] Retornar para Versão Principal (MULTI100-OFICIAL-u21)\n"
    printf "   [${BLUE}0${WHITE}] Sair\n"
    echo
    read -p "> " opcao_menu
    
    case "${opcao_menu}" in
    1)
      rollback_versao
      ;;
    2)
      retornar_versao_principal
      ;;
    0)
      printf "${GREEN} >> Saindo...${WHITE}\n"
      exit 0
      ;;
    *)
      printf "${RED}Opção inválida. Tente novamente.${WHITE}\n"
      sleep 2
      ;;
    esac
    
    # Após executar uma opção, perguntar se deseja continuar
    echo
    printf "${YELLOW} >> Deseja executar outra operação? (s/N):${WHITE}\n"
    read -p "> " continuar
    if [ "$continuar" != "s" ] && [ "$continuar" != "S" ]; then
      printf "${GREEN} >> Saindo...${WHITE}\n"
      exit 0
    fi
  done
}

# Executar menu principal
menu_principal

