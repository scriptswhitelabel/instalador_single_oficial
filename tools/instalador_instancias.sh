#!/bin/bash

GREEN='\033[1;32m'
BLUE='\033[1;34m'
WHITE='\033[1;37m'
RED='\033[1;31m'
YELLOW='\033[1;33m'

# Variaveis Padrão
ARCH=$(uname -m)
UBUNTU_VERSION=$(lsb_release -sr)
ARQUIVO_VARIAVEIS_BASE="VARIAVEIS_INSTALACAO"
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

banner() {
  clear
  printf "${BLUE}"
  echo "╔══════════════════════════════════════════════════════════════╗"
  echo "║            INSTALADOR DE NOVAS INSTÂNCIAS                    ║"
  echo "║                                                              ║"
  echo "║                    MultiFlow System                          ║"
  echo "╚══════════════════════════════════════════════════════════════╝"
  printf "${WHITE}"
  echo
}

# Função para manipular erros e encerrar o script
trata_erro() {
  printf "${RED}Erro encontrado na etapa $1. Encerrando o script.${WHITE}\n"
  exit 1
}

# Carregar variáveis base
carregar_variaveis_base() {
  if [ -f "$ARQUIVO_VARIAVEIS_BASE" ]; then
    source "$ARQUIVO_VARIAVEIS_BASE"
  fi
}

# Validar token do GitHub
validar_token_github() {
  local token=$1
  local repo=$2
  
  if [ -z "$token" ] || [ -z "$repo" ]; then
    return 1
  fi
  
  # Preparar URL do repositório com token
  repo_limpo=$(echo "${repo}" | sed 's|https://||' | sed 's|http://||' | sed 's|\.git$||' | sed 's|/$||')
  repo_url_com_token="https://${token}@${repo_limpo}.git"
  
  # Criar diretório temporário para teste
  TEST_DIR="/tmp/test_clone_$(date +%s)"
  
  # Tentar fazer clone de teste (shallow clone para ser rápido)
  if git clone --depth 1 "${repo_url_com_token}" "${TEST_DIR}" >/dev/null 2>&1; then
    # Clone bem-sucedido, remover diretório de teste
    rm -rf "${TEST_DIR}" >/dev/null 2>&1
    return 0
  else
    # Clone falhou, token inválido
    rm -rf "${TEST_DIR}" >/dev/null 2>&1
    return 1
  fi
}

# Definir versões disponíveis para instalação (mesma do instalador_single.sh)
definir_versoes_instalacao() {
  declare -gA VERSOES_INSTALACAO
  VERSOES_INSTALACAO["6.5.2"]="6607976a25f86127bd494bba20017fe6bbd9f50a"
  VERSOES_INSTALACAO["6.5"]="ab5565df5937f6113bbbb6b2ce9c526e25e525ef"
  VERSOES_INSTALACAO["6.4.4"]="b5de35ebb4acb10694ce4e8b8d6068b31eeabef9"
  VERSOES_INSTALACAO["6.4.3"]="6aa224db151bd8cbbf695b07a8624c976e89db00"
}

# Mostrar lista de versões disponíveis para instalação (mesma do instalador_single.sh)
mostrar_lista_versoes_instalacao() {
  printf "${WHITE}═══════════════════════════════════════════════════════════\n"
  printf "  VERSÕES DISPONÍVEIS PARA INSTALAÇÃO\n"
  printf "═══════════════════════════════════════════════════════════\n${WHITE}"
  echo
  
  printf "${BLUE}  [0]${WHITE} Mais Recente${WHITE}\n"
  printf "      Instala a versão mais recente disponível no repositório\n"
  echo
  
  local index=1
  for versao in $(printf '%s\n' "${!VERSOES_INSTALACAO[@]}" | sort -V -r); do
    printf "${BLUE}  [$index]${WHITE} Versão ${GREEN}${versao}${WHITE}\n"
    printf "      Commit: ${YELLOW}${VERSOES_INSTALACAO[$versao]}${WHITE}\n"
    echo
    ((index++))
  done
  
  printf "${WHITE}═══════════════════════════════════════════════════════════\n${WHITE}"
  echo
}

