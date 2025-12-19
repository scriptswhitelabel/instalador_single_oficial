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
  VERSOES["6.4.3"]="6aa224db151bd8cbbf695b07a8624c976e89db00"
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
  
  # 1) Entrar na pasta do projeto
  printf "${WHITE} [1/10] Entrando na pasta do projeto...\n"
  cd "$APP_DIR" || trata_erro "cd para pasta do projeto"
  printf "${GREEN} ✓ Diretório atual: $(pwd)\n${WHITE}"
  echo
  
  # 2) Configurar remote com token e fazer git fetch
  printf "${WHITE} [2/10] Configurando remote e executando git fetch --all --prune...\n"
  sudo su - deploy <<FETCH
cd "$APP_DIR"
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
git fetch --all --prune
FETCH
  if [ $? -ne 0 ]; then
    trata_erro "git fetch"
  fi
  printf "${GREEN} ✓ Git fetch concluído\n${WHITE}"
  echo
  
  # 3) Verificar se o commit existe
  printf "${WHITE} [3/10] Verificando se o commit existe...\n"
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
  printf "${WHITE} [4/10] Limpando alterações locais (git reset --hard)...\n"
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
  printf "${WHITE} [5/10] Limpando arquivos não rastreados (git clean -fd)...\n"
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
  printf "${WHITE} [6/10] Fazendo checkout para o commit alvo (criando branch rollback)...\n"
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
  printf "${WHITE} [7/10] Parando instâncias PM2...\n"
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
  printf "${WHITE} [8/10] Reinstalando dependências do Backend...\n"
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
cd "$BACKEND_DIR"
if [ -f "package.json" ]; then
  npm install
  if [ \$? -eq 0 ]; then
    echo "Backend: npm install concluído"
  else
    echo "ERRO: npm install falhou no backend"
    exit 1
  fi
else
  echo "Aviso: package.json não encontrado no backend"
fi
BACKEND
    if [ $? -ne 0 ]; then
      printf "${RED} >> ERRO ao instalar dependências do backend\n${WHITE}"
      trata_erro "npm install backend"
    fi
    printf "${GREEN} ✓ Dependências do Backend instaladas\n${WHITE}"
  fi
  echo
  
  # 9) Reinstalar dependências e build do Frontend
  printf "${WHITE} [9/10] Reinstalando dependências e build do Frontend...\n"
  FRONTEND_DIR="${APP_DIR}/frontend"
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
cd "$FRONTEND_DIR"
if [ -f "package.json" ]; then
  npm install
  if [ \$? -eq 0 ]; then
    npm run build
    if [ \$? -eq 0 ]; then
      echo "Frontend: npm install e build concluídos"
    else
      echo "ERRO: npm run build falhou no frontend"
      exit 1
    fi
  else
    echo "ERRO: npm install falhou no frontend"
    exit 1
  fi
else
  echo "Aviso: package.json não encontrado no frontend"
fi
FRONTEND
    if [ $? -ne 0 ]; then
      printf "${RED} >> ERRO ao instalar dependências ou build do frontend\n${WHITE}"
      trata_erro "npm install/build frontend"
    fi
    printf "${GREEN} ✓ Frontend instalado e buildado\n${WHITE}"
  fi
  echo
  
  # 10) Reiniciar PM2
  printf "${WHITE} [10/10] Reiniciando aplicações no PM2...\n"
  sudo su - deploy <<RESTARTPM2
# Configura PATH para Node.js e PM2
if [ -d /usr/local/n/versions/node/20.19.4/bin ]; then
  export PATH=/usr/local/n/versions/node/20.19.4/bin:/usr/bin:/usr/local/bin:\$PATH
else
  export PATH=/usr/bin:/usr/local/bin:\$PATH
fi
pm2 restart all
pm2 save
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

# Executar função principal
rollback_versao

