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

# Função banner
banner() {
  printf " ${BLUE}"
  printf "\n\n"
  printf "██╗███╗   ██╗███████╗████████╗ █████╗ ██╗     ██╗     ███████╗██╗    ██╗██╗\n"
  printf "██║████╗  ██║██╔════╝╚══██╔══╝██╔══██╗██║     ██║     ██╔════╝██║    ██║██║\n"
  printf "██║██╔██╗ ██║███████    ██║   ███████║██║     ██║     ███████╗██║ █╗ ██║██║\n"
  printf "██║██║╚██╗██║╚════██║   ██║   ██╔══██║██║     ██║     ╚════██║██║███╗██║██║\n"
  printf "██║██║ ╚████║███████║   ██║   ██║  ██║███████╗███████╗███████║╚███╔███╔╝██║\n"
  printf "╚═╝╚═╝  ╚═══╝╚══════╝   ╚═╝   ╚═╝  ╚═╝╚══════╝╚══════╝╚══════╝ ╚══╝╚══╝ ╚═╝\n"
  printf "${WHITE}\n"
}

# Função para detectar e listar todas as instâncias instaladas
detectar_instancias_instaladas() {
  local instancias=()
  local nomes_empresas=()
  local temp_empresa=""
  local temp_subdominio_backend=""
  local temp_subdominio_frontend=""
  
  # Verificar instalação base (arquivo VARIAVEIS_INSTALACAO)
  INSTALADOR_DIR="/root/instalador_single_oficial"
  ARQUIVO_VARIAVEIS="VARIAVEIS_INSTALACAO"
  if [ -f "${INSTALADOR_DIR}/${ARQUIVO_VARIAVEIS}" ]; then
    # Salvar variáveis atuais
    local empresa_original="${empresa:-}"
    local subdominio_backend_original="${subdominio_backend:-}"
    local subdominio_frontend_original="${subdominio_frontend:-}"
    
    # Carregar variáveis do arquivo
    source "${INSTALADOR_DIR}/${ARQUIVO_VARIAVEIS}" 2>/dev/null
    temp_empresa="${empresa:-}"
    
    if [ -n "${temp_empresa}" ] && [ -d "/home/deploy/${temp_empresa}" ] && [ -d "/home/deploy/${temp_empresa}/backend" ]; then
      instancias+=("${INSTALADOR_DIR}/${ARQUIVO_VARIAVEIS}")
      nomes_empresas+=("${temp_empresa}")
    fi
    
    # Restaurar variáveis originais
    empresa="${empresa_original}"
    subdominio_backend="${subdominio_backend_original}"
    subdominio_frontend="${subdominio_frontend_original}"
  fi
  
  # Verificar instâncias adicionais (arquivos VARIAVEIS_INSTALACAO_INSTANCIA_*)
  if [ -d "${INSTALADOR_DIR}" ]; then
    for arquivo_instancia in "${INSTALADOR_DIR}"/VARIAVEIS_INSTALACAO_INSTANCIA_*; do
      if [ -f "$arquivo_instancia" ]; then
        # Salvar variáveis atuais
        local empresa_original="${empresa:-}"
        local subdominio_backend_original="${subdominio_backend:-}"
        local subdominio_frontend_original="${subdominio_frontend:-}"
        
        # Carregar variáveis do arquivo
        source "$arquivo_instancia" 2>/dev/null
        temp_empresa="${empresa:-}"
        
        if [ -n "${temp_empresa}" ] && [ -d "/home/deploy/${temp_empresa}" ] && [ -d "/home/deploy/${temp_empresa}/backend" ]; then
          instancias+=("$arquivo_instancia")
          nomes_empresas+=("${temp_empresa}")
        fi
        
        # Restaurar variáveis originais
        empresa="${empresa_original}"
        subdominio_backend="${subdominio_backend_original}"
        subdominio_frontend="${subdominio_frontend_original}"
      fi
    done
  fi
  
  # Retornar arrays (usando variáveis globais)
  declare -g INSTANCIAS_DETECTADAS=("${instancias[@]}")
  declare -g NOMES_EMPRESAS_DETECTADAS=("${nomes_empresas[@]}")
}