# Selecionar versão para instalação (mesma do instalador_single.sh)
selecionar_versao_instalacao() {
  banner
  printf "${WHITE} >> Selecionando versão para instalação...\n"
  echo
  
  # Definir versões disponíveis
  definir_versoes_instalacao
  
  # Mostrar lista de versões
  mostrar_lista_versoes_instalacao
  
  local versoes_array=($(printf '%s\n' "${!VERSOES_INSTALACAO[@]}" | sort -V -r))
  local total_versoes=${#versoes_array[@]}
  
  if [ $total_versoes -eq 0 ]; then
    printf "${RED} >> ERRO: Nenhuma versão disponível na lista.\n${WHITE}"
    exit 1
  fi
  
  printf "${YELLOW} >> Selecione a versão desejada (0-${total_versoes}):${WHITE}\n"
  read -p "> " ESCOLHA
  
  # Validar entrada
  if ! [[ "$ESCOLHA" =~ ^[0-9]+$ ]]; then
    printf "${RED} >> ERRO: Entrada inválida. Digite um número.\n${WHITE}"
    exit 1
  fi
  
  if [ "$ESCOLHA" -lt 0 ] || [ "$ESCOLHA" -gt $total_versoes ]; then
    printf "${RED} >> ERRO: Opção inválida. Escolha um número entre 0 e ${total_versoes}.\n${WHITE}"
    exit 1
  fi
  
  # Tratar opção 0 - Mais Recente
  if [ "$ESCOLHA" -eq 0 ]; then
    declare -g versao_instalacao="Mais Recente"
    declare -g commit_instalacao=""
    printf "\n${GREEN} >> Versão selecionada: ${BLUE}Mais Recente${WHITE}\n"
    printf "${GREEN} >> Será instalada a versão mais recente disponível no repositório${WHITE}\n"
    echo
    sleep 2
  else
    # Obter versão e commit selecionados (variáveis globais)
    local index=$((ESCOLHA - 1))
    declare -g versao_instalacao="${versoes_array[$index]}"
    declare -g commit_instalacao="${VERSOES_INSTALACAO[$versao_instalacao]}"
    
    printf "\n${GREEN} >> Versão selecionada: ${BLUE}${versao_instalacao}${WHITE}\n"
    printf "${GREEN} >> Commit: ${BLUE}${commit_instalacao}${WHITE}\n"
    echo
    sleep 2
  fi
}

# Verificar conflitos com instalação base e outras instâncias
verificar_conflitos() {
  banner
  printf "${WHITE} >> Verificando conflitos com instalação base e outras instâncias...\n"
  echo
  
  carregar_variaveis_base
  
  conflitos_encontrados=0
  
  # Verificar conflito de portas com instalação base
  if [ -f "$ARQUIVO_VARIAVEIS_BASE" ]; then
    source "$ARQUIVO_VARIAVEIS_BASE"
    
    if [ "${backend_port}" = "${nova_backend_port}" ]; then
      printf "${RED}❌ CONFLITO: Porta do backend (${nova_backend_port}) já está em uso pela instalação base.${WHITE}\n"
      conflitos_encontrados=1
    fi
    
    if [ "${frontend_port}" = "${nova_frontend_port}" ]; then
      printf "${RED}❌ CONFLITO: Porta do frontend (${nova_frontend_port}) já está em uso pela instalação base.${WHITE}\n"
      conflitos_encontrados=1
    fi
    
    if [ "${redis_port:-6379}" = "${nova_redis_port}" ]; then
      printf "${RED}❌ CONFLITO: Porta do Redis (${nova_redis_port}) já está em uso pela instalação base.${WHITE}\n"
      conflitos_encontrados=1
    fi
  fi
  
  # Verificar conflito de domínios com instalação base
  if [ -f "$ARQUIVO_VARIAVEIS_BASE" ]; then
    source "$ARQUIVO_VARIAVEIS_BASE"
    
    if [ "${subdominio_backend}" = "${nova_subdominio_backend}" ]; then
      printf "${RED}❌ CONFLITO: Domínio do backend (${nova_subdominio_backend}) já está em uso pela instalação base.${WHITE}\n"
      conflitos_encontrados=1
    fi
    
    if [ "${subdominio_frontend}" = "${nova_subdominio_frontend}" ]; then
      printf "${RED}❌ CONFLITO: Domínio do frontend (${nova_subdominio_frontend}) já está em uso pela instalação base.${WHITE}\n"
      conflitos_encontrados=1
    fi
  fi
  
  # Verificar conflitos com outras instâncias
  INSTALADOR_DIR="/root/instalador_single_oficial"
  if [ -d "$INSTALADOR_DIR" ]; then
    for arquivo_instancia in "$INSTALADOR_DIR"/VARIAVEIS_INSTALACAO_INSTANCIA_*; do
      if [ -f "$arquivo_instancia" ]; then
        source "$arquivo_instancia"
        
        if [ "${backend_port}" = "${nova_backend_port}" ]; then
          printf "${RED}❌ CONFLITO: Porta do backend (${nova_backend_port}) já está em uso por outra instância.${WHITE}\n"
          conflitos_encontrados=1
        fi
        
        if [ "${frontend_port}" = "${nova_frontend_port}" ]; then
          printf "${RED}❌ CONFLITO: Porta do frontend (${nova_frontend_port}) já está em uso por outra instância.${WHITE}\n"
          conflitos_encontrados=1
        fi
        
        if [ "${redis_port:-6379}" = "${nova_redis_port}" ]; then
          printf "${RED}❌ CONFLITO: Porta do Redis (${nova_redis_port}) já está em uso por outra instância.${WHITE}\n"
          conflitos_encontrados=1
        fi
        
        if [ "${subdominio_backend}" = "${nova_subdominio_backend}" ]; then
          printf "${RED}❌ CONFLITO: Domínio do backend (${nova_subdominio_backend}) já está em uso por outra instância.${WHITE}\n"
          conflitos_encontrados=1
        fi
        
        if [ "${subdominio_frontend}" = "${nova_subdominio_frontend}" ]; then
          printf "${RED}❌ CONFLITO: Domínio do frontend (${nova_subdominio_frontend}) já está em uso por outra instância.${WHITE}\n"
          conflitos_encontrados=1
        fi
      fi
    done
  fi
  
  # Verificar se a empresa já existe
  if [ -d "/home/deploy/${nova_empresa}" ]; then
    printf "${RED}❌ CONFLITO: A empresa ${nova_empresa} já existe em /home/deploy/${nova_empresa}${WHITE}\n"
    conflitos_encontrados=1
  fi
  
  # Verificar se porta está em uso no sistema (usando mesma validação do instalador_single.sh)
  if lsof -i:${nova_backend_port} &>/dev/null; then
    printf "${RED}❌ CONFLITO: Porta ${nova_backend_port} já está em uso no sistema.${WHITE}\n"
    conflitos_encontrados=1
  fi
  
  if lsof -i:${nova_frontend_port} &>/dev/null; then
    printf "${RED}❌ CONFLITO: Porta ${nova_frontend_port} já está em uso no sistema.${WHITE}\n"
    conflitos_encontrados=1
  fi
  
  if lsof -i:${nova_redis_port} &>/dev/null; then
    printf "${RED}❌ CONFLITO: Porta ${nova_redis_port} já está em uso no sistema.${WHITE}\n"
    conflitos_encontrados=1
  fi
  
  if [ $conflitos_encontrados -eq 1 ]; then
    printf "${RED} >> Erros de conflito encontrados. Por favor, corrija os dados e tente novamente.${WHITE}\n"
    echo
    sleep 5
    return 1
  else
    printf "${GREEN}✅ Nenhum conflito encontrado. Prosseguindo...${WHITE}\n"
    echo
    sleep 2
    return 0
  fi
}

# Solicitar dados da nova instância
solicitar_dados_instancia() {
  banner
  printf "${WHITE} >> Configuração da Nova Instância\n"
  echo
  printf "${YELLOW}══════════════════════════════════════════════════════════════════${WHITE}\n"
  echo
  
  # Nome da empresa
  while true; do
    printf "${WHITE} >> Digite o nome da empresa (letras minúsculas, sem espaços):${WHITE}\n"
    read -p "> " nova_empresa
    nova_empresa=$(echo "${nova_empresa}" | tr '[:upper:]' '[:lower:]' | tr ' ' '_')
    
    if [ -z "${nova_empresa}" ]; then
      printf "${RED} >> Nome da empresa não pode estar vazio!${WHITE}\n"
      continue
    fi
    
    if [ -d "/home/deploy/${nova_empresa}" ]; then
      printf "${RED} >> A empresa ${nova_empresa} já existe! Escolha outro nome.${WHITE}\n"
      continue
    fi
    
    break
  done
  echo
  
  # Domínio Backend
  banner
  printf "${WHITE} >> Insira a URL do Backend para a nova instância:${WHITE}\n"
  read -p "> " nova_subdominio_backend
  echo
  
  # Domínio Frontend
  banner
  printf "${WHITE} >> Insira a URL do Frontend para a nova instância:${WHITE}\n"
  read -p "> " nova_subdominio_frontend
  echo
  
  # Porta Backend
  banner
  while true; do
    printf "${WHITE} >> Qual porta deseja para o Backend? (padrão: 8081):${WHITE}\n"
    read -p "> " nova_backend_port
    nova_backend_port=${nova_backend_port:-8081}
    
    if ! [[ "$nova_backend_port" =~ ^[0-9]+$ ]]; then
      printf "${RED} >> Porta inválida! Digite apenas números.${WHITE}\n"
      continue
    fi
    
    if lsof -i:${nova_backend_port} &>/dev/null; then
      printf "${RED} >> A porta ${nova_backend_port} já está em uso. Escolha outra.${WHITE}\n"
      continue
    fi
    
    break
  done
  echo
  
  # Porta Frontend
  banner
  while true; do
    printf "${WHITE} >> Qual porta deseja para o Frontend? (padrão: 3001):${WHITE}\n"
    read -p "> " nova_frontend_port
    nova_frontend_port=${nova_frontend_port:-3001}
    
    if ! [[ "$nova_frontend_port" =~ ^[0-9]+$ ]]; then
      printf "${RED} >> Porta inválida! Digite apenas números.${WHITE}\n"
      continue
    fi
    
    if lsof -i:${nova_frontend_port} &>/dev/null; then
      printf "${RED} >> A porta ${nova_frontend_port} já está em uso. Escolha outra.${WHITE}\n"
      continue
    fi
    
    break
  done
  echo
  
  # Porta Redis
  banner
  while true; do
    printf "${WHITE} >> Qual porta deseja para o Redis? (padrão: 6380):${WHITE}\n"
    read -p "> " nova_redis_port
    nova_redis_port=${nova_redis_port:-6380}
    
    if ! [[ "$nova_redis_port" =~ ^[0-9]+$ ]]; then
      printf "${RED} >> Porta inválida! Digite apenas números.${WHITE}\n"
      continue
    fi
    
    if lsof -i:${nova_redis_port} &>/dev/null; then
      printf "${RED} >> A porta ${nova_redis_port} já está em uso. Escolha outra.${WHITE}\n"
      continue
    fi
    
    break
  done
  echo
}

# Solicitar dados adicionais
solicitar_dados_adicionais() {
  banner
  printf "${WHITE} >> Dados Adicionais da Nova Instância\n"
  echo
  
  # Carregar variáveis base se existirem
  carregar_variaveis_base
  
  # Email
  if [ -f "$ARQUIVO_VARIAVEIS_BASE" ] && [ -n "${email_deploy}" ]; then
    printf "${GREEN} >> Email encontrado no arquivo de variáveis base: ${email_deploy}${WHITE}\n"
    printf "${WHITE} >> Deseja usar este email? (S/N):${WHITE}\n"
    read -p "> " usar_email_base
    usar_email_base=$(echo "${usar_email_base}" | tr '[:upper:]' '[:lower:]')
    if [ "${usar_email_base}" != "s" ]; then
      printf "${WHITE} >> Digite o email para certificados SSL:${WHITE}\n"
      read -p "> " email_deploy
    fi
  else
    printf "${WHITE} >> Digite o email para certificados SSL:${WHITE}\n"
    read -p "> " email_deploy
  fi
  echo
  
  # Senha Deploy - Carregar do arquivo base se existir (sempre usar a mesma senha do deploy)
  if [ -f "$ARQUIVO_VARIAVEIS_BASE" ] && [ -n "${senha_deploy}" ]; then
    printf "${GREEN} >> Senha do usuário Deploy encontrada no arquivo de variáveis base.${WHITE}\n"
    printf "${GREEN} >> Usando a mesma senha do deploy existente para esta instância.${WHITE}\n"
    echo
    sleep 2
  else
    banner
    printf "${YELLOW} >> ATENÇÃO: Arquivo de variáveis base não encontrado ou senha não definida.${WHITE}\n"
    printf "${WHITE} >> Insira a senha para o usuário Deploy e Banco de Dados ${RED}(IMPORTANTE: Não utilizar caracteres especiais)${WHITE}:${WHITE}\n"
    read -p "> " senha_deploy
    echo
  fi
  
  # Senha Master
  banner
  printf "${WHITE} >> Insira a senha para o MASTER:${WHITE}\n"
  read -p "> " senha_master
  echo
  
  # Título
  banner
  printf "${WHITE} >> Insira o Título da Aplicação (Permitido Espaço):${WHITE}\n"
  read -p "> " nome_titulo
  echo
  
  # Número Suporte
  banner
  printf "${WHITE} >> Digite o número de telefone para suporte:${WHITE}\n"
  read -p "> " numero_suporte
  echo
  
  # Facebook App ID
  banner
  printf "${WHITE} >> Digite o FACEBOOK_APP_ID caso tenha:${WHITE}\n"
  read -p "> " facebook_app_id
  echo
  
  # Facebook App Secret
  banner
  printf "${WHITE} >> Digite o FACEBOOK_APP_SECRET caso tenha:${WHITE}\n"
  read -p "> " facebook_app_secret
  echo
  
  # Repositório - Carregar do arquivo base se existir
  if [ -f "$ARQUIVO_VARIAVEIS_BASE" ] && [ -n "${repo_url}" ]; then
    printf "${GREEN} >> URL do repositório encontrada no arquivo de variáveis base: ${repo_url}${WHITE}\n"
    printf "${WHITE} >> Deseja usar este repositório? (S/N):${WHITE}\n"
    read -p "> " usar_repo_base
    usar_repo_base=$(echo "${usar_repo_base}" | tr '[:upper:]' '[:lower:]')
    if [ "${usar_repo_base}" != "s" ]; then
      banner
      printf "${WHITE} >> Digite a URL do repositório privado no GitHub:${WHITE}\n"
      read -p "> " repo_url
    fi
  else
    banner
    printf "${WHITE} >> Digite a URL do repositório privado no GitHub:${WHITE}\n"
    read -p "> " repo_url
  fi
  echo
  
  # Token GitHub - Carregar do arquivo base se existir e validar
  token_valido=false
  if [ -f "$ARQUIVO_VARIAVEIS_BASE" ] && [ -n "${github_token}" ]; then
    printf "${WHITE} >> Validando token do GitHub encontrado no arquivo base...\n"
    if validar_token_github "${github_token}" "${repo_url}"; then
      printf "${GREEN} >> Token do GitHub válido!${WHITE}\n"
      token_valido=true
    else
      printf "${RED} >> Token do GitHub inválido ou expirado!${WHITE}\n"
      printf "${YELLOW} >> Será necessário informar um novo token.${WHITE}\n"
      echo
      sleep 2
    fi
  fi
  
  # Se token não foi validado ou não existe, pedir novo
  if [ "$token_valido" = false ]; then
    banner
    printf "${WHITE} >> Digite seu TOKEN de acesso pessoal do GitHub:${WHITE}\n"
    printf "${WHITE} >> Passo a Passo para gerar o seu TOKEN no link ${BLUE}https://bit.ly/token-github ${WHITE}\n"
    read -p "> " github_token
    
    # Validar o novo token
    printf "${WHITE} >> Validando token...\n"
    while ! validar_token_github "${github_token}" "${repo_url}"; do
      printf "${RED} >> Token inválido! Por favor, verifique o token e tente novamente.${WHITE}\n"
      echo
      printf "${WHITE} >> Digite seu TOKEN de acesso pessoal do GitHub:${WHITE}\n"
      read -p "> " github_token
    done
    printf "${GREEN} >> Token validado com sucesso!${WHITE}\n"
  fi
  echo
  
  # Validar que o repositório é o correto (usando mesma validação do instalador_single.sh)
  repo_url_limpo=$(echo "${repo_url}" | sed 's|https://||' | sed 's|http://||' | sed 's|\.git$||' | sed 's|/$||')
  repo_esperado="github.com/scriptswhitelabel/multiflow-pro"
  
  if [ "${repo_url_limpo}" != "${repo_esperado}" ]; then
    printf "${RED}══════════════════════════════════════════════════════════════════${WHITE}\n"
    printf "${RED}❌ ERRO: Repositório inválido!${WHITE}\n"
    echo
    printf "${YELLOW}   O repositório deve ser exatamente:${WHITE}\n"
    printf "${BLUE}   https://github.com/scriptswhitelabel/multiflow-pro${WHITE}\n"
    printf "${BLUE}   ou${WHITE}\n"
    printf "${BLUE}   https://github.com/scriptswhitelabel/multiflow-pro.git${WHITE}\n"
    echo
    printf "${RED}   Repositório informado: ${repo_url}${WHITE}\n"
    printf "${RED}══════════════════════════════════════════════════════════════════${WHITE}\n"
    echo
    sleep 5
    exit 1
  fi
  
  # Selecionar versão (usando mesma função do instalador_single.sh)
  selecionar_versao_instalacao
  
  # Proxy
  banner
  while true; do
    printf "${WHITE} >> Instalar usando Nginx ou Traefik? (Nginx/Traefik):${WHITE}\n"
    read -p "> " proxy
    proxy=$(echo "${proxy}" | tr '[:upper:]' '[:lower:]')
    
    if [ "${proxy}" = "nginx" ] || [ "${proxy}" = "traefik" ]; then
      break
    else
      printf "${RED} >> Por favor, digite 'Nginx' ou 'Traefik' para continuar...${WHITE}\n"
    fi
  done
  echo
}

# Salvar variáveis da nova instância
salvar_variaveis_instancia() {
  # Salvar no diretório do instalador principal
  INSTALADOR_DIR="/root/instalador_single_oficial"
  if [ -d "$INSTALADOR_DIR" ]; then
    ARQUIVO_VARIAVEIS_INSTANCIA="${INSTALADOR_DIR}/VARIAVEIS_INSTALACAO_INSTANCIA_${nova_empresa}"
  else
    ARQUIVO_VARIAVEIS_INSTANCIA="$(pwd)/VARIAVEIS_INSTALACAO_INSTANCIA_${nova_empresa}"
  fi
  
  {
    echo "subdominio_backend=${nova_subdominio_backend}" > "$ARQUIVO_VARIAVEIS_INSTANCIA"
    echo "subdominio_frontend=${nova_subdominio_frontend}" >> "$ARQUIVO_VARIAVEIS_INSTANCIA"
    echo "email_deploy=${email_deploy}" >> "$ARQUIVO_VARIAVEIS_INSTANCIA"
    echo "empresa=${nova_empresa}" >> "$ARQUIVO_VARIAVEIS_INSTANCIA"
    echo "senha_deploy=${senha_deploy}" >> "$ARQUIVO_VARIAVEIS_INSTANCIA"
    echo "senha_master=${senha_master}" >> "$ARQUIVO_VARIAVEIS_INSTANCIA"
    echo "nome_titulo=${nome_titulo}" >> "$ARQUIVO_VARIAVEIS_INSTANCIA"
    echo "numero_suporte=${numero_suporte}" >> "$ARQUIVO_VARIAVEIS_INSTANCIA"
    echo "facebook_app_id=${facebook_app_id}" >> "$ARQUIVO_VARIAVEIS_INSTANCIA"
    echo "facebook_app_secret=${facebook_app_secret}" >> "$ARQUIVO_VARIAVEIS_INSTANCIA"
    echo "github_token=${github_token}" >> "$ARQUIVO_VARIAVEIS_INSTANCIA"
    echo "repo_url=${repo_url}" >> "$ARQUIVO_VARIAVEIS_INSTANCIA"
    echo "proxy=${proxy}" >> "$ARQUIVO_VARIAVEIS_INSTANCIA"
    echo "backend_port=${nova_backend_port}" >> "$ARQUIVO_VARIAVEIS_INSTANCIA"
    echo "frontend_port=${nova_frontend_port}" >> "$ARQUIVO_VARIAVEIS_INSTANCIA"
    echo "redis_port=${nova_redis_port}" >> "$ARQUIVO_VARIAVEIS_INSTANCIA"
    echo "versao_instalacao=${versao_instalacao:-Mais Recente}" >> "$ARQUIVO_VARIAVEIS_INSTANCIA"
    echo "commit_instalacao=${commit_instalacao:-}" >> "$ARQUIVO_VARIAVEIS_INSTANCIA"
    
    printf "${GREEN} >> Variáveis da instância salvas em: ${ARQUIVO_VARIAVEIS_INSTANCIA}${WHITE}\n"
  } || trata_erro "salvar_variaveis_instancia"
}

# Verificar e instalar Docker
verificar_e_instalar_docker() {
  banner
  printf "${WHITE} >> Verificando se o Docker está instalado...\n"
  echo
  
  if command -v docker >/dev/null 2>&1; then
    printf "${GREEN} >> Docker já está instalado.${WHITE}\n"
    docker --version
    echo
    sleep 2
  else
    printf "${YELLOW} >> Docker não encontrado. Iniciando instalação...${WHITE}\n"
    echo
    
    {
      sudo apt-get update -y >/dev/null 2>&1
      sudo apt-get install -y ca-certificates curl gnupg lsb-release >/dev/null 2>&1
      
      sudo install -m 0755 -d /etc/apt/keyrings
      curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg >/dev/null 2>&1
      sudo chmod a+r /etc/apt/keyrings/docker.gpg
      
      echo \
        "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
        $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
      
      sudo apt-get update -y >/dev/null 2>&1
      sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin >/dev/null 2>&1
      
      printf "${GREEN} >> Docker instalado com sucesso!${WHITE}\n"
      docker --version
      echo
      sleep 2
    } || trata_erro "verificar_e_instalar_docker"
  fi
  
  # Verificar se docker compose está disponível
  if ! docker compose version >/dev/null 2>&1; then
    printf "${YELLOW} >> Instalando docker-compose-plugin...${WHITE}\n"
    sudo apt-get install -y docker-compose-plugin >/dev/null 2>&1
  fi
}

# Instalar Redis em Docker
instalar_redis_docker() {
  banner
  printf "${WHITE} >> Instalando Redis em Docker para a instância ${nova_empresa}...\n"
  echo
  
  {
    # Criar diretório para dados do Redis
    mkdir -p /home/deploy/redis_${nova_empresa}
    chown -R deploy:deploy /home/deploy/redis_${nova_empresa}
    
    # Criar docker-compose para Redis
    cat > /home/deploy/redis_${nova_empresa}/docker-compose.yml <<EOF
version: '3.8'

services:
  redis:
    image: redis:7-alpine
    container_name: redis_${nova_empresa}
    ports:
      - "${nova_redis_port}:6379"
    volumes:
      - redis_data_${nova_empresa}:/data
    command: redis-server --requirepass ${senha_deploy} --appendonly yes
    restart: always
    networks:
      - redis_network_${nova_empresa}

volumes:
  redis_data_${nova_empresa}:

networks:
  redis_network_${nova_empresa}:
    driver: bridge
EOF

    # Subir o container Redis
    cd /home/deploy/redis_${nova_empresa}
    docker compose up -d
    
    # Aguardar Redis iniciar
    sleep 5
    
    # Verificar se está rodando
    if docker ps | grep -q "redis_${nova_empresa}"; then
      printf "${GREEN}✅ Redis instalado e rodando em Docker na porta ${nova_redis_port}!${WHITE}\n"
      echo
      sleep 2
    else
      printf "${RED}❌ ERRO: Falha ao iniciar Redis em Docker.${WHITE}\n"
      exit 1
    fi
  } || trata_erro "instalar_redis_docker"
}

# Verificar DNS (usando mesma lógica do instalador_single.sh)
verificar_dns_instancia() {
  banner
  printf "${WHITE} >> Verificando o DNS dos dominios/subdominios...\n"
  echo
  sleep 2
  sudo apt-get install dnsutils -y >/dev/null 2>&1
  subdominios_incorretos=""

  verificar_dns() {
    local domain=$1
    local resolved_ip
    local cname_target

    cname_target=$(dig +short CNAME ${domain} 2>/dev/null)

    if [ -n "${cname_target}" ]; then
      resolved_ip=$(dig +short ${cname_target} 2>/dev/null)
    else
      resolved_ip=$(dig +short ${domain} 2>/dev/null)
    fi

    if [ "${resolved_ip}" != "${ip_atual}" ]; then
      echo "O domínio ${domain} (resolvido para ${resolved_ip}) não está apontando para o IP público atual (${ip_atual})."
      subdominios_incorretos+="${domain} "
      sleep 2
    fi
  }
  verificar_dns ${nova_subdominio_backend}
  verificar_dns ${nova_subdominio_frontend}
  if [ -n "${subdominios_incorretos}" ]; then
    echo
    printf "${YELLOW} >> ATENÇÃO: Os seguintes subdomínios não estão apontando para o IP público atual (${ip_atual}):${WHITE}\n"
    printf "${YELLOW} >> ${subdominios_incorretos}${WHITE}\n"
    echo
    printf "${WHITE} >> Deseja continuar a instalação mesmo assim? (S/N): ${WHITE}\n"
    echo
    read -p "> " continuar_dns
    continuar_dns=$(echo "${continuar_dns}" | tr '[:lower:]' '[:upper:]')
    echo
    if [ "${continuar_dns}" != "S" ]; then
      printf "${GREEN} >> Instalação cancelada.${WHITE}\n"
      sleep 2
      exit 0
    else
      printf "${YELLOW} >> Continuando a instalação mesmo com DNS não configurado corretamente...${WHITE}\n"
      sleep 2
    fi
  else
    echo "Todos os subdomínios estão apontando corretamente para o IP público da VPS."
    sleep 2
  fi
  echo
  printf "${WHITE} >> Continuando...\n"
  sleep 2
  echo
}

# Verificar conectividade de rede e DNS
verificar_conectividade() {
  printf "${WHITE} >> Verificando conectividade de rede...\n"
  
  if ! ping -c 1 -W 2 8.8.8.8 >/dev/null 2>&1; then
    printf "${RED} >> ERRO: Sem conectividade de rede (não consegue alcançar 8.8.8.8)${WHITE}\n"
    return 1
  fi
  
  if ! ping -c 1 -W 2 google.com >/dev/null 2>&1; then
    printf "${RED} >> ERRO: Problema com resolução DNS${WHITE}\n"
    return 1
  fi
  
  printf "${GREEN} >> Conectividade de rede OK!${WHITE}\n"
  return 0
}

# Tentar corrigir problemas de DNS
tentar_corrigir_dns() {
  printf "${WHITE} >> Tentando corrigir problemas de DNS...\n"
  
  if ! grep -q "8.8.8.8" /etc/resolv.conf 2>/dev/null; then
    printf "${WHITE} >> Adicionando Google DNS (8.8.8.8)...\n"
    echo "nameserver 8.8.8.8" >> /etc/resolv.conf
    echo "nameserver 8.8.4.4" >> /etc/resolv.conf
  fi
  
  if command -v systemd-resolve &> /dev/null; then
    systemd-resolve --flush-caches >/dev/null 2>&1 || true
  fi
  
  sleep 2
}

# Verificar e instalar dependências do sistema (se necessário)
verificar_dependencias_sistema() {
  banner
  printf "${WHITE} >> Verificando dependências do sistema...\n"
  echo
  
  # Verificar se Postgres está instalado
  if ! command -v psql >/dev/null 2>&1; then
    printf "${YELLOW} >> PostgreSQL não encontrado. Será necessário instalar.${WHITE}\n"
    printf "${YELLOW} >> Por favor, execute o instalador_single.sh primeiro ou instale PostgreSQL manualmente.${WHITE}\n"
    sleep 3
  else
    printf "${GREEN} >> PostgreSQL já está instalado.${WHITE}\n"
  fi
  
  # Verificar se Node.js está instalado
  if ! command -v node >/dev/null 2>&1; then
    printf "${YELLOW} >> Node.js não encontrado. Será necessário instalar.${WHITE}\n"
    printf "${YELLOW} >> Por favor, execute o instalador_single.sh primeiro ou instale Node.js manualmente.${WHITE}\n"
    sleep 3
  else
    printf "${GREEN} >> Node.js já está instalado.${WHITE}\n"
  fi
  
  # Verificar se PM2 está instalado
  if ! command -v pm2 >/dev/null 2>&1; then
    printf "${YELLOW} >> PM2 não encontrado. Será necessário instalar.${WHITE}\n"
    printf "${YELLOW} >> Por favor, execute o instalador_single.sh primeiro ou instale PM2 manualmente.${WHITE}\n"
    sleep 3
  else
    printf "${GREEN} >> PM2 já está instalado.${WHITE}\n"
  fi
  
  # Verificar se Nginx ou Traefik está instalado (dependendo da escolha)
  if [ "${proxy}" = "nginx" ]; then
    if ! command -v nginx >/dev/null 2>&1; then
      printf "${YELLOW} >> Nginx não encontrado. Será necessário instalar.${WHITE}\n"
      printf "${YELLOW} >> Por favor, execute o instalador_single.sh primeiro ou instale Nginx manualmente.${WHITE}\n"
      sleep 3
    else
      printf "${GREEN} >> Nginx já está instalado.${WHITE}\n"
    fi
  elif [ "${proxy}" = "traefik" ]; then
    if ! command -v traefik >/dev/null 2>&1 && [ ! -f /usr/local/bin/traefik ]; then
      printf "${YELLOW} >> Traefik não encontrado. Será necessário instalar.${WHITE}\n"
      printf "${YELLOW} >> Por favor, execute o instalador_single.sh primeiro ou instale Traefik manualmente.${WHITE}\n"
      sleep 3
    else
      printf "${GREEN} >> Traefik já está instalado.${WHITE}\n"
    fi
  fi
  
  sleep 2
}

# Criar banco de dados para a nova instância
cria_banco_instancia() {
  banner
  printf "${WHITE} >> Criando Banco Postgres para ${nova_empresa}...\n"
  echo
  {
    sudo su - postgres <<EOF
    createdb ${nova_empresa};
    psql
    CREATE USER ${nova_empresa} SUPERUSER INHERIT CREATEDB CREATEROLE;
    ALTER USER ${nova_empresa} PASSWORD '${senha_deploy}';
    \q
    exit
EOF
    sleep 2
  } || trata_erro "cria_banco_instancia"
}

# Função para codificar URL de clone
codifica_clone_instancia() {
  local length="${#1}"
  for ((i = 0; i < length; i++)); do
    local c="${1:i:1}"
    case $c in
    [a-zA-Z0-9.~_-]) printf "$c" ;;
    *) printf '%%%02X' "'$c" ;;
    esac
  done
}

