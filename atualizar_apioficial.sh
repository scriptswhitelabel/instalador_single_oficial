#!/bin/bash

GREEN='\033[1;32m'
BLUE='\033[1;34m'
WHITE='\033[1;37m'
RED='\033[1;31m'
YELLOW='\033[1;33m'

# Variaveis Padrão
ARCH=$(uname -m)
UBUNTU_VERSION=$(lsb_release -sr)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALADOR_DIR="$SCRIPT_DIR"
# Caminho absoluto do VARIAVEIS da instância escolhida
ARQUIVO_VARIAVEIS=""
default_apioficial_port=6000

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

# Banner
banner() {
  clear
  printf "${BLUE}"
  echo "╔══════════════════════════════════════════════════════════════╗"
  echo "║                    ATUALIZADOR API OFICIAL                   ║"
  echo "║                                                              ║"
  echo "║                    MultiFlow System                          ║"
  echo "╚══════════════════════════════════════════════════════════════╝"
  printf "${WHITE}"
  echo
}

# Detectar instâncias (mesma lógica do instalador_single.sh)
detectar_instancias_instaladas() {
  local instancias=()
  local nomes_empresas=()
  local temp_empresa=""

  if [ -f "${INSTALADOR_DIR}/VARIAVEIS_INSTALACAO" ]; then
    local empresa_original="${empresa:-}"
    local subdominio_backend_original="${subdominio_backend:-}"
    local subdominio_frontend_original="${subdominio_frontend:-}"
    # shellcheck source=/dev/null
    source "${INSTALADOR_DIR}/VARIAVEIS_INSTALACAO" 2>/dev/null
    temp_empresa="${empresa:-}"
    if [ -n "${temp_empresa}" ] && [ -d "/home/deploy/${temp_empresa}/backend" ] && [ -d "/home/deploy/${temp_empresa}/api_oficial" ]; then
      instancias+=("${INSTALADOR_DIR}/VARIAVEIS_INSTALACAO")
      nomes_empresas+=("${temp_empresa}")
    fi
    empresa="${empresa_original}"
    subdominio_backend="${subdominio_backend_original}"
    subdominio_frontend="${subdominio_frontend_original}"
  fi

  if [ -d "${INSTALADOR_DIR}" ]; then
    shopt -s nullglob
    for arquivo_instancia in "${INSTALADOR_DIR}"/VARIAVEIS_INSTALACAO_INSTANCIA_*; do
      if [ -f "$arquivo_instancia" ]; then
        local empresa_original="${empresa:-}"
        local subdominio_backend_original="${subdominio_backend:-}"
        local subdominio_frontend_original="${subdominio_frontend:-}"
        # shellcheck source=/dev/null
        source "$arquivo_instancia" 2>/dev/null
        temp_empresa="${empresa:-}"
        if [ -n "${temp_empresa}" ] && [ -d "/home/deploy/${temp_empresa}/backend" ] && [ -d "/home/deploy/${temp_empresa}/api_oficial" ]; then
          instancias+=("$arquivo_instancia")
          nomes_empresas+=("${temp_empresa}")
        fi
        empresa="${empresa_original}"
        subdominio_backend="${subdominio_backend_original}"
        subdominio_frontend="${subdominio_frontend_original}"
      fi
    done
    shopt -u nullglob
  fi

  declare -g INSTANCIAS_DETECTADAS=("${instancias[@]}")
  declare -g NOMES_EMPRESAS_DETECTADAS=("${nomes_empresas[@]}")
}