# Função para selecionar qual instância atualizar
selecionar_instancia_atualizar() {
  banner
  printf "${WHITE} >> Detectando instâncias instaladas...\n"
  echo
  
  detectar_instancias_instaladas
  
  local total_instancias=${#INSTANCIAS_DETECTADAS[@]}
  
  if [ $total_instancias -eq 0 ]; then
    printf "${RED} >> ERRO: Nenhuma instância instalada detectada!${WHITE}\n"
    printf "${YELLOW} >> Não é possível atualizar. Verifique se há instâncias instaladas.${WHITE}\n"
    sleep 3
    return 1
  elif [ $total_instancias -eq 1 ]; then
    # Apenas uma instância, usar diretamente
    printf "${GREEN} >> Uma instância detectada: ${BLUE}${NOMES_EMPRESAS_DETECTADAS[0]}${WHITE}\n"
    echo
    sleep 2
    
    # Carregar variáveis da instância única
    source "${INSTANCIAS_DETECTADAS[0]}"
    # Salvar arquivo usado em variável global para uso posterior
    declare -g ARQUIVO_VARIAVEIS_USADO="${INSTANCIAS_DETECTADAS[0]}"
    return 0
  else
    # Múltiplas instâncias, perguntar qual atualizar
    printf "${WHITE}═══════════════════════════════════════════════════════════\n"
    printf "  INSTÂNCIAS INSTALADAS DETECTADAS\n"
    printf "═══════════════════════════════════════════════════════════\n${WHITE}"
    echo
    
    local index=1
    for i in "${!NOMES_EMPRESAS_DETECTADAS[@]}"; do
      local empresa_nome="${NOMES_EMPRESAS_DETECTADAS[$i]}"
      local arquivo_instancia="${INSTANCIAS_DETECTADAS[$i]}"
      
      # Salvar variáveis atuais antes de carregar
      local empresa_original="${empresa:-}"
      local subdominio_backend_original="${subdominio_backend:-}"
      local subdominio_frontend_original="${subdominio_frontend:-}"
      
      # Tentar carregar informações adicionais da instância
      source "$arquivo_instancia" 2>/dev/null
      
      local temp_subdominio_backend="${subdominio_backend:-}"
      local temp_subdominio_frontend="${subdominio_frontend:-}"
      
      # Restaurar variáveis originais
      empresa="${empresa_original}"
      subdominio_backend="${subdominio_backend_original}"
      subdominio_frontend="${subdominio_frontend_original}"
      
      printf "${BLUE}  [$index]${WHITE} Empresa: ${GREEN}${empresa_nome}${WHITE}\n"
      if [ -n "${temp_subdominio_backend}" ]; then
        printf "      Backend: ${YELLOW}${temp_subdominio_backend}${WHITE}\n"
      fi
      if [ -n "${temp_subdominio_frontend}" ]; then
        printf "      Frontend: ${YELLOW}${temp_subdominio_frontend}${WHITE}\n"
      fi
      echo
      ((index++))
    done
    
    printf "${WHITE}═══════════════════════════════════════════════════════════\n${WHITE}"
    echo
    printf "${YELLOW} >> Qual instância deseja atualizar? (1-${total_instancias}):${WHITE}\n"
    read -p "> " escolha_instancia
    
    # Validar entrada
    if ! [[ "$escolha_instancia" =~ ^[0-9]+$ ]]; then
      printf "${RED} >> ERRO: Entrada inválida. Digite um número.${WHITE}\n"
      sleep 2
      return 1
    fi
    
    if [ "$escolha_instancia" -lt 1 ] || [ "$escolha_instancia" -gt $total_instancias ]; then
      printf "${RED} >> ERRO: Opção inválida. Escolha um número entre 1 e ${total_instancias}.${WHITE}\n"
      sleep 2
      return 1
    fi
    
    # Carregar variáveis da instância selecionada
    local indice_selecionado=$((escolha_instancia - 1))
    source "${INSTANCIAS_DETECTADAS[$indice_selecionado]}"
    # Salvar arquivo usado em variável global para uso posterior
    declare -g ARQUIVO_VARIAVEIS_USADO="${INSTANCIAS_DETECTADAS[$indice_selecionado]}"
    
    printf "${GREEN} >> Instância selecionada: ${BLUE}${empresa}${WHITE}\n"
    echo
    sleep 2
    return 0
  fi
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
    printf "${WHITE}   A migração para PRO já foi realizada anteriormente.${WHITE}\n"
    echo
    printf "${YELLOW}   ⚠️  Não é necessário executar este atualizador novamente.${WHITE}\n"
    echo
    printf "${GREEN}   📌 Para atualizar sua instalação, execute a ${WHITE}atualização normal pelo instalador${GREEN}.${WHITE}\n"
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
    
    INSTALADOR_DIR="/root/instalador_single_oficial"
    
    # VALIDAR O TOKEN ANTES DE FAZER QUALQUER ALTERAÇÃO
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
      printf "${RED}══════════════════════════════════════════════════════════════════${WHITE}\n"
      printf "${RED}❌ ERRO: Token de autorização inválido!${WHITE}\n"
      echo
      printf "${RED}   O teste de git clone falhou. O token informado não tem acesso ao repositório multiflow-pro.${WHITE}\n"
      echo
      printf "${YELLOW}   ⚠️  IMPORTANTE:${WHITE}\n"
      printf "${YELLOW}   O MultiFlow PRO é um projeto fechado e requer autorização especial.${WHITE}\n"
      printf "${YELLOW}   Para solicitar acesso ou analisar a disponibilidade de migração,${WHITE}\n"
      printf "${YELLOW}   entre em contato com o administrador do projeto:${WHITE}\n"
      echo
      printf "${BLUE}   📱 WhatsApp:${WHITE}\n"
      printf "${WHITE}   • https://wa.me/5518996755165${WHITE}\n"
      printf "${WHITE}   • https://wa.me/558499418159${WHITE}\n"
      echo
      printf "${RED}   Atualização interrompida.${WHITE}\n"
      printf "${RED}══════════════════════════════════════════════════════════════════${WHITE}\n"
      echo
      exit 1
    fi
    
    # Carregar o token antigo do arquivo VARIAVEIS_INSTALACAO
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
        sudo rm -f /usr/bin/npx || true

        echo "=== Removendo repositórios antigos do NodeSource ==="
        sudo rm -f /etc/apt/sources.list.d/nodesource.list 2>/dev/null || true
        sudo rm -f /etc/apt/sources.list.d/nodesource*.list 2>/dev/null || true

        echo "=== Instalando Node.js temporário para ter npm ==="
        # Tenta primeiro com Node.js 22.x (LTS atual), depois 20.x
        curl -fsSL https://deb.nodesource.com/setup_22.x | sudo -E bash - 2>&1 | grep -v "does not have a Release file" || \
        curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash - 2>&1 | grep -v "does not have a Release file" || true
        
        sudo apt-get update -y 2>&1 | grep -v "does not have a Release file" | grep -v "Key is stored in legacy" || true
        sudo apt install -y nodejs

        echo "=== Instalando gerenciador 'n' ==="
        sudo npm install -g n

        echo "=== Instalando Node.js 20.19.4 ==="
        sudo n 20.19.4

        echo "=== Ajustando links globais para a versão correta ==="
        if [ -f /usr/local/n/versions/node/20.19.4/bin/node ]; then
          sudo ln -sf /usr/local/n/versions/node/20.19.4/bin/node /usr/bin/node
          sudo ln -sf /usr/local/n/versions/node/20.19.4/bin/npm /usr/bin/npm
          sudo ln -sf /usr/local/n/versions/node/20.19.4/bin/npx /usr/bin/npx 2>/dev/null || true
        fi

        # Atualiza o PATH no perfil do sistema
        if ! grep -q "/usr/local/n/versions/node" /etc/profile 2>/dev/null; then
          echo 'export PATH=/usr/local/n/versions/node/20.19.4/bin:/usr/bin:$PATH' | sudo tee -a /etc/profile > /dev/null
        fi

        echo "=== Versões instaladas ==="
        export PATH=/usr/local/n/versions/node/20.19.4/bin:/usr/bin:$PATH
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
      echo "=== Removendo repositórios antigos do NodeSource ==="
      sudo rm -f /etc/apt/sources.list.d/nodesource.list 2>/dev/null || true
      sudo rm -f /etc/apt/sources.list.d/nodesource*.list 2>/dev/null || true

      echo "=== Instalando Node.js temporário para ter npm ==="
      # Tenta primeiro com Node.js 22.x (LTS atual), depois 20.x
      curl -fsSL https://deb.nodesource.com/setup_22.x | sudo -E bash - 2>&1 | grep -v "does not have a Release file" || \
      curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash - 2>&1 | grep -v "does not have a Release file" || true
      
      sudo apt-get update -y 2>&1 | grep -v "does not have a Release file" | grep -v "Key is stored in legacy" || true
      sudo apt install -y nodejs

      echo "=== Instalando gerenciador 'n' ==="
      sudo npm install -g n

      echo "=== Instalando Node.js 20.19.4 ==="
      sudo n 20.19.4

      echo "=== Ajustando links globais para a versão correta ==="
      if [ -f /usr/local/n/versions/node/20.19.4/bin/node ]; then
        sudo ln -sf /usr/local/n/versions/node/20.19.4/bin/node /usr/bin/node
        sudo ln -sf /usr/local/n/versions/node/20.19.4/bin/npm /usr/bin/npm
        sudo ln -sf /usr/local/n/versions/node/20.19.4/bin/npx /usr/bin/npx 2>/dev/null || true
      fi

      # Atualiza o PATH no perfil do sistema
      if ! grep -q "/usr/local/n/versions/node" /etc/profile 2>/dev/null; then
        echo 'export PATH=/usr/local/n/versions/node/20.19.4/bin:/usr/bin:$PATH' | sudo tee -a /etc/profile > /dev/null
      fi

      echo "=== Versões instaladas ==="
      export PATH=/usr/local/n/versions/node/20.19.4/bin:/usr/bin:$PATH
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
  
  # Verifica se a variável empresa está definida
  if [ -z "${empresa}" ]; then
    printf "${RED} >> ERRO: Variável 'empresa' não está definida!\n${WHITE}"
    exit 1
  fi
  
  # Verifica se o arquivo .env existe
  ENV_FILE="/home/deploy/${empresa}/backend/.env"
  if [ ! -f "$ENV_FILE" ]; then
    printf "${YELLOW} >> AVISO: Arquivo .env não encontrado em $ENV_FILE. Pulando backup.\n${WHITE}"
    return 0
  fi
  
  source "$ENV_FILE"
  {
    printf "${WHITE} >> Fazendo backup do banco de dados da empresa ${empresa}...\n"
    db_password=$(grep "DB_PASS=" "$ENV_FILE" | cut -d '=' -f2)
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
  
  # Verifica se a variável empresa está definida
  if [ -z "${empresa}" ]; then
    printf "${RED} >> ERRO: Variável 'empresa' não está definida!\n${WHITE}"
    exit 1
  fi
  
  # Verifica se o arquivo .env existe
  ENV_FILE="/home/deploy/${empresa}/backend/.env"
  if [ ! -f "$ENV_FILE" ]; then
    printf "${YELLOW} >> AVISO: Arquivo .env não encontrado em $ENV_FILE. Pulando otimização do banco.\n${WHITE}"
    return 0
  fi
  
  [ -f "${INSTALADOR_DIR}/${ARQUIVO_VARIAVEIS}" ] && source "${INSTALADOR_DIR}/${ARQUIVO_VARIAVEIS}" 2>/dev/null
  if [ "${ALTA_PERFORMANCE}" = "1" ]; then
    db_host_opt="127.0.0.1"
    db_port_opt="7532"
  else
    db_host_opt="localhost"
    db_port_opt="5432"
  fi
  
  {
    db_password=$(grep "DB_PASS=" "$ENV_FILE" | cut -d '=' -f2)
    if [ -z "$db_password" ]; then
      printf "${YELLOW} >> AVISO: Senha do banco não encontrada. Pulando otimização.\n${WHITE}"
      return 0
    fi
    sudo su - root <<EOF
    PGPASSWORD="$db_password" vacuumdb -U "${empresa}" -h ${db_host_opt} -p ${db_port_opt} -d "${empresa}" --full --analyze
    PGPASSWORD="$db_password" psql -U ${empresa} -h ${db_host_opt} -p ${db_port_opt} -d ${empresa} -c "REINDEX DATABASE ${empresa};"
    PGPASSWORD="$db_password" psql -U ${empresa} -h ${db_host_opt} -p ${db_port_opt} -d ${empresa} -c "ANALYZE;"
EOF
    sleep 2
  } || trata_erro "otimiza_banco_atualizar"
}

# Verificar e adicionar MAX_BUFFER_SIZE_MB no .env do backend
verificar_e_adicionar_max_buffer() {
  dummy_carregar_variaveis
  
  # Verifica se a variável empresa está definida
  if [ -z "${empresa}" ]; then
    printf "${RED} >> ERRO: Variável 'empresa' não está definida!\n${WHITE}"
    return 0
  fi
  
  ENV_FILE="/home/deploy/${empresa}/backend/.env"
  
  if [ ! -f "$ENV_FILE" ]; then
    printf "${YELLOW} >> AVISO: Arquivo .env não encontrado em $ENV_FILE. Pulando verificação de MAX_BUFFER_SIZE_MB.\n${WHITE}"
    return 0
  fi
  
  if ! grep -q "^MAX_BUFFER_SIZE_MB=" "$ENV_FILE"; then
    printf "${WHITE} >> Adicionando MAX_BUFFER_SIZE_MB=200 no .env do backend...\n"
    echo "" >> "$ENV_FILE"
    echo "# Buffer Size Configuration" >> "$ENV_FILE"
    echo "MAX_BUFFER_SIZE_MB=200" >> "$ENV_FILE"
    printf "${GREEN} >> Variável MAX_BUFFER_SIZE_MB adicionada com sucesso!${WHITE}\n"
  else
    printf "${GREEN} >> Variável MAX_BUFFER_SIZE_MB já existe no .env do backend.${WHITE}\n"
  fi
}

baixa_codigo_atualizar() {
  # Verifica se a variável empresa está definida
  if [ -z "${empresa}" ]; then
    printf "${RED} >> ERRO: Variável 'empresa' não está definida!\n${WHITE}"
    dummy_carregar_variaveis
    if [ -z "${empresa}" ]; then
      printf "${RED} >> ERRO: Não foi possível carregar a variável 'empresa'. Abortando.\n${WHITE}"
      exit 1
    fi
  fi
  
  # Verifica se o diretório existe
  if [ ! -d "/home/deploy/${empresa}" ]; then
    printf "${RED} >> ERRO: Diretório /home/deploy/${empresa} não existe!\n${WHITE}"
    exit 1
  fi
  
  printf "${WHITE} >> Recuperando Permissões da empresa ${empresa}... \n"
  sleep 2
  chown deploy -R /home/deploy/${empresa}
  chmod 775 -R /home/deploy/${empresa}

  sleep 2

  printf "${WHITE} >> Parando Instancias da empresa ${empresa}... \n"
  sleep 2
  sudo su - deploy <<STOPPM2
  # Configura PATH para Node.js e PM2
  if [ -d /usr/local/n/versions/node/20.19.4/bin ]; then
    export PATH=/usr/local/n/versions/node/20.19.4/bin:/usr/bin:/usr/local/bin:\$PATH
  else
    export PATH=/usr/bin:/usr/local/bin:\$PATH
  fi
  # Parar apenas processos PM2 relacionados à empresa específica
  # Detecta todos os processos que começam com o nome da empresa (independente do sufixo)
  # Não afeta processos de outras instâncias
  pm2 list | grep "${empresa}-" | awk '{print \$2}' | while read process_name; do
    if [ -n "\$process_name" ] && [ "\$process_name" != "name" ]; then
      pm2 stop "\$process_name" 2>/dev/null || true
    fi
  done
STOPPM2

  sleep 2

  otimiza_banco_atualizar

  verificar_e_adicionar_max_buffer

  printf "${WHITE} >> Atualizando a Aplicação da Empresa ${empresa}... \n"
  sleep 2

  # Verifica se a variável empresa está definida
  if [ -z "${empresa}" ]; then
    printf "${RED} >> ERRO: Variável 'empresa' não está definida!\n${WHITE}"
    dummy_carregar_variaveis
    if [ -z "${empresa}" ]; then
      printf "${RED} >> ERRO: Não foi possível carregar a variável 'empresa'. Abortando.\n${WHITE}"
      exit 1
    fi
  fi

  # Verifica se o diretório existe
  if [ ! -d "/home/deploy/${empresa}" ]; then
    printf "${RED} >> ERRO: Diretório /home/deploy/${empresa} não existe!\n${WHITE}"
    exit 1
  fi

  source /home/deploy/${empresa}/frontend/.env 2>/dev/null || true
  frontend_port=${SERVER_PORT:-3000}
  sudo su - deploy <<UPDATEAPP
  # Configura PATH para Node.js e PM2
  if [ -d /usr/local/n/versions/node/20.19.4/bin ]; then
    export PATH=/usr/local/n/versions/node/20.19.4/bin:/usr/bin:/usr/local/bin:\$PATH
  else
    export PATH=/usr/bin:/usr/local/bin:\$PATH
  fi
  
  APP_DIR="/home/deploy/${empresa}"
  BACKEND_DIR="\${APP_DIR}/backend"
  FRONTEND_DIR="\${APP_DIR}/frontend"
  
  # Verifica se os diretórios existem
  if [ ! -d "\$APP_DIR" ]; then
    echo "ERRO: Diretório da aplicação não existe: \$APP_DIR"
    exit 1
  fi
  
  printf "${WHITE} >> Atualizando Backend...\n"
  echo
  cd "\$APP_DIR"

  # ==== PASTA ESTÁTICA DE PERSONALIZAÇÕES ====
  CUSTOM_DIR="/home/deploy/personalizacoes/${empresa}"

  # Criar pasta de personalizações se não existir
  if [ ! -d "\$CUSTOM_DIR" ]; then
    printf "${YELLOW} >> Criando pasta de personalizações: \$CUSTOM_DIR${WHITE}\n"
    mkdir -p "\$CUSTOM_DIR/assets"
    mkdir -p "\$CUSTOM_DIR/public"

    # Copiar arquivos atuais para a pasta de personalizações (primeira vez)
    if [ -d "\$FRONTEND_DIR/src/assets" ]; then
      cp -rf "\$FRONTEND_DIR/src/assets/"* "\$CUSTOM_DIR/assets/" 2>/dev/null || true
      echo "  - Assets salvos: \$(ls \$CUSTOM_DIR/assets/ 2>/dev/null | wc -l) arquivos"
    fi
    if [ -d "\$FRONTEND_DIR/public" ]; then
      cp -rf "\$FRONTEND_DIR/public/"* "\$CUSTOM_DIR/public/" 2>/dev/null || true
      echo "  - Public salvos: \$(ls \$CUSTOM_DIR/public/ 2>/dev/null | wc -l) arquivos"
    fi
    printf "${GREEN} >> Pasta de personalizações criada com sucesso!${WHITE}\n"
    printf "${YELLOW} >> DICA: Edite os arquivos em \$CUSTOM_DIR para personalizar logos/favicon${WHITE}\n"
  else
    printf "${GREEN} >> Pasta de personalizações encontrada: \$CUSTOM_DIR${WHITE}\n"
  fi
  # ==== FIM PASTA ESTÁTICA ====

  git fetch origin
  git checkout MULTI100-OFICIAL-u21
  git reset --hard origin/MULTI100-OFICIAL-u21
  
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
  printf "${WHITE} >> Atualizando Banco da empresa ${empresa}...\n"
  echo
  sleep 2
  npx sequelize db:migrate
  sleep 2
  printf "${WHITE} >> Atualizando Frontend da ${empresa}...\n"
  echo
  sleep 2
  
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

  # ==== RESTORE DE PERSONALIZAÇÕES (da pasta estática) ====
  if [ -d "\$CUSTOM_DIR" ]; then
    printf "${WHITE} >> Aplicando personalizações de \$CUSTOM_DIR...\n"

    # Restaurar assets
    if [ -d "\$CUSTOM_DIR/assets" ] && [ "\$(ls -A \$CUSTOM_DIR/assets 2>/dev/null)" ]; then
      cp -rf "\$CUSTOM_DIR/assets/"* "\$FRONTEND_DIR/src/assets/" 2>/dev/null || true
      echo "  - Assets aplicados: \$(ls \$CUSTOM_DIR/assets/ 2>/dev/null | wc -l) arquivos"
    fi

    # Restaurar public
    if [ -d "\$CUSTOM_DIR/public" ] && [ "\$(ls -A \$CUSTOM_DIR/public 2>/dev/null)" ]; then
      cp -rf "\$CUSTOM_DIR/public/"* "\$FRONTEND_DIR/public/" 2>/dev/null || true
      echo "  - Public aplicados: \$(ls \$CUSTOM_DIR/public/ 2>/dev/null | wc -l) arquivos"
    fi

    printf "${GREEN} >> Personalizações aplicadas com sucesso!${WHITE}\n"
  fi
  # ==== FIM RESTORE ====

  NODE_OPTIONS="--max-old-space-size=4096 --openssl-legacy-provider" npm run build
  sleep 2
  # Reiniciar apenas processos PM2 relacionados à empresa específica
  # Detecta todos os processos que começam com o nome da empresa (independente do sufixo)
  pm2 list | grep "${empresa}-" | awk '{print \$2}' | while read process_name; do
    if [ -n "\$process_name" ] && [ "\$process_name" != "name" ]; then
      pm2 restart "\$process_name" 2>/dev/null || true
    fi
  done
  pm2 save
UPDATEAPP

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

# Verificar e selecionar instância para atualizar
if ! selecionar_instancia_atualizar; then
  printf "${RED} >> Erro ao selecionar instância. Encerrando script...${WHITE}\n"
  exit 1
fi

verificar_versao_pro
atualizar_git_config
verificar_e_instalar_nodejs
backup_app_atualizar
baixa_codigo_atualizar
atualizar_token_variaveis