# Clona código de repo privado
baixa_codigo_instancia() {
  banner
  printf "${WHITE} >> Fazendo download do código para ${nova_empresa}...\n"
  echo
  {
    if [ -z "${repo_url}" ] || [ -z "${github_token}" ]; then
      printf "${WHITE} >> Erro: URL do repositório ou token do GitHub não definidos.\n"
      exit 1
    fi

    github_token_encoded=$(codifica_clone_instancia "${github_token}")
    github_url=$(echo ${repo_url} | sed "s|https://|https://${github_token_encoded}@|")

    dest_dir="/home/deploy/${nova_empresa}/"

    git clone ${github_url} ${dest_dir}
    echo
    if [ $? -eq 0 ]; then
      printf "${WHITE} >> Código baixado, continuando a instalação...\n"
      echo
    else
      printf "${WHITE} >> Falha ao baixar o código! Verifique as informações fornecidas...\n"
      echo
      exit 1
    fi

    # Verificar se foi selecionada a opção "Mais Recente"
    if [ -z "${commit_instalacao}" ] || [ "${versao_instalacao}" = "Mais Recente" ]; then
      banner
      printf "${WHITE} >> Instalando versão mais recente disponível no repositório...\n"
      echo
      
      cd ${dest_dir} || trata_erro "cd para diretório do projeto"
      
      sudo su - deploy <<CHECKOUTRECENT
cd ${dest_dir}
git fetch --all --prune 2>/dev/null || true

if git show-ref --verify --quiet refs/remotes/origin/MULTI100-OFICIAL-u21; then
  git checkout MULTI100-OFICIAL-u21 2>/dev/null || git checkout -b MULTI100-OFICIAL-u21 origin/MULTI100-OFICIAL-u21
  git pull origin MULTI100-OFICIAL-u21 2>/dev/null || true
elif git show-ref --verify --quiet refs/remotes/origin/main; then
  git checkout main 2>/dev/null || git checkout -b main origin/main
  git pull origin main 2>/dev/null || true
elif git show-ref --verify --quiet refs/remotes/origin/master; then
  git checkout master 2>/dev/null || git checkout -b master origin/master
  git pull origin master 2>/dev/null || true
fi
CHECKOUTRECENT
      
      printf "${GREEN} >> Versão mais recente do repositório será instalada${WHITE}\n"
      echo
      sleep 2
    elif [ -n "${commit_instalacao}" ]; then
      banner
      printf "${WHITE} >> Fazendo checkout para o commit da versão ${versao_instalacao}...\n"
      echo
      
      cd ${dest_dir} || trata_erro "cd para diretório do projeto"
      
      chown -R deploy:deploy ${dest_dir} 2>/dev/null || true
      chmod -R 755 ${dest_dir}/.git 2>/dev/null || true
      
      sudo su - deploy <<FETCHCOMMIT
cd ${dest_dir}
git fetch --all --prune 2>/dev/null || true
FETCHCOMMIT
      
      sudo su - deploy <<VERIFYCOMMIT
cd ${dest_dir}
if git cat-file -e "${commit_instalacao}^{commit}" 2>/dev/null; then
  exit 0
else
  exit 1
fi
VERIFYCOMMIT
      
      if [ $? -eq 0 ]; then
        BRANCH_INSTALACAO="instalacao-${versao_instalacao}-$(date +%Y%m%d-%H%M%S)"
        sudo su - deploy <<CHECKOUTCOMMIT
cd ${dest_dir}
git checkout -b "${BRANCH_INSTALACAO}" "${commit_instalacao}"
CHECKOUTCOMMIT
        
        if [ $? -eq 0 ]; then
          printf "${GREEN} >> Checkout para commit ${commit_instalacao} concluído com sucesso!${WHITE}\n"
          printf "${GREEN} >> Branch criada: ${BRANCH_INSTALACAO}${WHITE}\n"
          echo
        else
          printf "${RED} >> ERRO: Falha ao fazer checkout do commit ${commit_instalacao}${WHITE}\n"
          exit 1
        fi
      else
        printf "${RED} >> ERRO: Commit ${commit_instalacao} não encontrado no repositório.${WHITE}\n"
        exit 1
      fi
    fi

    mkdir -p /home/deploy/${nova_empresa}/backend/public/
    chown deploy:deploy -R /home/deploy/${nova_empresa}/
    chmod 775 -R /home/deploy/${nova_empresa}/backend/public/
    sleep 2
  } || trata_erro "baixa_codigo_instancia"
}