selecionar_instancia_apioficial() {
  banner
  printf "${WHITE} >> Qual instância terá a API Oficial atualizada?\n\n"
  detectar_instancias_instaladas
  local total_instancias=${#INSTANCIAS_DETECTADAS[@]}

  if [ "$total_instancias" -eq 0 ]; then
    printf "${RED} >> Nenhuma instância com API Oficial instalada foi encontrada.${WHITE}\n"
    printf "${YELLOW} >> Instale a API Oficial em Ferramentas ou no menu principal antes de atualizar.${WHITE}\n"
    sleep 3
    exit 1
  elif [ "$total_instancias" -eq 1 ]; then
    printf "${GREEN} >> Instância: ${BLUE}${NOMES_EMPRESAS_DETECTADAS[0]}${WHITE}\n\n"
    ARQUIVO_VARIAVEIS="${INSTANCIAS_DETECTADAS[0]}"
    # shellcheck source=/dev/null
    source "$ARQUIVO_VARIAVEIS"
    sleep 1
    return 0
  fi

  printf "${WHITE}═══════════════════════════════════════════════════════════\n"
  printf "  INSTÂNCIAS\n"
  printf "═══════════════════════════════════════════════════════════${WHITE}\n\n"
  local index=1
  for i in "${!NOMES_EMPRESAS_DETECTADAS[@]}"; do
    local empresa_nome="${NOMES_EMPRESAS_DETECTADAS[$i]}"
    local arquivo_instancia="${INSTANCIAS_DETECTADAS[$i]}"
    local empresa_original="${empresa:-}"
    local subdominio_backend_original="${subdominio_backend:-}"
    local subdominio_frontend_original="${subdominio_frontend:-}"
    # shellcheck source=/dev/null
    source "$arquivo_instancia" 2>/dev/null
    local tb="${subdominio_backend:-}"
    local tf="${subdominio_frontend:-}"
    empresa="${empresa_original}"
    subdominio_backend="${subdominio_backend_original}"
    subdominio_frontend="${subdominio_frontend_original}"
    printf "  [${BLUE}%s${WHITE}] %s\n" "$index" "$empresa_nome"
    [ -n "$tb" ] && printf "      Backend:  ${YELLOW}%s${WHITE}\n" "$tb"
    [ -n "$tf" ] && printf "      Frontend: ${YELLOW}%s${WHITE}\n" "$tf"
    echo
    index=$((index + 1))
  done
  printf "${YELLOW} >> Escolha a instância (1-%s):${WHITE}\n" "$total_instancias"
  read -r escolha_instancia
  if ! [[ "$escolha_instancia" =~ ^[0-9]+$ ]] || [ "$escolha_instancia" -lt 1 ] || [ "$escolha_instancia" -gt "$total_instancias" ]; then
    printf "${RED} >> Opção inválida.${WHITE}\n"
    exit 1
  fi
  local indice_selecionado=$((escolha_instancia - 1))
  ARQUIVO_VARIAVEIS="${INSTANCIAS_DETECTADAS[$indice_selecionado]}"
  # shellcheck source=/dev/null
  source "$ARQUIVO_VARIAVEIS"
  printf "${GREEN} >> Instância selecionada: ${BLUE}${empresa}${WHITE}\n\n"
  sleep 1
}

# Carregar variáveis
carregar_variaveis() {
  if [ -f "$ARQUIVO_VARIAVEIS" ]; then
    # shellcheck source=/dev/null
    source "$ARQUIVO_VARIAVEIS"
  else
    empresa="multiflow"
    nome_titulo="MultiFlow"
  fi
}

# Verificar se a API Oficial já está instalada
verificar_instalacao_apioficial() {
  banner
  printf "${WHITE} >> Verificando se a API Oficial já está instalada...\n"
  echo
  
  # Verificar se o diretório da API Oficial existe
  if [ ! -d "/home/deploy/${empresa}/api_oficial" ]; then
    printf "${RED} >> ERRO: API Oficial não está instalada nesta instância!${WHITE}\n"
    printf "${RED} >> Diretório /home/deploy/${empresa}/api_oficial não encontrado.${WHITE}\n"
    echo
    printf "${YELLOW} >> Execute primeiro o script de instalação da API Oficial para a empresa ${empresa}.${WHITE}\n"
    echo
    sleep 5
    exit 1
  fi
  
  # Verificar se o processo PM2 está rodando (como usuário deploy)
  pm2_status=$(sudo su - deploy -c "pm2 jlist 2>/dev/null | grep -qF 'api_oficial_${empresa}' && echo running || pm2 jlist 2>/dev/null | grep -qF '\"name\":\"api_oficial\"' && echo running || echo not_running")
  
  if [ "$pm2_status" = "not_running" ]; then
    printf "${RED} >> AVISO: API Oficial não está rodando no PM2!${WHITE}\n"
    printf "${YELLOW} >> Tentando iniciar a API Oficial...${WHITE}\n"
    echo
  else
    printf "${GREEN} >> API Oficial encontrada e rodando no PM2!${WHITE}\n"
    echo
  fi
  
  sleep 2
}

# Atualizar código da API Oficial
atualizar_codigo_apioficial() {
  banner
  printf "${WHITE} >> Atualizando código da API Oficial...\n"
  echo
  {
    sudo su - deploy <<EOF
cd /home/deploy/${empresa}

printf "${WHITE} >> Fazendo pull das atualizações...\n"
git reset --hard
git pull

cd /home/deploy/${empresa}/api_oficial

printf "${WHITE} >> Instalando dependências atualizadas...\n"
npm install

printf "${WHITE} >> Gerando Prisma...\n"
npx prisma generate

printf "${WHITE} >> Buildando aplicação...\n"
npm run build

printf "${WHITE} >> Executando migrações...\n"
npx prisma migrate deploy

printf "${WHITE} >> Gerando cliente Prisma...\n"
npx prisma generate client

printf "${GREEN} >> Código da API Oficial atualizado com sucesso!${WHITE}\n"
sleep 2
EOF
  } || trata_erro "atualizar_codigo_apioficial"
}

# Reiniciar API Oficial no PM2 (su -c garante o mesmo ambiente que pm2 list na verificação)
reiniciar_apioficial() {
  banner
  printf "${WHITE} >> Reiniciando API Oficial no PM2...\n"
  echo
  {
    sudo su - deploy -c "cd /home/deploy/${empresa}/api_oficial && (pm2 restart api_oficial_${empresa} 2>/dev/null || pm2 restart api_oficial 2>/dev/null || pm2 start dist/main.js --name api_oficial_${empresa}) && pm2 save"
  } || trata_erro "reiniciar_apioficial"
  printf "${GREEN} >> API Oficial reiniciada com sucesso!${WHITE}\n"
  echo
  sleep 2
}

# Função principal
main() {
  selecionar_instancia_apioficial
  carregar_variaveis
  verificar_instalacao_apioficial
  atualizar_codigo_apioficial
  reiniciar_apioficial
  
  banner
  printf "${GREEN} >> Atualização da API Oficial concluída com sucesso!${WHITE}\n"
  echo
  printf "${WHITE} >> Instância: ${YELLOW}${empresa}${WHITE}\n"
  printf "${WHITE} >> API Oficial atualizada e rodando na porta: ${YELLOW}${default_apioficial_port}${WHITE}\n"
  echo
  sleep 5
}

# Executar função principal
main
