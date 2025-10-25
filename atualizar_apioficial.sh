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

# Carregar variáveis
carregar_variaveis() {
  if [ -f $ARQUIVO_VARIAVEIS ]; then
    source $ARQUIVO_VARIAVEIS
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
    printf "${RED} >> ERRO: API Oficial não está instalada!${WHITE}\n"
    printf "${RED} >> Diretório /home/deploy/${empresa}/api_oficial não encontrado.${WHITE}\n"
    echo
    printf "${YELLOW} >> Execute primeiro o script de instalação da API Oficial.${WHITE}\n"
    echo
    sleep 5
    exit 1
  fi
  
  # Verificar se o processo PM2 está rodando (como usuário deploy)
  pm2_status=$(sudo su - deploy -c "pm2 list | grep -q 'api_oficial' && echo 'running' || echo 'not_running'")
  
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

# Reiniciar API Oficial no PM2
reiniciar_apioficial() {
  banner
  printf "${WHITE} >> Reiniciando API Oficial no PM2...\n"
  echo
  {
    sudo su - deploy <<EOF
    # Parar a API Oficial se estiver rodando
    pm2 stop api_oficial 2>/dev/null || true
    
    # Iniciar a API Oficial
    pm2 restart api_oficial
    
    # Salvar configuração do PM2
    pm2 save
    
    printf "${GREEN} >> API Oficial reiniciada com sucesso!${WHITE}\n"
    sleep 2
EOF
  } || trata_erro "reiniciar_apioficial"
}

# Função principal
main() {
  carregar_variaveis
  verificar_instalacao_apioficial
  atualizar_codigo_apioficial
  reiniciar_apioficial
  
  banner
  printf "${GREEN} >> Atualização da API Oficial concluída com sucesso!${WHITE}\n"
  echo
  printf "${WHITE} >> API Oficial atualizada e rodando na porta: ${YELLOW}${default_apioficial_port}${WHITE}\n"
  echo
  sleep 5
}

# Executar função principal
main