# Instala e configura backend
instala_backend_instancia() {
  banner
  printf "${WHITE} >> Configurando variáveis de ambiente do ${BLUE}backend${WHITE}...\n"
  echo
  
  {
    sleep 2
    subdominio_backend_clean=$(echo "${nova_subdominio_backend/https:\/\//}")
    subdominio_backend_clean=${subdominio_backend_clean%%/*}
    subdominio_backend_final=https://${subdominio_backend_clean}
    subdominio_frontend_clean=$(echo "${nova_subdominio_frontend/https:\/\//}")
    subdominio_frontend_clean=${subdominio_frontend_clean%%/*}
    subdominio_frontend_final=https://${subdominio_frontend_clean}
    
    sudo su - deploy <<EOF
  cat <<[-]EOF > /home/deploy/${nova_empresa}/backend/.env
# Scripts WhiteLabel - All Rights Reserved - (18) 9 8802-9627
NODE_ENV=
BACKEND_URL=${subdominio_backend_final}
FRONTEND_URL=${subdominio_frontend_final}
PROXY_PORT=443
PORT=${nova_backend_port}

# CREDENCIAIS BD
DB_HOST=localhost
DB_DIALECT=postgres
DB_PORT=5432
DB_USER=${nova_empresa}
DB_PASS=${senha_deploy}
DB_NAME=${nova_empresa}

# DADOS REDIS (Docker)
REDIS_URI=redis://:${senha_deploy}@127.0.0.1:${nova_redis_port}
REDIS_OPT_LIMITER_MAX=1
REDIS_OPT_LIMITER_DURATION=3000

# --- RabbitMQ ---
RABBITMQ_HOST=localhost
RABBITMQ_PORT=5672
RABBIT_USER=${nova_empresa}
RABBIT_PASS=${senha_deploy}
RABBITMQ_URI=amqp://\${nova_empresa}:\${senha_deploy}@localhost:5672/

TIMEOUT_TO_IMPORT_MESSAGE=1000

# SECRETS
JWT_SECRET=${jwt_secret}
JWT_REFRESH_SECRET=${jwt_refresh_secret}
MASTER_KEY=${senha_master}

VERIFY_TOKEN=whaticket
FACEBOOK_APP_ID=${facebook_app_id}
FACEBOOK_APP_SECRET=${facebook_app_secret}

#METODOS DE PAGAMENTO

STRIPE_PRIVATE=
STRIPE_OK_URL=BACKEND_URL/subscription/stripewebhook
STRIPE_CANCEL_URL=FRONTEND_URL/financeiro

# MERCADO PAGO

MPACCESSTOKEN=SEU TOKEN
MPNOTIFICATIONURL=https://SUB_DOMINIO_API/subscription/mercadopagowebhook

MP_ACCESS_TOKEN=SEU TOKEN
MP_NOTIFICATION_URL=https://SUB_DOMINIO_API/subscription/mercadopagowebhook

ASAAS_TOKEN=SEU TOKEN
MP_NOTIFICATION_URL=https://SUB_DOMINIO_API/subscription/asaaswebhook

MPNOTIFICATION_URL=https://SUB_DOMINIO_API/subscription/asaaswebhook
ASAASTOKEN=SEU TOKEN

GERENCIANET_SANDBOX=
GERENCIANET_CLIENT_ID=
GERENCIANET_CLIENT_SECRET=
GERENCIANET_PIX_CERT=
GERENCIANET_PIX_KEY=

# EMAIL
MAIL_HOST="smtp.gmail.com"
MAIL_USER="SEUGMAIL@gmail.com"
MAIL_PASS="SENHA DE APP"
MAIL_FROM="Recuperação de Senha <SEU GMAIL@gmail.com>"
MAIL_PORT="465"

# WAVOIP
WAVOIP_URL=https://api.wavoip.com
WAVOIP_USERNAME='seuemaildowavoip@email.com.br'
WAVOIP_PASSWORD='SUASENHA'

# WhatsApp Oficial
USE_WHATSAPP_OFICIAL=true
TOKEN_API_OFICIAL="adminpro"
OFFICIAL_CAMPAIGN_CONCURRENCY=10

# API de Transcrição de Audio
TRANSCRIBE_URL=http://localhost:4002

# Buffer Size Configuration
MAX_BUFFER_SIZE_MB=200
[-]EOF
EOF

    sleep 2

    banner
    printf "${WHITE} >> Instalando dependências do ${BLUE}backend${WHITE}...\n"
    echo
    sudo su - deploy <<BACKENDINSTALL
  if [ -d /usr/local/n/versions/node/20.19.4/bin ]; then
    export PATH=/usr/local/n/versions/node/20.19.4/bin:/usr/bin:/usr/local/bin:\$PATH
  elif [ -f /usr/bin/node ]; then
    export PATH=/usr/bin:/usr/local/bin:\$PATH
  fi
  
  BACKEND_DIR="/home/deploy/${nova_empresa}/backend"
  if [ ! -d "\$BACKEND_DIR" ]; then
    echo "ERRO: Diretório do backend não existe: \$BACKEND_DIR"
    exit 1
  fi
  
  cd "\$BACKEND_DIR"
  
  if [ ! -f "package.json" ]; then
    echo "ERRO: package.json não encontrado em \$BACKEND_DIR"
    exit 1
  fi
  
  export PUPPETEER_SKIP_DOWNLOAD=true
  rm -rf node_modules 2>/dev/null || true
  rm -f package-lock.json 2>/dev/null || true
  npm install --force
  npm install puppeteer-core --force
  npm i glob
  npm run build
BACKENDINSTALL

    sleep 2

    sudo su - deploy <<FFMPEGFIX
  BACKEND_DIR="/home/deploy/${nova_empresa}/backend"
  FFMPEG_FILE="\${BACKEND_DIR}/node_modules/@ffmpeg-installer/ffmpeg/index.js"
  
  if [ -f "\$FFMPEG_FILE" ]; then
    sed -i 's|npm3Binary = .*|npm3Binary = "/usr/bin/ffmpeg";|' "\$FFMPEG_FILE"
  fi
  
  mkdir -p "\${BACKEND_DIR}/node_modules/@ffmpeg-installer/linux-x64/" 2>/dev/null || true
  if [ -d "\${BACKEND_DIR}/node_modules/@ffmpeg-installer/linux-x64/" ]; then
    echo '{ "version": "1.1.0", "name": "@ffmpeg-installer/linux-x64" }' > "\${BACKEND_DIR}/node_modules/@ffmpeg-installer/linux-x64/package.json"
  fi
FFMPEGFIX

    sleep 2

    banner
    printf "${WHITE} >> Executando db:migrate...\n"
    echo
    sudo su - deploy <<MIGRATEINSTALL
  if [ -d /usr/local/n/versions/node/20.19.4/bin ]; then
    export PATH=/usr/local/n/versions/node/20.19.4/bin:/usr/bin:/usr/local/bin:\$PATH
  else
    export PATH=/usr/bin:/usr/local/bin:\$PATH
  fi
  
  BACKEND_DIR="/home/deploy/${nova_empresa}/backend"
  cd "\$BACKEND_DIR"
  npx sequelize db:migrate
MIGRATEINSTALL

    sleep 2

    banner
    printf "${WHITE} >> Executando db:seed...\n"
    echo
    sudo su - deploy <<SEEDINSTALL
  if [ -d /usr/local/n/versions/node/20.19.4/bin ]; then
    export PATH=/usr/local/n/versions/node/20.19.4/bin:/usr/bin:/usr/local/bin:\$PATH
  else
    export PATH=/usr/bin:/usr/local/bin:\$PATH
  fi
  
  BACKEND_DIR="/home/deploy/${nova_empresa}/backend"
  cd "\$BACKEND_DIR"
  npx sequelize db:seed:all
SEEDINSTALL

    sleep 2

    banner
    printf "${WHITE} >> Iniciando pm2 ${BLUE}backend${WHITE}...\n"
    echo
    sudo su - deploy <<PM2BACKEND
  if [ -d /usr/local/n/versions/node/20.19.4/bin ]; then
    export PATH=/usr/local/n/versions/node/20.19.4/bin:/usr/bin:/usr/local/bin:\$PATH
  else
    export PATH=/usr/bin:/usr/local/bin:\$PATH
  fi
  
  BACKEND_DIR="/home/deploy/${nova_empresa}/backend"
  cd "\$BACKEND_DIR"
  
  if [ ! -f "dist/server.js" ]; then
    echo "ERRO: Arquivo dist/server.js não encontrado. O build pode ter falhado."
    exit 1
  fi
  
  pm2 start dist/server.js --name ${nova_empresa}-backend
PM2BACKEND

    sleep 2
  } || trata_erro "instala_backend_instancia"
}

# Instala e configura frontend
instala_frontend_instancia() {
  banner
  printf "${WHITE} >> Instalando dependências do ${BLUE}frontend${WHITE}...\n"
  echo
  
  {
    sudo su - deploy <<FRONTENDINSTALL
  if [ -d /usr/local/n/versions/node/20.19.4/bin ]; then
    export PATH=/usr/local/n/versions/node/20.19.4/bin:/usr/bin:/usr/local/bin:\$PATH
  else
    export PATH=/usr/bin:/usr/local/bin:\$PATH
  fi
  
  FRONTEND_DIR="/home/deploy/${nova_empresa}/frontend"
  if [ ! -d "\$FRONTEND_DIR" ]; then
    echo "ERRO: Diretório do frontend não existe: \$FRONTEND_DIR"
    exit 1
  fi
  
  cd "\$FRONTEND_DIR"
  
  if [ ! -f "package.json" ]; then
    echo "ERRO: package.json não encontrado em \$FRONTEND_DIR"
    exit 1
  fi
  
  npm install --force
  npx browserslist@latest --update-db
FRONTENDINSTALL

    sleep 2

    banner
    printf "${WHITE} >> Configurando variáveis de ambiente ${BLUE}frontend${WHITE}...\n"
    echo
    subdominio_backend_clean=$(echo "${nova_subdominio_backend/https:\/\//}")
    subdominio_backend_clean=${subdominio_backend_clean%%/*}
    subdominio_backend_final=https://${subdominio_backend_clean}
    
    sudo su - deploy <<EOF
  cat <<[-]EOF > /home/deploy/${nova_empresa}/frontend/.env
REACT_APP_BACKEND_URL=${subdominio_backend_final}
REACT_APP_FACEBOOK_APP_ID=${facebook_app_id}
REACT_APP_REQUIRE_BUSINESS_MANAGEMENT=TRUE
REACT_APP_NAME_SYSTEM=${nome_titulo}
REACT_APP_NUMBER_SUPPORT=${numero_suporte}
SERVER_PORT=${nova_frontend_port}
[-]EOF
EOF

    sleep 2

    banner
    printf "${WHITE} >> Compilando o código do ${BLUE}frontend${WHITE}...\n"
    echo
    sudo su - deploy <<FRONTENDBUILD
  if [ -d /usr/local/n/versions/node/20.19.4/bin ]; then
    export PATH=/usr/local/n/versions/node/20.19.4/bin:/usr/bin:/usr/local/bin:\$PATH
  else
    export PATH=/usr/bin:/usr/local/bin:\$PATH
  fi
  
  FRONTEND_DIR="/home/deploy/${nova_empresa}/frontend"
  cd "\$FRONTEND_DIR"
  
  if [ ! -f "server.js" ]; then
    echo "ERRO: Arquivo server.js não encontrado em \$FRONTEND_DIR"
    exit 1
  fi
  
  sed -i 's/3000/'"${nova_frontend_port}"'/g' server.js
  NODE_OPTIONS="--max-old-space-size=4096 --openssl-legacy-provider" npm run build
FRONTENDBUILD

    sleep 2

    banner
    printf "${WHITE} >> Iniciando pm2 ${BLUE}frontend${WHITE}...\n"
    echo
    sudo su - deploy <<PM2FRONTEND
  if [ -d /usr/local/n/versions/node/20.19.4/bin ]; then
    export PATH=/usr/local/n/versions/node/20.19.4/bin:/usr/bin:/usr/local/bin:\$PATH
  else
    export PATH=/usr/bin:/usr/local/bin:\$PATH
  fi
  
  FRONTEND_DIR="/home/deploy/${nova_empresa}/frontend"
  cd "\$FRONTEND_DIR"
  
  if [ ! -f "server.js" ]; then
    echo "ERRO: Arquivo server.js não encontrado em \$FRONTEND_DIR"
    exit 1
  fi
  
  pm2 start server.js --name ${nova_empresa}-frontend
  pm2 save
PM2FRONTEND

    sleep 2
  } || trata_erro "instala_frontend_instancia"
}

# Configura cron de atualização
config_cron_instancia() {
  printf "${GREEN} >> Configurando cron jobs...${WHITE} \n"
  echo
  {
    if ! command -v cron >/dev/null 2>&1; then
      sudo apt-get update
      sudo apt-get install -y cron
    fi
    sleep 2
    
    sudo su - deploy <<'EOF'
        CRON_JOB1="0 3 * * * wget -O /home/deploy/atualiza_public.sh https://raw.githubusercontent.com/FilipeCamillo/busca_tamaho_pasta/main/busca_tamaho_pasta.sh && bash /home/deploy/atualiza_public.sh >> /home/deploy/cron.log 2>&1"
        CRON_JOB2="0 1 * * * /bin/bash /home/deploy/reinicia_instancia.sh >> /home/deploy/cron.log 2>&1"
        CRON_EXISTS1=$(crontab -l 2>/dev/null | grep -F "${CRON_JOB1}")
        CRON_EXISTS2=$(crontab -l 2>/dev/null | grep -F "${CRON_JOB2}")

        if [[ -z "${CRON_EXISTS1}" ]] || [[ -z "${CRON_EXISTS2}" ]]; then
            {
                crontab -l 2>/dev/null
                [[ -z "${CRON_EXISTS1}" ]] && echo "${CRON_JOB1}"
                [[ -z "${CRON_EXISTS2}" ]] && echo "${CRON_JOB2}"
            } | crontab -
        fi
EOF

    sleep 2
  } || trata_erro "config_cron_instancia"
}

# Configura Nginx para a nova instância
config_nginx_instancia() {
  banner
  printf "${WHITE} >> Configurando nginx ${BLUE}frontend${WHITE}...\n"
  echo
  {
    frontend_hostname=$(echo "${nova_subdominio_frontend/https:\/\//}")
    frontend_hostname=${frontend_hostname%%/*}
    sudo su - root <<EOF
cat > /etc/nginx/sites-available/${nova_empresa}-frontend << 'END'
server {
  server_name ${frontend_hostname};
  location / {
    proxy_pass http://127.0.0.1:${nova_frontend_port};
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
END
ln -s /etc/nginx/sites-available/${nova_empresa}-frontend /etc/nginx/sites-enabled
EOF

    sleep 2

    banner
    printf "${WHITE} >> Configurando Nginx ${BLUE}backend${WHITE}...\n"
    echo
    backend_hostname=$(echo "${nova_subdominio_backend/https:\/\//}")
    backend_hostname=${backend_hostname%%/*}
    sudo su - root <<EOF
cat > /etc/nginx/sites-available/${nova_empresa}-backend << 'END'
upstream backend_${nova_empresa} {
        server 127.0.0.1:${nova_backend_port};
        keepalive 32;
    }
server {
  server_name ${backend_hostname};
  location / {
    proxy_pass http://backend_${nova_empresa};
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
ln -s /etc/nginx/sites-available/${nova_empresa}-backend /etc/nginx/sites-enabled
EOF

    sleep 2

    banner
    printf "${WHITE} >> Testando configuração do Nginx...\n"
    echo
    sudo nginx -t && sudo systemctl reload nginx

    sleep 2

    banner
    printf "${WHITE} >> Emitindo SSL do ${nova_subdominio_backend}...\n"
    echo
    backend_domain=$(echo "${nova_subdominio_backend/https:\/\//}")
    backend_domain=${backend_domain%%/*}
    sudo su - root <<EOF
    certbot -m ${email_deploy} \
            --nginx \
            --agree-tos \
            -n \
            -d ${backend_domain}
EOF

    sleep 2

    banner
    printf "${WHITE} >> Emitindo SSL do ${nova_subdominio_frontend}...\n"
    echo
    frontend_domain=$(echo "${nova_subdominio_frontend/https:\/\//}")
    frontend_domain=${frontend_domain%%/*}
    sudo su - root <<EOF
    certbot -m ${email_deploy} \
            --nginx \
            --agree-tos \
            -n \
            -d ${frontend_domain}
EOF

    sleep 2
  } || trata_erro "config_nginx_instancia"
}

# Configura Traefik para a nova instância
config_traefik_instancia() {
  {
    subdominio_backend_clean=$(echo "${nova_subdominio_backend/https:\/\//}")
    subdominio_backend_clean=${subdominio_backend_clean%%/*}
    subdominio_frontend_clean=$(echo "${nova_subdominio_frontend/https:\/\//}")
    subdominio_frontend_clean=${subdominio_frontend_clean%%/*}
    
    sudo su - root <<EOF
cat > /etc/traefik/conf.d/routers-${nova_empresa}-backend.toml << 'END'
[http.routers]
  [http.routers.backend-${nova_empresa}]
    rule = "Host(\`${subdominio_backend_clean}\`)"
    service = "backend-${nova_empresa}"
    entryPoints = ["web"]
    middlewares = ["https-redirect-${nova_empresa}"]

  [http.routers.backend-${nova_empresa}-secure]
    rule = "Host(\`${subdominio_backend_clean}\`)"
    service = "backend-${nova_empresa}"
    entryPoints = ["websecure"]
    [http.routers.backend-${nova_empresa}-secure.tls]
      certResolver = "letsencryptresolver"

[http.services]
  [http.services.backend-${nova_empresa}]
    [http.services.backend-${nova_empresa}.loadBalancer]
      [[http.services.backend-${nova_empresa}.loadBalancer.servers]]
        url = "http://127.0.0.1:${nova_backend_port}"

[http.middlewares]
  [http.middlewares.https-redirect-${nova_empresa}.redirectScheme]
    scheme = "https"
    permanent = true
END
EOF

    sleep 2

    sudo su - root <<EOF
cat > /etc/traefik/conf.d/routers-${nova_empresa}-frontend.toml << 'END'
[http.routers]
  [http.routers.frontend-${nova_empresa}]
    rule = "Host(\`${subdominio_frontend_clean}\`)"
    service = "frontend-${nova_empresa}"
    entryPoints = ["web"]
    middlewares = ["https-redirect-${nova_empresa}"]

  [http.routers.frontend-${nova_empresa}-secure]
    rule = "Host(\`${subdominio_frontend_clean}\`)"
    service = "frontend-${nova_empresa}"
    entryPoints = ["websecure"]
    [http.routers.frontend-${nova_empresa}-secure.tls]
      certResolver = "letsencryptresolver"

[http.services]
  [http.services.frontend-${nova_empresa}]
    [http.services.frontend-${nova_empresa}.loadBalancer]
      [[http.services.frontend-${nova_empresa}.loadBalancer.servers]]
        url = "http://127.0.0.1:${nova_frontend_port}"

[http.middlewares]
  [http.middlewares.https-redirect-${nova_empresa}.redirectScheme]
    scheme = "https"
    permanent = true
END
EOF

    sleep 2
    
    sudo systemctl restart traefik.service
    sleep 2
  } || trata_erro "config_traefik_instancia"
}

# Ajusta latência
config_latencia_instancia() {
  banner
  printf "${WHITE} >> Reduzindo Latência...\n"
  echo
  {
    subdominio_backend_clean=$(echo "${nova_subdominio_backend/https:\/\//}")
    subdominio_backend_clean=${subdominio_backend_clean%%/*}
    subdominio_frontend_clean=$(echo "${nova_subdominio_frontend/https:\/\//}")
    subdominio_frontend_clean=${subdominio_frontend_clean%%/*}
    
    sudo su - root <<EOF
cat >> /etc/hosts << 'END'
127.0.0.1   ${subdominio_backend_clean}
127.0.0.1   ${subdominio_frontend_clean}
END
EOF

    sleep 2

    sudo su - deploy <<'RESTARTPM2'
  if [ -d /usr/local/n/versions/node/20.19.4/bin ]; then
    export PATH=/usr/local/n/versions/node/20.19.4/bin:/usr/bin:/usr/local/bin:$PATH
  else
    export PATH=/usr/bin:/usr/local/bin:$PATH
  fi
  pm2 restart ${nova_empresa}-backend ${nova_empresa}-frontend
RESTARTPM2

    sleep 2
  } || trata_erro "config_latencia_instancia"
}

# Finaliza a instalação e mostra dados de acesso
fim_instalacao_instancia() {
  banner
  printf "   ${GREEN} >> Instalação concluída!${WHITE}\n"
  echo
  printf "   ${WHITE}Backend: ${BLUE}${nova_subdominio_backend}${WHITE}\n"
  printf "   ${WHITE}Frontend: ${BLUE}${nova_subdominio_frontend}${WHITE}\n"
  echo
  printf "   ${WHITE}Usuário ${BLUE}admin@multi100.com.br${WHITE}\n"
  printf "   ${WHITE}Senha   ${BLUE}adminpro${WHITE}\n"
  echo
  printf "   ${WHITE}Empresa: ${BLUE}${nova_empresa}${WHITE}\n"
  printf "   ${WHITE}Porta Backend: ${BLUE}${nova_backend_port}${WHITE}\n"
  printf "   ${WHITE}Porta Frontend: ${BLUE}${nova_frontend_port}${WHITE}\n"
  printf "   ${WHITE}Porta Redis: ${BLUE}${nova_redis_port}${WHITE}\n"
  echo
  printf "${WHITE}>> Aperte qualquer tecla para finalizar...${WHITE}\n"
  read -p ""
  echo
}

# Função principal
main() {
  solicitar_dados_instancia
  solicitar_dados_adicionais
  
  if ! verificar_conflitos; then
    printf "${RED} >> Instalação cancelada devido a conflitos.${WHITE}\n"
    exit 1
  fi
  
  verificar_dns_instancia
  
  salvar_variaveis_instancia
  verificar_e_instalar_docker
  instalar_redis_docker
  
  # Verificar dependências do sistema
  verificar_dependencias_sistema
  
  # Criar banco de dados
  cria_banco_instancia
  
  # Instalar Git se necessário
  if ! command -v git >/dev/null 2>&1; then
    banner
    printf "${WHITE} >> Instalando Git...\n"
    apt install -y git
    sleep 2
  fi
  
  # Baixar código
  baixa_codigo_instancia
  
  # Instalar backend
  instala_backend_instancia
  
  # Instalar frontend
  instala_frontend_instancia
  
  # Configurar cron
  config_cron_instancia
  
  # Configurar proxy
  if [ "${proxy}" == "nginx" ]; then
    config_nginx_instancia
  elif [ "${proxy}" == "traefik" ]; then
    config_traefik_instancia
  fi
  
  # Configurar latência
  config_latencia_instancia
  
  # Finalizar
  fim_instalacao_instancia
}

# Executar função principal
main
