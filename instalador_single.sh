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
# Modo Alta Performance: Redis, Postgres e PgBouncer via Docker (não instala nativos)
[ -f "ALTA_PERFORMANCE_MODE" ] && source ALTA_PERFORMANCE_MODE 2>/dev/null || true
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

banner() {
  printf " ${BLUE}"
  printf "\n\n"
  printf "██╗███╗   ██╗███████╗████████╗ █████╗ ██╗     ██╗     ███████╗██╗    ██╗██╗\n"
  printf "██║████╗  ██║██╔════╝╚══██╔══╝██╔══██╗██║     ██║     ██╔════╝██║    ██║██║\n"
  printf "██║██╔██╗ ██║███████    ██║   ███████║██║     ██║     ███████╗██║ █╗ ██║██║\n"
  printf "██║██║╚██╗██║╚════██║   ██║   ██╔══██║██║     ██║     ╚════██║██║███╗██║██║\n"
  printf "██║██║ ╚████║███████╗   ██║   ██║  ██║███████╗███████╗███████╗╚███╔███╔╝███████╗\n"
  printf "╚═╝╚═╝  ╚═══╝╚══════╝   ╚═╝   ╚═╝  ╚═╝╚══════╝╚══════╝╚══════╝ ╚══╝╚══╝ ╚══════╝\n"
  printf "                                INSTALADOR 7.0\n"
  printf "\n\n"
}

# Função para manipular erros e encerrar o script
trata_erro() {
  printf "${RED}Erro encontrado na etapa $1. Encerrando o script.${WHITE}\n"
  salvar_etapa "$1"
  exit 1
}

# Verificar conectividade de rede e DNS
verificar_conectividade() {
  printf "${WHITE} >> Verificando conectividade de rede...\n"
  
  # Verificar se consegue fazer ping no Google DNS
  if ! ping -c 1 -W 2 8.8.8.8 >/dev/null 2>&1; then
    printf "${RED} >> ERRO: Sem conectividade de rede (não consegue alcançar 8.8.8.8)${WHITE}\n"
    printf "${YELLOW} >> Verifique sua conexão de internet.${WHITE}\n"
    return 1
  fi
  
  # Verificar resolução DNS
  if ! ping -c 1 -W 2 google.com >/dev/null 2>&1; then
    printf "${RED} >> ERRO: Problema com resolução DNS${WHITE}\n"
    printf "${YELLOW} >> Verifique a configuração do DNS em /etc/resolv.conf${WHITE}\n"
    printf "${YELLOW} >> Você pode tentar:${WHITE}\n"
    printf "${YELLOW} >>   echo 'nameserver 8.8.8.8' >> /etc/resolv.conf${WHITE}\n"
    printf "${YELLOW} >>   echo 'nameserver 8.8.4.4' >> /etc/resolv.conf${WHITE}\n"
    return 1
  fi
  
  printf "${GREEN} >> Conectividade de rede OK!${WHITE}\n"
  return 0
}

# Tentar corrigir problemas de DNS
tentar_corrigir_dns() {
  printf "${WHITE} >> Tentando corrigir problemas de DNS...\n"
  
  # Adicionar Google DNS se não estiver presente
  if ! grep -q "8.8.8.8" /etc/resolv.conf 2>/dev/null; then
    printf "${WHITE} >> Adicionando Google DNS (8.8.8.8)...\n"
    echo "nameserver 8.8.8.8" >> /etc/resolv.conf
    echo "nameserver 8.8.4.4" >> /etc/resolv.conf
  fi
  
  # Tentar usar systemd-resolve se disponível
  if command -v systemd-resolve &> /dev/null; then
    systemd-resolve --flush-caches >/dev/null 2>&1 || true
  fi
  
  sleep 2
}

# Salvar variáveis
salvar_variaveis() {
  echo "subdominio_backend=${subdominio_backend}" >$ARQUIVO_VARIAVEIS
  echo "subdominio_frontend=${subdominio_frontend}" >>$ARQUIVO_VARIAVEIS
  echo "email_deploy=${email_deploy}" >>$ARQUIVO_VARIAVEIS
  echo "empresa=${empresa}" >>$ARQUIVO_VARIAVEIS
  echo "senha_deploy=${senha_deploy}" >>$ARQUIVO_VARIAVEIS
  # echo "subdominio_perfex=${subdominio_perfex}" >>$ARQUIVO_VARIAVEIS
  echo "senha_master=${senha_master}" >>$ARQUIVO_VARIAVEIS
  echo "nome_titulo=${nome_titulo}" >>$ARQUIVO_VARIAVEIS
  echo "numero_suporte=${numero_suporte}" >>$ARQUIVO_VARIAVEIS
  echo "facebook_app_id=${facebook_app_id}" >>$ARQUIVO_VARIAVEIS
  echo "facebook_app_secret=${facebook_app_secret}" >>$ARQUIVO_VARIAVEIS
  echo "github_token=${github_token}" >>$ARQUIVO_VARIAVEIS
  echo "repo_url=${repo_url}" >>$ARQUIVO_VARIAVEIS
  echo "proxy=${proxy}" >>$ARQUIVO_VARIAVEIS
  echo "backend_port=${backend_port}" >>$ARQUIVO_VARIAVEIS
  echo "frontend_port=${frontend_port}" >>$ARQUIVO_VARIAVEIS
  # Salvar versão (usar underscore se for "Mais Recente" para evitar problemas com espaços)
  local versao_para_salvar="${versao_instalacao}"
  if [ "${versao_instalacao}" = "Mais Recente" ] || [ "${versao_instalacao}" = "Mais_Recente" ]; then
    versao_para_salvar="Mais_Recente"
  fi
  echo "versao_instalacao=${versao_para_salvar}" >>$ARQUIVO_VARIAVEIS
  echo "commit_instalacao=${commit_instalacao}" >>$ARQUIVO_VARIAVEIS
  # Registro se a instalação foi em modo Alta Performance (Redis, Postgres e PgBouncer via Docker)
  echo "# Instalação em modo Alta Performance (1=sim, 0=não)" >>$ARQUIVO_VARIAVEIS
  echo "ALTA_PERFORMANCE=${ALTA_PERFORMANCE:-0}" >>$ARQUIVO_VARIAVEIS
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

# Salvar etapa concluída
salvar_etapa() {
  echo "$1" >$ARQUIVO_ETAPAS
}

# Carregar última etapa
carregar_etapa() {
  if [ -f $ARQUIVO_ETAPAS ]; then
    etapa=$(cat $ARQUIVO_ETAPAS)
    if [ -z "$etapa" ]; then
      etapa="0"
    fi
  else
    etapa="0"
  fi
}

# Resetar etapas e variáveis
resetar_instalacao() {
  rm -f $ARQUIVO_VARIAVEIS $ARQUIVO_ETAPAS
  printf "${GREEN} >> Instalação resetada! Iniciando uma nova instalação...${WHITE}\n"
  sleep 2
  instalacao_base
}

# Pergunta se deseja continuar ou recomeçar
verificar_arquivos_existentes() {
  if [ -f $ARQUIVO_VARIAVEIS ] && [ -f $ARQUIVO_ETAPAS ]; then
    banner
    printf "${YELLOW} >> Dados de instalação anteriores detectados.\n"
    echo
    carregar_etapa
    if [ "$etapa" -eq 21 ]; then
      printf "${WHITE}>> Instalação já concluída.\n"
      printf "${WHITE}>> Deseja resetar as etapas e começar do zero? (S/N): ${WHITE}\n"
      echo
      read -p "> " reset_escolha
      echo
      reset_escolha=$(echo "${reset_escolha}" | tr '[:lower:]' '[:upper:]')
      if [ "$reset_escolha" == "S" ]; then
        resetar_instalacao
      else
        printf "${GREEN} >> Voltando para o menu principal...${WHITE}\n"
        sleep 2
        menu
      fi
    elif [ "$etapa" -lt 21 ]; then
      printf "${YELLOW} >> Instalação Incompleta Detectada na etapa $etapa. \n"
      printf "${WHITE} >> Deseja continuar de onde parou? (S/N): ${WHITE}\n"
      echo
      read -p "> " escolha
      echo
      escolha=$(echo "${escolha}" | tr '[:lower:]' '[:upper:]')
      if [ "$escolha" == "S" ]; then
        instalacao_base
      else
        printf "${GREEN} >> Voltando ao menu principal...${WHITE}\n"
        printf "${WHITE} >> Caso deseje resetar as etapas, apague os arquivos ETAPAS_INSTALAÇÃO da pasta root...${WHITE}\n"
        sleep 5
        menu
      fi
    fi
  else
    instalacao_base
  fi
}

# Função para instalar API WhatsMeow
instalar_whatsmeow() {
  banner
  printf "${YELLOW}══════════════════════════════════════════════════════════════════${WHITE}\n"
  printf "${YELLOW}⚠️  ATENÇÃO:${WHITE}\n"
  echo
  printf "${WHITE}   A WhatsMeow é uma API Alternativa à Bayles, muito estável.${WHITE}\n"
  printf "${WHITE}   Ela está disponível apenas para a versão do MultiFlow PRO${WHITE}\n"
  printf "${WHITE}   - A partir da Versão ${BLUE}6.4.4${WHITE}.${WHITE}\n"
  echo
  printf "${YELLOW}══════════════════════════════════════════════════════════════════${WHITE}\n"
  echo
  printf "${WHITE}   Deseja continuar? (S/N):${WHITE}\n"
  echo
  read -p "> " confirmacao_whatsmeow
  confirmacao_whatsmeow=$(echo "${confirmacao_whatsmeow}" | tr '[:lower:]' '[:upper:]')
  echo
  
  if [ "${confirmacao_whatsmeow}" != "S" ]; then
    printf "${GREEN} >> Operação cancelada. Voltando ao menu de ferramentas...${WHITE}\n"
    sleep 2
    return
  fi
  
  banner
  printf "${WHITE} >> Digite o TOKEN de autorização do GitHub para acesso ao repositório multiflow-pro:${WHITE}\n"
  echo
  read -p "> " TOKEN_AUTH
  
  # Verificar se o token foi informado
  if [ -z "$TOKEN_AUTH" ]; then
    printf "${RED}❌ ERRO: Token de autorização não pode estar vazio.${WHITE}\n"
    sleep 2
    return
  fi
  
  printf "${BLUE} >> Token de autorização recebido. Validando...${WHITE}\n"
  echo
  
  # Validar o token usando a mesma lógica do atualizador_pro.sh
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
    
    # Executar o instalador WhatsMeow
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    WHATSMEOW_SCRIPT="${SCRIPT_DIR}/instalador_whatsmeow.sh"
    
    if [ -f "$WHATSMEOW_SCRIPT" ]; then
      printf "${GREEN} >> Executando Instalador API WhatsMeow...${WHITE}\n"
      echo
      bash "$WHATSMEOW_SCRIPT"
      echo
      printf "${GREEN} >> Pressione Enter para voltar ao menu de ferramentas...${WHITE}\n"
      read -r
    else
      printf "${RED} >> Erro: Arquivo ${WHATSMEOW_SCRIPT} não encontrado!${WHITE}\n"
      printf "${RED} >> Certifique-se de que o arquivo instalador_whatsmeow.sh está no mesmo diretório do instalador.${WHITE}\n"
      sleep 3
    fi
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
    printf "${YELLOW}   Para solicitar acesso ou analisar a disponibilidade,${WHITE}\n"
    printf "${YELLOW}   entre em contato com o suporte:${WHITE}\n"
    echo
    printf "${BLUE}   📱 WhatsApp:${WHITE}\n"
    printf "${WHITE}   • https://wa.me/5518996755165${WHITE}\n"
    printf "${WHITE}   • https://wa.me/558499418159${WHITE}\n"
    echo
    printf "${RED}   Instalação interrompida.${WHITE}\n"
    printf "${RED}══════════════════════════════════════════════════════════════════${WHITE}\n"
    echo
    printf "${GREEN} >> Pressione Enter para voltar ao menu de ferramentas...${WHITE}\n"
    read -r
  fi
}

# Menu de Ferramentas
menu_ferramentas() {
  while true; do
    banner
    printf "${WHITE} Selecione abaixo a ferramenta desejada: \n"
    echo
    printf "   [${BLUE}1${WHITE}] Instalador RabbitMQ\n"
    printf "   [${BLUE}2${WHITE}] Instalar Push Notifications\n"
    printf "   [${BLUE}3${WHITE}] Instalar API WhatsMeow\n"
    printf "   [${BLUE}4${WHITE}] Roolback Versão\n"
    printf "   [${BLUE}5${WHITE}] Instalar Nova Instância\n"
    printf "   [${BLUE}6${WHITE}] Agendar Backup Diário do Banco Alta Performance\n"
    printf "   [${BLUE}0${WHITE}] Voltar ao Menu Principal\n"
    echo
    read -p "> " option_tools
    case "${option_tools}" in
    1)
      SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
      RABBIT_SCRIPT="${SCRIPT_DIR}/tools/instalador_rabbit.sh"
      if [ -f "$RABBIT_SCRIPT" ]; then
        printf "${GREEN} >> Executando Instalador RabbitMQ...${WHITE}\n"
        echo
        bash "$RABBIT_SCRIPT"
        echo
        printf "${GREEN} >> Pressione Enter para voltar ao menu de ferramentas...${WHITE}\n"
        read -r
      else
        printf "${RED} >> Erro: Arquivo ${RABBIT_SCRIPT} não encontrado!${WHITE}\n"
        sleep 3
      fi
      ;;
    2)
      SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
      PUSH_SCRIPT="${SCRIPT_DIR}/tools/instalar_push.sh"
      if [ -f "$PUSH_SCRIPT" ]; then
        printf "${GREEN} >> Executando Instalador Push Notifications...${WHITE}\n"
        echo
        bash "$PUSH_SCRIPT"
        echo
        printf "${GREEN} >> Pressione Enter para voltar ao menu de ferramentas...${WHITE}\n"
        read -r
      else
        printf "${RED} >> Erro: Arquivo ${PUSH_SCRIPT} não encontrado!${WHITE}\n"
        sleep 3
      fi
      ;;
    3)
      instalar_whatsmeow
      ;;
    4)
      SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
      ROLLBACK_SCRIPT="${SCRIPT_DIR}/tools/roolback_versao.sh"
      if [ -f "$ROLLBACK_SCRIPT" ]; then
        printf "${GREEN} >> Executando Roolback Versão...${WHITE}\n"
        echo
        bash "$ROLLBACK_SCRIPT"
        echo
        printf "${GREEN} >> Pressione Enter para voltar ao menu de ferramentas...${WHITE}\n"
        read -r
      else
        printf "${RED} >> Erro: Arquivo ${ROLLBACK_SCRIPT} não encontrado!${WHITE}\n"
        sleep 3
      fi
      ;;
    5)
      SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
      INSTANCIAS_SCRIPT="${SCRIPT_DIR}/tools/instalador_instancias.sh"
      if [ -f "$INSTANCIAS_SCRIPT" ]; then
        printf "${GREEN} >> Executando Instalador de Novas Instâncias...${WHITE}\n"
        echo
        bash "$INSTANCIAS_SCRIPT"
        echo
        printf "${GREEN} >> Pressione Enter para voltar ao menu de ferramentas...${WHITE}\n"
        read -r
      else
        printf "${RED} >> Erro: Arquivo ${INSTANCIAS_SCRIPT} não encontrado!${WHITE}\n"
        sleep 3
      fi
      ;;
    6)
      SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
      BACKUP_SCRIPT="${SCRIPT_DIR}/tools/agendar_backup_bd_docker.sh"
      if [ -f "$BACKUP_SCRIPT" ]; then
        chmod 775 "$BACKUP_SCRIPT"
        bash "$BACKUP_SCRIPT"
        echo
        printf "${GREEN} >> Pressione Enter para voltar ao menu de ferramentas...${WHITE}\n"
        read -r
      else
        printf "${RED} >> Erro: Arquivo ${BACKUP_SCRIPT} não encontrado!${WHITE}\n"
        sleep 3
      fi
      ;;
    0)
      return
      ;;
    *)
      printf "${RED}Opção inválida. Tente novamente.${WHITE}"
      sleep 2
      ;;
    esac
  done
}

# Menu principal
menu() {
  while true; do
    banner
    printf "${WHITE} Selecione abaixo a opção desejada: \n"
    echo
    printf "   [${BLUE}1${WHITE}] Instalar ${nome_titulo}\n"
    printf "   [${BLUE}2${WHITE}] Atualizar ${nome_titulo}\n"
    printf "   [${BLUE}3${WHITE}] Instalar Transcrição de Audio Nativa\n"
    printf "   [${BLUE}4${WHITE}] Instalar API Oficial\n"
    printf "   [${BLUE}5${WHITE}] Atualizar API Oficial\n"
    printf "   [${BLUE}6${WHITE}] Migrar para Multiflow-PRO\n"
    printf "   [${BLUE}7${WHITE}] Instalação Alta Performance (Redis, Postgres, PgBouncer)\n"
    printf "   [${BLUE}10${WHITE}] Ferramentas\n"
    printf "   [${BLUE}0${WHITE}] Sair\n"
    echo
    read -p "> " option
    case "${option}" in
    1)
      verificar_arquivos_existentes
      ;;
    2)
      atualizar_base
      ;;
    3)
      instalar_transcricao_audio_nativa
      ;;
    4)
      instalar_api_oficial
      ;;
    5)
      atualizar_api_oficial
      ;;
    6)
      migrar_multiflow_pro
      ;;
    7)
      exec_instalador_alta_performance
      ;;
    10)
      menu_ferramentas
      ;;
    0)
      sair
      ;;
    *)
      printf "${RED}Opção inválida. Tente novamente.${WHITE}"
      sleep 2
      ;;
    esac
  done
}

# Etapa de instalação
instalacao_base() {
  carregar_etapa
  if [ "$etapa" == "0" ]; then
    questoes_dns_base || trata_erro "questoes_dns_base"
    verificar_dns_base || trata_erro "verificar_dns_base"
    questoes_variaveis_base || trata_erro "questoes_variaveis_base"
    define_proxy_base || trata_erro "define_proxy_base"
    define_portas_base || trata_erro "define_portas_base"
    confirma_dados_instalacao_base || trata_erro "confirma_dados_instalacao_base"
    salvar_variaveis || trata_erro "salvar_variaveis"
    salvar_etapa 1
  fi
  if [ "$etapa" -le "1" ]; then
    atualiza_vps_base || trata_erro "atualiza_vps_base"
    salvar_etapa 2
  fi
  if [ "$etapa" -le "2" ]; then
    cria_deploy_base || trata_erro "cria_deploy_base"
    salvar_etapa 3
  fi
  if [ "$etapa" -le "3" ]; then
    config_timezone_base || trata_erro "config_timezone_base"
    salvar_etapa 4
  fi
  if [ "$etapa" -le "4" ]; then
    config_firewall_base || trata_erro "config_firewall_base"
    salvar_etapa 5
  fi
  if [ "$etapa" -le "5" ]; then
    instala_puppeteer_base || trata_erro "instala_puppeteer_base"
    salvar_etapa 6
  fi
  if [ "$etapa" -le "6" ]; then
    instala_ffmpeg_base || trata_erro "instala_ffmpeg_base"
    salvar_etapa 7
  fi
  if [ "$etapa" -le "7" ]; then
    if [ "${ALTA_PERFORMANCE}" = "1" ]; then
      printf "${GREEN} >> Modo Alta Performance: pulando instalação do Postgres nativo (uso de container).${WHITE}\n"
      salvar_etapa 8
    else
      instala_postgres_base || trata_erro "instala_postgres_base"
      salvar_etapa 8
    fi
  fi
  if [ "$etapa" -le "8" ]; then
    instala_node_base || trata_erro "instala_node_base"
    salvar_etapa 9
  fi
  if [ "$etapa" -le "9" ]; then
    if [ "${ALTA_PERFORMANCE}" = "1" ]; then
      printf "${GREEN} >> Modo Alta Performance: pulando instalação do Redis nativo (uso de container).${WHITE}\n"
      salvar_etapa 10
    else
      instala_redis_base || trata_erro "instala_redis_base"
      salvar_etapa 10
    fi
  fi
  if [ "$etapa" -le "10" ]; then
    instala_pm2_base || trata_erro "instala_pm2_base"
    salvar_etapa 11
  fi
  if [ "$etapa" -le "11" ]; then
    if [ "${proxy}" == "nginx" ]; then
      instala_nginx_base || trata_erro "instala_nginx_base"
      salvar_etapa 12
    elif [ "${proxy}" == "traefik" ]; then
      instala_traefik_base || trata_erro "instala_traefik_base"
      salvar_etapa 12
    fi
  fi
  if [ "$etapa" -le "12" ]; then
    if [ "${ALTA_PERFORMANCE}" = "1" ]; then
      printf "${GREEN} >> Modo Alta Performance: banco já criado pelo container Postgres.${WHITE}\n"
      salvar_etapa 13
    else
      cria_banco_base || trata_erro "cria_banco_base"
      salvar_etapa 13
    fi
  fi
  if [ "$etapa" -le "13" ]; then
    instala_git_base || trata_erro "instala_git_base"
    salvar_etapa 14
  fi
  if [ "$etapa" -le "14" ]; then
    codifica_clone_base || trata_erro "codifica_clone_base"
    baixa_codigo_base || trata_erro "baixa_codigo_base"
    salvar_etapa 15
  fi
  if [ "$etapa" -le "15" ]; then
    instala_backend_base || trata_erro "instala_backend_base"
    salvar_etapa 16
  fi
  if [ "$etapa" -le "16" ]; then
    instala_frontend_base || trata_erro "instala_frontend_base"
    salvar_etapa 17
  fi
  if [ "$etapa" -le "17" ]; then
    config_cron_base || trata_erro "config_cron_base"
    salvar_etapa 18
  fi
  if [ "$etapa" -le "18" ]; then
    if [ "${proxy}" == "nginx" ]; then
      config_nginx_base || trata_erro "config_nginx_base"
      salvar_etapa 19
    elif [ "${proxy}" == "traefik" ]; then
      config_traefik_base || trata_erro "config_traefik_base"
      salvar_etapa 19
    fi
  fi
  if [ "$etapa" -le "19" ]; then
    config_latencia_base || trata_erro "config_latencia_base"
    salvar_etapa 20
  fi
  if [ "$etapa" -le "20" ]; then
    fim_instalacao_base || trata_erro "fim_instalacao_base"
    salvar_etapa 21
  fi
}

# Função para detectar e listar todas as instâncias instaladas
detectar_instancias_instaladas() {
  local instancias=()
  local nomes_empresas=()
  local temp_empresa=""
  local temp_subdominio_backend=""
  local temp_subdominio_frontend=""
  
  # Verificar instalação base (arquivo VARIAVEIS_INSTALACAO)
  INSTALADOR_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
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

# Etapa de instalação
atualizar_base() {
  # Verificar e selecionar instância para atualizar
  if ! selecionar_instancia_atualizar; then
    printf "${RED} >> Erro ao selecionar instância. Voltando ao menu principal...${WHITE}\n"
    sleep 2
    menu
    return
  fi
  
  backup_app_atualizar || trata_erro "backup_app_atualizar"
  instala_ffmpeg_base || trata_erro "instala_ffmpeg_base"
  config_cron_base || trata_erro "config_cron_base"
  baixa_codigo_atualizar || trata_erro "baixa_codigo_atualizar"
}

sair() {
  exit 0
}

################################################################
#                         INSTALAÇÃO                           #
################################################################

# Questões base
questoes_dns_base() {
  # ARMAZENA URL BACKEND
  banner
  printf "${WHITE} >> Insira a URL do Backend: \n"
  echo
  read -p "> " subdominio_backend
  echo
  # ARMAZENA URL FRONTEND
  banner
  printf "${WHITE} >> Insira a URL do Frontend: \n"
  echo
  read -p "> " subdominio_frontend
  echo
}

# Valida se o domínio ou subdomínio está apontado para o IP da VPS
verificar_dns_base() {
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

    cname_target=$(dig +short CNAME ${domain})

    if [ -n "${cname_target}" ]; then
      resolved_ip=$(dig +short ${cname_target})
    else
      resolved_ip=$(dig +short ${domain})
    fi

    if [ "${resolved_ip}" != "${ip_atual}" ]; then
      echo "O domínio ${domain} (resolvido para ${resolved_ip}) não está apontando para o IP público atual (${ip_atual})."
      subdominios_incorretos+="${domain} "
      sleep 2
    fi
  }
  verificar_dns ${subdominio_backend}
  verificar_dns ${subdominio_frontend}
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
      printf "${GREEN} >> Retornando ao menu principal...${WHITE}\n"
      sleep 2
      menu
      return 0
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

questoes_variaveis_base() {
  # DEFINE EMAIL
  banner
  printf "${WHITE} >> Digite o seu melhor email: \n"
  echo
  read -p "> " email_deploy
  echo
  # DEFINE NOME DA EMPRESA
  banner
  printf "${WHITE} >> Digite o nome da sua empresa (Letras minusculas e sem espaço): \n"
  echo
  read -p "> " empresa
  echo
  # DEFINE SENHA BASE
  banner
  printf "${WHITE} >> Insira a senha para o usuario Deploy, Redis e Banco de Dados ${RED}IMPORTANTE${WHITE}: Não utilizar caracteres especiais\n"
  echo
  read -p "> " senha_deploy
  echo
  # ARMAZENA URL BACKEND
  # banner
  # printf "${WHITE} >> Insira a URL do PerfexCRM: \n"
  # echo
  # read -p "> " subdominio_perfex
  echo
  # DEFINE SENHA MASTER
  banner
  printf "${WHITE} >> Insira a senha para o MASTER: \n"
  echo
  read -p "> " senha_master
  echo
  # DEFINE TITULO DO APP NO NAVEGADOR
  banner
  printf "${WHITE} >> Insira o Titulo da Aplicação (Permitido Espaço): \n"
  echo
  read -p "> " nome_titulo
  echo
  # DEFINE TELEFONE SUPORTE
  banner
  printf "${WHITE} >> Digite o numero de telefone para suporte: \n"
  echo
  read -p "> " numero_suporte
  echo
  # DEFINE FACEBOOK_APP_ID
  banner
  printf "${WHITE} >> Digite o FACEBOOK_APP_ID caso tenha: \n"
  echo
  read -p "> " facebook_app_id
  echo
  # DEFINE FACEBOOK_APP_SECRET
  banner
  printf "${WHITE} >> Digite o FACEBOOK_APP_SECRET caso tenha: \n"
  echo
  read -p "> " facebook_app_secret
  echo
  # DEFINE TOKEN GITHUB
  banner
  printf "${WHITE} >> Digite seu TOKEN de acesso pessoal do GitHub: \n"
  printf "${WHITE} >> Passo a Passo para gerar o seu TOKEN no link ${BLUE}https://bit.ly/token-github ${WHITE} \n"
  echo
  read -p "> " github_token
  echo
  # DEFINE LINK REPO GITHUB
  banner
  printf "${WHITE} >> Digite a URL do repositório Git (ex.: GitHub, GitLab): \n"
  echo
  read -p "> " repo_url
  echo
  
  # Validar que a URL parece ser um repositório Git válido (aceita qualquer repo: GitHub, GitLab, etc.)
  repo_url_limpo=$(echo "${repo_url}" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
  if [ -z "${repo_url_limpo}" ]; then
    printf "${RED}══════════════════════════════════════════════════════════════════${WHITE}\n"
    printf "${RED}❌ ERRO: URL do repositório não pode estar vazia!${WHITE}\n"
    printf "${RED}══════════════════════════════════════════════════════════════════${WHITE}\n"
    echo
    sleep 5
    exit 1
  fi
  if ! [[ "${repo_url_limpo}" =~ ^https?:// ]] && ! [[ "${repo_url_limpo}" =~ ^git@ ]]; then
    printf "${RED}══════════════════════════════════════════════════════════════════${WHITE}\n"
    printf "${RED}❌ ERRO: URL do repositório inválida!${WHITE}\n"
    echo
    printf "${YELLOW}   Use uma URL HTTPS (https://...) ou SSH (git@...).${WHITE}\n"
    printf "${YELLOW}   Exemplos:${WHITE}\n"
    printf "${BLUE}   https://github.com/usuario/repositorio.git${WHITE}\n"
    printf "${BLUE}   git@github.com:usuario/repositorio.git${WHITE}\n"
    echo
    printf "${RED}   Repositório informado: ${repo_url}${WHITE}\n"
    printf "${RED}══════════════════════════════════════════════════════════════════${WHITE}\n"
    echo
    sleep 5
    exit 1
  fi
  # Normalizar para uso posterior (garantir .git no final para clone, se for HTTPS)
  if [[ "${repo_url_limpo}" =~ ^https?:// ]] && [[ "${repo_url_limpo}" != *.git ]]; then
    repo_url="${repo_url_limpo}.git"
  else
    repo_url="${repo_url_limpo}"
  fi
  
  # Mostrar seleção de versão/commit apenas para o repositório multiflow-pro
  if echo "${repo_url}" | grep -q "scriptswhitelabel/multiflow-pro"; then
    selecionar_versao_instalacao
  else
    # Outros repositórios: sempre instalar a versão mais recente, sem menu
    declare -g versao_instalacao="Mais_Recente"
    declare -g commit_instalacao=""
  fi
}

# Define proxy usado
define_proxy_base() {
  banner
  while true; do
    printf "${WHITE} >> Instalar usando Nginx ou Traefik? (Nginx/Traefik): ${WHITE}\n"
    echo
    read -p "> " proxy
    echo
    proxy=$(echo "${proxy}" | tr '[:upper:]' '[:lower:]')

    if [ "${proxy}" = "nginx" ] || [ "${proxy}" = "traefik" ]; then
      sleep 2
      break
    else
      printf "${RED} >> Por favor, digite 'Nginx' ou 'Traefik' para continuar... ${WHITE}\n"
      echo
    fi
  done
  export proxy
}

# Define portas backend e frontend
define_portas_base() {
  banner
  printf "${WHITE} >> Usar as portas padrão para Backend (8080) e Frontend (3000) ? (S/N): ${WHITE}\n"
  echo
  read -p "> " use_default_ports
  use_default_ports=$(echo "${use_default_ports}" | tr '[:upper:]' '[:lower:]')
  echo

  default_backend_port=8080
  default_frontend_port=3000

  if [ "${use_default_ports}" = "s" ]; then
    backend_port=${default_backend_port}
    frontend_port=${default_frontend_port}
  else
    while true; do
      printf "${WHITE} >> Qual porta deseja para o Backend? ${WHITE}\n"
      echo
      read -p "> " backend_port
      echo
      if ! lsof -i:${backend_port} &>/dev/null; then
        break
      else
        printf "${RED} >> A porta ${backend_port} já está em uso. Por favor, escolha outra.${WHITE}\n"
        echo
      fi
    done

    while true; do
      printf "${WHITE} >> Qual porta deseja para o Frontend? ${WHITE}\n"
      echo
      read -p "> " frontend_port
      echo
      if ! lsof -i:${frontend_port} &>/dev/null; then
        break
      else
        printf "${RED} >> A porta ${frontend_port} já está em uso. Por favor, escolha outra.${WHITE}\n"
        echo
      fi
    done
  fi

  sleep 2
}

# Informa os dados de instalação
dados_instalacao_base() {
  printf "   ${WHITE}Anote os dados abaixo\n\n"
  printf "   ${WHITE}Subdominio Backend: ---->> ${YELLOW}${subdominio_backend}\n"
  printf "   ${WHITE}Subdominiio Frontend: -->> ${YELLOW}${subdominio_frontend}\n"
  printf "   ${WHITE}Seu Email: ------------->> ${YELLOW}${email_deploy}\n"
  printf "   ${WHITE}Nome da Empresa: ------->> ${YELLOW}${empresa}\n"
  printf "   ${WHITE}Senha Deploy: ---------->> ${YELLOW}${senha_deploy}\n"
  # printf "   ${WHITE}Subdominio Perfex: ----->> ${YELLOW}${subdominio_perfex}\n"
  printf "   ${WHITE}Senha Master: ---------->> ${YELLOW}${senha_master}\n"
  printf "   ${WHITE}Titulo da Aplicação: --->> ${YELLOW}${nome_titulo}\n"
  printf "   ${WHITE}Numero de Suporte: ----->> ${YELLOW}${numero_suporte}\n"
  printf "   ${WHITE}FACEBOOK_APP_ID: ------->> ${YELLOW}${facebook_app_id}\n"
  printf "   ${WHITE}FACEBOOK_APP_SECRET: --->> ${YELLOW}${facebook_app_secret}\n"
  printf "   ${WHITE}Token GitHub: ---------->> ${YELLOW}${github_token}\n"
  printf "   ${WHITE}URL do Repositório: ---->> ${YELLOW}${repo_url}\n"
  printf "   ${WHITE}Proxy Usado: ----------->> ${YELLOW}${proxy}\n"
  printf "   ${WHITE}Porta Backend: --------->> ${YELLOW}${backend_port}\n"
  printf "   ${WHITE}Porta Frontend: -------->> ${YELLOW}${frontend_port}\n"
  if [ -n "${versao_instalacao}" ]; then
    printf "   ${WHITE}Versão Instalada: ------->> ${YELLOW}${versao_instalacao}${WHITE}\n"
    printf "   ${WHITE}Commit Instalado: ------->> ${YELLOW}${commit_instalacao}${WHITE}\n"
  fi
}

# Confirma os dados de instalação
confirma_dados_instalacao_base() {
  printf " >> Confira abaixo os dados dessa instalação! \n"
  echo
  dados_instalacao_base
  echo
  printf "${WHITE} >> Os dados estão corretos? ${GREEN}S/${RED}N:${WHITE} \n"
  echo
  read -p "> " confirmacao
  echo
  confirmacao=$(echo "${confirmacao}" | tr '[:lower:]' '[:upper:]')
  if [ "${confirmacao}" == "S" ]; then
    printf "${GREEN} >> Continuando a Instalação... ${WHITE} \n"
    echo
  else
    printf "${GREEN} >> Retornando ao Menu Principal... ${WHITE} \n"
    echo
    sleep 2
    menu
  fi
}

# Atualiza sistema operacional
atualiza_vps_base() {
  banner
  printf "${WHITE} >> Atualizando sistema operacional...\n"
  echo
  
  # Verificar conectividade antes de atualizar
  if ! verificar_conectividade; then
    printf "${YELLOW} >> Tentando corrigir problemas de DNS...${WHITE}\n"
    tentar_corrigir_dns
    
    # Verificar novamente
    if ! verificar_conectividade; then
      printf "${RED} >> ERRO: Problemas de conectividade não resolvidos.${WHITE}\n"
      printf "${YELLOW} >> Por favor, resolva os problemas de rede antes de continuar.${WHITE}\n"
      trata_erro "atualiza_vps_base"
    fi
  fi
  
  UPDATE_FILE="$(pwd)/update.x"
  {
    # Tentar atualizar, se falhar, corrigir DNS e tentar novamente
    if ! sudo DEBIAN_FRONTEND=noninteractive apt update -y; then
      printf "${YELLOW} >> Erro ao atualizar. Tentando corrigir DNS e tentar novamente...${WHITE}\n"
      tentar_corrigir_dns
      if ! sudo DEBIAN_FRONTEND=noninteractive apt update -y; then
        printf "${RED} >> ERRO: Falha ao atualizar lista de pacotes após correções.${WHITE}\n"
        printf "${YELLOW} >> Verifique sua conexão de internet e configuração de DNS.${WHITE}\n"
        trata_erro "atualiza_vps_base"
      fi
    fi
    
    sudo DEBIAN_FRONTEND=noninteractive apt upgrade -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" && sudo DEBIAN_FRONTEND=noninteractive apt-get install build-essential -y && sudo DEBIAN_FRONTEND=noninteractive apt-get install -y apparmor-utils
    touch "${UPDATE_FILE}"
    sleep 2
  } || trata_erro "atualiza_vps_base"
}

# Cria usuário deploy
cria_deploy_base() {
  banner
  printf "${WHITE} >> Agora, vamos criar o usuário para deploy...\n"
  echo
  {
    sudo useradd -m -p $(openssl passwd -1 ${senha_deploy}) -s /bin/bash -G sudo deploy
    sudo usermod -aG sudo deploy
    sleep 2
  } || trata_erro "cria_deploy_base"
}

# Configura timezone
config_timezone_base() {
  banner
  printf "${WHITE} >> Configurando Timezone...\n"
  echo
  {
    sudo su - root <<EOF
  timedatectl set-timezone America/Sao_Paulo
EOF
    sleep 2
  } || trata_erro "config_timezone_base"
}

# Configura firewall
config_firewall_base() {
  banner
  printf "${WHITE} >> Configurando o firewall Portas 80 e 443...\n"
  echo
  {
    if [ "${ARCH}" = "x86_64" ]; then
      sudo su - root <<EOF >/dev/null 2>&1
  ufw allow 80/tcp && ufw allow 22/tcp && ufw allow 443/tcp
EOF
      sleep 2

    elif [ "${ARCH}" = "aarch64" ]; then
      sudo su - root <<EOF >/dev/null 2>&1
  sudo iptables -F &&
  sudo iptables -A INPUT -i lo -j ACCEPT &&
  sudo iptables -A OUTPUT -o lo -j ACCEPT &&
  sudo iptables -A INPUT -p tcp --dport 80 -j ACCEPT &&
  sudo iptables -A INPUT -p udp --dport 80 -j ACCEPT &&
  sudo iptables -A INPUT -p tcp --dport 443 -j ACCEPT &&
  sudo iptables -A INPUT -p udp --dport 443 -j ACCEPT &&
  sudo service netfilter-persistent save
EOF
      sleep 2

    else
      echo "Arquitetura não suportada."
    fi
  } || trata_erro "config_firewall_base"
}

# Instala dependência puppeteer
instala_puppeteer_base() {
  banner
  printf "${WHITE} >> Instalando puppeteer dependencies...\n"
  echo
  {
    sudo su - root <<EOF
apt-get install -y libaom-dev libass-dev libfreetype6-dev libfribidi-dev \
                   libharfbuzz-dev libgme-dev libgsm1-dev libmp3lame-dev \
                   libopencore-amrnb-dev libopencore-amrwb-dev libopenmpt-dev \
                   libopus-dev libfdk-aac-dev librubberband-dev libspeex-dev \
                   libssh-dev libtheora-dev libvidstab-dev libvo-amrwbenc-dev \
                   libvorbis-dev libvpx-dev libwebp-dev libx264-dev libx265-dev \
                   libxvidcore-dev libzmq3-dev libsdl2-dev build-essential \
                   yasm cmake libtool libc6 libc6-dev unzip wget pkg-config texinfo zlib1g-dev \
                   libxshmfence-dev libgcc1 libgbm-dev fontconfig locales gconf-service libasound2 \
                   libatk1.0-0 libcairo2 libcups2 libdbus-1-3 libexpat1 libfontconfig1 libgcc-s1 \
                   libgconf-2-4 libgdk-pixbuf2.0-0 libglib2.0-0 libgtk-3-0 libnspr4 libpango-1.0-0 \
                   libpangocairo-1.0-0 libstdc++6 libx11-6 libx11-xcb1 libxcb1 libxcomposite1 \
                   libxcursor1 libxdamage1 libxext6 libxfixes3 libxi6 libxrandr2 libxrender1 \
                   libxss1 libxtst6 ca-certificates fonts-liberation libappindicator1 libnss3 \
                   lsb-release xdg-utils

if grep -q "20.04" /etc/os-release; then
    apt-get install -y libsrt-dev
else
    apt-get install -y libsrt-openssl-dev
fi

EOF
    sleep 2
  } || trata_erro "instala_puppeteer_base"
}

# Instala FFMPEG
instala_ffmpeg_base() {
  banner
  printf "${WHITE} >> Instalando FFMPEG 6...\n"
  echo

  if [ -f "${FFMPEG}" ]; then
    printf " >> FFMPEG já foi instalado. Continuando a instalação...\n"
    echo
  else

    sleep 2

    {
      sudo apt install ffmpeg -y
      # Dynamic fetch of latest FFmpeg build from BtbN/FFmpeg-Builds
      download_ok=false
      asset_url=""
      if [ "${ARCH}" = "x86_64" ]; then
        asset_url=$(curl -sL https://api.github.com/repos/BtbN/FFmpeg-Builds/releases/latest | grep -oP '"browser_download_url":\s*"\K[^"]+' | grep -E 'linux64-gpl.*\.tar\.xz$' | head -n1)
      elif [ "${ARCH}" = "aarch64" ]; then
        asset_url=$(curl -sL https://api.github.com/repos/BtbN/FFmpeg-Builds/releases/latest | grep -oP '"browser_download_url":\s*"\K[^"]+' | grep -E 'linuxarm64-gpl.*\.tar\.xz$' | head -n1)
      else
        echo "Arquitetura não suportada: ${ARCH}"
      fi

      if [ -n "${asset_url}" ]; then
        FFMPEG_FILE="${asset_url##*/}"
        wget -q "${asset_url}" -O "${FFMPEG_FILE}"
        if [ $? -eq 0 ]; then
          mkdir -p ${FFMPEG_DIR}
          tar -xvf ${FFMPEG_FILE} -C ${FFMPEG_DIR} >/dev/null 2>&1
          extracted_dir=$(tar -tf ${FFMPEG_FILE} | head -1 | cut -d/ -f1)
          if [ -n "${extracted_dir}" ] && [ -d "${FFMPEG_DIR}/${extracted_dir}/bin" ]; then
            sudo cp ${FFMPEG_DIR}/${extracted_dir}/bin/ffmpeg /usr/bin/ >/dev/null 2>&1
            sudo cp ${FFMPEG_DIR}/${extracted_dir}/bin/ffprobe /usr/bin/ >/dev/null 2>&1
            sudo cp ${FFMPEG_DIR}/${extracted_dir}/bin/ffplay /usr/bin/ >/dev/null 2>&1
            rm -rf ${FFMPEG_DIR} >/dev/null 2>&1
            rm -f ${FFMPEG_FILE} >/dev/null 2>&1
            download_ok=true
          fi
        fi
      fi

      if [ "${download_ok}" != true ]; then
        printf "${YELLOW} >> Não foi possível baixar o FFmpeg dos builds oficiais. Usando pacote da distribuição...${WHITE}\n"
      fi

      export PATH=/usr/bin:${PATH}
      echo 'export PATH=/usr/bin:${PATH}' >>~/.bashrc
      source ~/.bashrc >/dev/null 2>&1
      if command -v ffmpeg >/dev/null 2>&1; then
        touch "${FFMPEG}"
      fi
    } || trata_erro "instala_ffmpeg_base"
  fi
}

# Instala Postgres
instala_postgres_base() {
  banner
  printf "${WHITE} >> Instalando postgres...\n"
  echo
  {
    sudo su - root <<EOF
  sudo apt-get install gnupg -y
  sudo sh -c 'echo "deb http://apt.postgresql.org/pub/repos/apt $(lsb_release -cs)-pgdg main" > /etc/apt/sources.list.d/pgdg.list'
  wget --quiet -O - https://www.postgresql.org/media/keys/ACCC4CF8.asc | sudo apt-key add -
  sudo apt-get update -y && sudo apt-get -y install postgresql-17
EOF
    sleep 2
  } || trata_erro "instala_postgres_base"
}

# Instala NodeJS
instala_node_base() {
  banner
 printf "${WHITE} >> Instalando nodejs...\n"
 echo
  {
    sudo su - root <<'NODEINSTALL'
    # Remove repositórios antigos do NodeSource que podem estar causando problemas
    rm -f /etc/apt/sources.list.d/nodesource.list 2>/dev/null
    rm -f /etc/apt/sources.list.d/nodesource*.list 2>/dev/null
    
    # Tenta primeiro com Node.js 22.x (LTS atual disponível no repositório oficial)
    printf " >> Tentando instalar Node.js 22.x LTS (repositório oficial)...\n"
    curl -fsSL https://deb.nodesource.com/setup_22.x | bash - 2>&1 | grep -v "does not have a Release file" || {
      printf " >> Node.js 22.x não disponível. Tentando Node.js 20.x...\n"
      curl -fsSL https://deb.nodesource.com/setup_20.x | bash - 2>&1 | grep -v "does not have a Release file" || {
        printf " >> Erro ao configurar repositório. Tentando método alternativo...\n"
        # Método alternativo: baixa e executa o script manualmente
        curl -fsSL https://deb.nodesource.com/setup_22.x -o /tmp/nodesource_setup.sh 2>/dev/null || \
        curl -fsSL https://deb.nodesource.com/setup_20.x -o /tmp/nodesource_setup.sh
        bash /tmp/nodesource_setup.sh 2>&1 | grep -v "does not have a Release file" || {
          printf " >> Falha ao configurar repositório NodeSource.\n"
          exit 1
        }
      }
    }
    
    # Atualiza lista de pacotes (ignorando erros de outros repositórios)
    printf " >> Atualizando lista de pacotes...\n"
    apt-get update -y 2>&1 | grep -v "does not have a Release file" | grep -v "Key is stored in legacy" || true
    
    # Instala Node.js
    printf " >> Instalando Node.js...\n"
    apt-get install -y nodejs || {
      printf " >> Erro ao instalar Node.js via apt.\n"
      exit 1
    }
    
    # Verifica se Node.js foi instalado
    if ! command -v node &> /dev/null; then
      printf " >> Erro: Node.js não foi encontrado no PATH após instalação.\n"
      printf " >> Verificando localização...\n"
      find /usr -name node -type f 2>/dev/null | head -5
      exit 1
    fi
    
    # Verifica se npm está disponível
    if ! command -v npm &> /dev/null; then
      printf " >> Erro: npm não foi encontrado no PATH após instalação.\n"
      printf " >> Verificando localização...\n"
      find /usr -name npm -type f 2>/dev/null | head -5
      exit 1
    fi
    
    # Mostra versões instaladas
    printf " >> Node.js instalado: "
    node --version
    printf " >> npm instalado: "
    npm --version
    
    # Instala o gerenciador de versões 'n' e configura a versão específica 20.19.4
    printf " >> Instalando gerenciador de versões 'n'...\n"
    npm install -g n || {
      printf " >> Aviso: Não foi possível instalar 'n'. Continuando com versão padrão.\n"
    }
    
    # Tenta instalar versão específica se 'n' foi instalado
    if command -v n &> /dev/null; then
      printf " >> Configurando Node.js versão 20.19.4...\n"
      n 20.19.4 || {
        printf " >> Aviso: Não foi possível instalar versão específica. Usando versão padrão.\n"
      }
      
      # Garante que os binários estão no PATH do sistema
      if [ -f /usr/local/n/versions/node/20.19.4/bin/node ]; then
        ln -sf /usr/local/n/versions/node/20.19.4/bin/node /usr/bin/node
        ln -sf /usr/local/n/versions/node/20.19.4/bin/npm /usr/bin/npm
        ln -sf /usr/local/n/versions/node/20.19.4/bin/npx /usr/bin/npx 2>/dev/null || true
      fi
    fi
    
    # Cria links simbólicos para garantir acesso global
    NODE_BIN=$(which node 2>/dev/null || find /usr -name node -type f 2>/dev/null | head -1)
    NPM_BIN=$(which npm 2>/dev/null || find /usr -name npm -type f 2>/dev/null | head -1)
    
    if [ -n "$NODE_BIN" ] && [ "$NODE_BIN" != "/usr/bin/node" ]; then
      ln -sf "$NODE_BIN" /usr/bin/node
    fi
    
    if [ -n "$NPM_BIN" ] && [ "$NPM_BIN" != "/usr/bin/npm" ]; then
      ln -sf "$NPM_BIN" /usr/bin/npm
    fi
    
    # Atualiza o PATH no perfil do sistema
    if ! grep -q "/usr/local/n/versions/node" /etc/profile 2>/dev/null; then
      echo 'export PATH=/usr/local/n/versions/node/20.19.4/bin:/usr/bin:$PATH' >> /etc/profile
    fi
    
    # Atualiza o PATH no bashrc do root e deploy
    for user_home in /root /home/deploy; do
      if [ -d "$user_home" ]; then
        if ! grep -q "/usr/local/n/versions/node" "$user_home/.bashrc" 2>/dev/null; then
          echo 'export PATH=/usr/local/n/versions/node/20.19.4/bin:/usr/bin:$PATH' >> "$user_home/.bashrc"
        fi
      fi
    done
    
    # Verifica novamente se node e npm estão disponíveis
    printf " >> Verificando instalação final...\n"
    export PATH=/usr/local/n/versions/node/20.19.4/bin:/usr/bin:$PATH
    node --version || exit 1
    npm --version || exit 1
NODEINSTALL
    
    sleep 2
  } || trata_erro "instala_node_base"
}

# Instala Redis
instala_redis_base() {
  {
    sudo su - root <<EOF
  apt install redis-server -y
  systemctl enable redis-server.service
  sed -i 's/# requirepass foobared/requirepass ${senha_deploy}/g' /etc/redis/redis.conf
  sed -i 's/^appendonly no/appendonly yes/g' /etc/redis/redis.conf
  systemctl restart redis-server.service
EOF
    sleep 2
  } || trata_erro "instala_redis_base"
}

# Instala PM2
instala_pm2_base() {
  banner
  printf "${WHITE} >> Instalando pm2...\n"
  echo
  
  {
    sudo su - root <<'PM2INSTALL'
    # Configura PATH para incluir Node.js
    export PATH=/usr/local/n/versions/node/20.19.4/bin:/usr/bin:/usr/local/bin:$PATH
    
    # Tenta encontrar node em vários locais possíveis
    NODE_BIN=""
    if command -v node &> /dev/null; then
      NODE_BIN=$(which node)
      printf " >> Node.js encontrado em: $NODE_BIN\n"
    elif [ -f /usr/local/n/versions/node/20.19.4/bin/node ]; then
      NODE_BIN="/usr/local/n/versions/node/20.19.4/bin/node"
      export PATH=/usr/local/n/versions/node/20.19.4/bin:/usr/bin:$PATH
      printf " >> Node.js encontrado em: $NODE_BIN\n"
    elif [ -f /usr/bin/node ]; then
      NODE_BIN="/usr/bin/node"
      printf " >> Node.js encontrado em: $NODE_BIN\n"
    else
      printf " >> ERRO: Node.js não está instalado ou não foi encontrado no sistema.\n"
      printf " >> Procurando Node.js no sistema...\n"
      find /usr -name node -type f 2>/dev/null | head -5
      exit 1
    fi
    
    # Verifica npm
    if ! command -v npm &> /dev/null; then
      printf " >> ERRO: npm não está instalado ou não foi encontrado no sistema.\n"
      printf " >> Procurando npm no sistema...\n"
      find /usr -name npm -type f 2>/dev/null | head -5
      exit 1
    fi
    
    # Mostra versões
    printf " >> Versão do Node.js: "
    node --version || exit 1
    printf " >> Versão do npm: "
    npm --version || exit 1
    
    # Instala PM2 globalmente
    printf " >> Instalando PM2...\n"
    npm install -g pm2 || {
      printf " >> Erro ao instalar PM2. Tentando com sudo...\n"
      exit 1
    }
    
    # Verifica se PM2 foi instalado
    if ! command -v pm2 &> /dev/null; then
      printf " >> PM2 não encontrado no PATH. Procurando...\n"
      PM2_BIN=$(find /usr -name pm2 -type f 2>/dev/null | head -1)
      if [ -n "$PM2_BIN" ]; then
        printf " >> PM2 encontrado em: $PM2_BIN\n"
        ln -sf "$PM2_BIN" /usr/bin/pm2 2>/dev/null || true
      else
        printf " >> ERRO: PM2 não foi instalado corretamente\n"
        exit 1
      fi
    fi
    
    printf " >> PM2 instalado com sucesso!\n"
    pm2 --version || exit 1
    
    # Configura o PM2 para iniciar automaticamente
    printf " >> Configurando PM2 para iniciar automaticamente...\n"
    export PATH=/usr/local/n/versions/node/20.19.4/bin:/usr/bin:$PATH
    
    # Garante que o usuário deploy existe
    if id "deploy" &>/dev/null; then
      pm2 startup ubuntu -u deploy --hp /home/deploy || {
        printf " >> Aviso: Não foi possível configurar startup automático. Continuando...\n"
      }
    else
      printf " >> Aviso: Usuário deploy não existe ainda. Startup será configurado depois.\n"
    fi
PM2INSTALL
    
    sleep 2
  } || trata_erro "instala_pm2_base"
}

# Instala Nginx e dependências
instala_nginx_base() {
  banner
  printf "${WHITE} >> Instalando Nginx...\n"
  echo
  
  # Verificar conectividade antes de continuar
  if ! verificar_conectividade; then
    printf "${YELLOW} >> Tentando corrigir problemas de DNS...${WHITE}\n"
    tentar_corrigir_dns
    
    # Verificar novamente
    if ! verificar_conectividade; then
      printf "${RED} >> ERRO: Problemas de conectividade não resolvidos.${WHITE}\n"
      printf "${YELLOW} >> Por favor, resolva os problemas de rede antes de continuar.${WHITE}\n"
      printf "${YELLOW} >> Você pode tentar:${WHITE}\n"
      printf "${YELLOW} >>   1. Verificar conexão de internet${WHITE}\n"
      printf "${YELLOW} >>   2. Configurar DNS manualmente${WHITE}\n"
      printf "${YELLOW} >>   3. Verificar firewall/proxy${WHITE}\n"
      trata_erro "instala_nginx_base"
    fi
  fi
  
  {
    # Atualizar lista de pacotes primeiro
    printf "${WHITE} >> Atualizando lista de pacotes...\n"
    sudo su - root <<EOF
apt update -y || {
  echo "Erro ao atualizar. Tentando corrigir DNS..."
  echo "nameserver 8.8.8.8" >> /etc/resolv.conf
  echo "nameserver 8.8.4.4" >> /etc/resolv.conf
  apt update -y
}
EOF

    sleep 2

    # Instalar Nginx
    printf "${WHITE} >> Instalando pacote Nginx...\n"
    sudo su - root <<EOF
if ! apt install -y nginx; then
  echo "Erro ao instalar Nginx. Verificando logs..."
  echo "Possíveis soluções:"
  echo "1. Verificar conectividade de internet"
  echo "2. Configurar DNS: echo 'nameserver 8.8.8.8' >> /etc/resolv.conf"
  echo "3. Tentar: apt-get update --fix-missing"
  exit 1
fi
rm /etc/nginx/sites-enabled/default 2>/dev/null || true
EOF

    sleep 2

    # Configurar client_max_body_size
    sudo su - root <<EOF
mkdir -p /etc/nginx/conf.d
echo 'client_max_body_size 100M;' > /etc/nginx/conf.d/${empresa}.conf
EOF

    sleep 2

    # Reiniciar Nginx
    sudo su - root <<EOF
if ! service nginx restart; then
  systemctl start nginx || systemctl restart nginx
fi
EOF

    sleep 2

    # Instalar snapd e certbot
    printf "${WHITE} >> Instalando Certbot...\n"
    sudo su - root <<EOF
if ! command -v snap &> /dev/null; then
  apt install -y snapd || {
    echo "Erro ao instalar snapd"
    exit 1
  }
  snap install core
  snap refresh core
fi

# Remover certbot antigo se existir
apt-get remove certbot -y 2>/dev/null || true

# Instalar certbot via snap
if ! snap install --classic certbot; then
  echo "Erro ao instalar Certbot via snap"
  exit 1
fi

# Criar link simbólico se não existir
if [ ! -f /usr/bin/certbot ]; then
  ln -s /snap/bin/certbot /usr/bin/certbot
fi
EOF

    sleep 2
    
    printf "${GREEN} >> Nginx e Certbot instalados com sucesso!${WHITE}\n"
  } || trata_erro "instala_nginx_base"
}

# Instala Traefik
instala_traefik_base() {
  useradd --system --shell /bin/false --user-group --no-create-home traefik
  cd /tmp
  mkdir traefik
  cd traefik/
  if [ "${ARCH}" = "x86_64" ]; then
    traefik_arch="amd64"
  elif [ "${ARCH}" = "aarch64" ]; then
    traefik_arch="arm64"
  else
    echo "Arquitetura não suportada: ${ARCH}"
    exit 1
  fi
  traefik_url="https://github.com/traefik/traefik/releases/download/v2.10.5/traefik_v2.10.5_linux_${traefik_arch}.tar.gz"
  curl --remote-name --location "${traefik_url}"
  tar -zxf traefik_v2.10.5_linux_${traefik_arch}.tar.gz
  cp traefik /usr/local/bin/traefik
  chmod a+x /usr/local/bin/traefik
  cd ..
  rm -rf traefik
  mkdir --parents /etc/traefik
  mkdir --parents /etc/traefik/conf.d

  sleep 2

  sudo su - root <<EOF
cat > /etc/traefik/traefik.toml << 'END'
################################################################
# Global configuration
################################################################
[global]
  checkNewVersion = "false"
  sendAnonymousUsage = "true"

################################################################
# Entrypoints configuration
################################################################
[entryPoints]
  [entryPoints.websecure]
    address = ":443"
  [entryPoints.web]
    address = ":80"

################################################################
# CertificatesResolvers configuration for Let's Encrypt
################################################################
[certificatesResolvers.letsencryptresolver.acme]
  email = "${email_deploy}"
  storage = "/etc/traefik/acme.json"
  [certificatesResolvers.letsencryptresolver.acme.httpChallenge]
    # Define the entrypoint which will receive the HTTP challenge
    entryPoint = "web"

################################################################
# Log configuration
################################################################
[log]
  level = "INFO"
  format = "json"
  filePath = "/var/log/traefik/traefik.log"

################################################################
# Access Log configuration
################################################################
[accessLog]
  filePath = "/var/log/traefik/access.log"
  format = "common"

################################################################
# API and Dashboard configuration
################################################################
[api]
  dashboard = false
  insecure = false
  # [entryPoints.dashboard]
  #   address = ":9090"

################################################################
# Providers configuration
################################################################
# Since the original setup was intended for Docker and this setup is for systemd,
# we don't use Docker provider settings but we keep file provider.
[providers]
  [providers.file]
    directory = "/etc/traefik/conf.d/"
    watch = "true"
END
EOF

  sleep 2

  sudo su - root <<EOF
cat > /etc/traefik/traefik.service << 'END'
# Systemd Traefik service
[Unit]
Description=Traefik - Proxy
Documentation=https://docs.traefik.io
After=network-online.target
Wants=network-online.target systemd-networkd-wait-online.service
AssertFileIsExecutable=/usr/local/bin/traefik
AssertPathExists=/etc/traefik/traefik.toml
#RequiresMountsFor=/var/log

[Service]
User=traefik
AmbientCapabilities=CAP_NET_BIND_SERVICE
Type=notify
ExecStart=/usr/local/bin/traefik --configFile=/etc/traefik/traefik.toml
Restart=always
WatchdogSec=2s

LogsDirectory=traefik

[Install]
WantedBy=multi-user.target
END
EOF

  sleep 2

  sudo su - root <<EOF
cat > /etc/traefik/conf.d/tls.toml << 'END'
[tls.options]
  [tls.options.default]
    sniStrict = true
    minVersion = "VersionTLS12"
END
EOF
  sleep 2

  cp /etc/traefik/traefik.service /etc/systemd/system/
  chown -R traefik:traefik /etc/traefik/
  rm -rf /etc/traefik/traefik.service
  systemctl daemon-reload
  sleep 2
  systemctl enable --now traefik.service
  sleep 2
}

# Cria banco de dados
cria_banco_base() {
  banner
  printf "${WHITE} >> Criando Banco Postgres...\n"
  echo
  {
    sudo su - postgres <<EOF
    createdb ${empresa};
    psql
    CREATE USER ${empresa} SUPERUSER INHERIT CREATEDB CREATEROLE;
    ALTER USER ${empresa} PASSWORD '${senha_deploy}';
    \q
    exit
EOF

    sleep 2
  } || trata_erro "cria_banco_base"
}

# Instala Git
instala_git_base() {
  banner
  printf "${WHITE} >> Instalando o GIT...\n"
  echo
  {
    sudo su - root <<EOF
  apt install -y git
  apt -y autoremove
EOF
    sleep 2
  } || trata_erro "instala_git_base"
}

# Função para codificar URL de clone
codifica_clone_base() {
  local length="${#1}"
  for ((i = 0; i < length; i++)); do
    local c="${1:i:1}"
    case $c in
    [a-zA-Z0-9.~_-]) printf "$c" ;;
    *) printf '%%%02X' "'$c" ;;
    esac
  done
}

# Definir versões disponíveis para instalação
definir_versoes_instalacao() {
  declare -gA VERSOES_INSTALACAO
  VERSOES_INSTALACAO["6.5.2"]="6607976a25f86127bd494bba20017fe6bbd9f50a"
  VERSOES_INSTALACAO["6.5"]="ab5565df5937f6113bbbb6b2ce9c526e25e525ef"
  VERSOES_INSTALACAO["6.4.4"]="b5de35ebb4acb10694ce4e8b8d6068b31eeabef9"
  VERSOES_INSTALACAO["6.4.3"]="6aa224db151bd8cbbf695b07a8624c976e89db00"
}

# Mostrar lista de versões disponíveis para instalação
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

# Selecionar versão para instalação
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
    declare -g versao_instalacao="Mais_Recente"
    declare -g commit_instalacao=""
    printf "\n${GREEN} >> Versão selecionada: ${BLUE}Mais Recente${WHITE}\n"
    printf "${GREEN} >> Será instalada a versão mais recente disponível no repositório${WHITE}\n"
    # Usar "Mais_Recente" internamente para evitar problemas com espaços no source
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

# Clona código de repo privado
baixa_codigo_base() {
  banner
  printf "${WHITE} >> Fazendo download do ${nome_titulo}...\n"
  echo
  {
    if [ -z "${repo_url}" ] || [ -z "${github_token}" ]; then
      printf "${WHITE} >> Erro: URL do repositório ou token do GitHub não definidos.\n"
      exit 1
    fi

    github_token_encoded=$(codifica_clone_base "${github_token}")
    github_url=$(echo ${repo_url} | sed "s|https://|https://${github_token_encoded}@|")

    dest_dir="/home/deploy/${empresa}/"

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
    if [ -z "${commit_instalacao}" ] || [ "${versao_instalacao}" = "Mais_Recente" ] || [ "${versao_instalacao}" = "Mais Recente" ]; then
      banner
      printf "${WHITE} >> Instalando versão mais recente disponível no repositório...\n"
      echo
      
      cd ${dest_dir} || trata_erro "cd para diretório do projeto"
      
      # Fazer checkout para a branch principal (geralmente MULTI100-OFICIAL-u21 ou main/master)
      sudo su - deploy <<CHECKOUTRECENT
cd ${dest_dir}
git fetch --all --prune 2>/dev/null || true

# Tentar fazer checkout para a branch principal
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
    # Fazer checkout do commit específico se foi selecionado
    elif [ -n "${commit_instalacao}" ]; then
      banner
      printf "${WHITE} >> Fazendo checkout para o commit da versão ${versao_instalacao}...\n"
      echo
      
      cd ${dest_dir} || trata_erro "cd para diretório do projeto"
      
      # Corrigir permissões antes do checkout
      chown -R deploy:deploy ${dest_dir} 2>/dev/null || true
      chmod -R 755 ${dest_dir}/.git 2>/dev/null || true
      
      # Fazer fetch para garantir que temos todos os commits
      sudo su - deploy <<FETCHCOMMIT
cd ${dest_dir}
git fetch --all --prune 2>/dev/null || true
FETCHCOMMIT
      
      # Verificar se o commit existe
      sudo su - deploy <<VERIFYCOMMIT
cd ${dest_dir}
if git cat-file -e "${commit_instalacao}^{commit}" 2>/dev/null; then
  exit 0
else
  exit 1
fi
VERIFYCOMMIT
      
      if [ $? -eq 0 ]; then
        # Criar branch temporária para o commit
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
        printf "${YELLOW} >> Verifique se o commit hash está correto.${WHITE}\n"
        exit 1
      fi
    fi

    mkdir -p /home/deploy/${empresa}/backend/public/
    chown deploy:deploy -R /home/deploy/${empresa}/
    chmod 775 -R /home/deploy/${empresa}/backend/public/
    sleep 2
  } || trata_erro "baixa_codigo_base"
}

# Instala e configura backend
instala_backend_base() {
  banner
  printf "${WHITE} >> Configurando variáveis de ambiente do ${BLUE}backend${WHITE}...\n"
  echo
  
  # Verifica se a variável empresa está definida
  if [ -z "${empresa}" ]; then
    printf "${RED} >> ERRO: Variável 'empresa' não está definida!\n${WHITE}"
    printf "${YELLOW} >> Carregando variáveis salvas...\n${WHITE}"
    carregar_variaveis
    if [ -z "${empresa}" ]; then
      printf "${RED} >> ERRO: Não foi possível carregar a variável 'empresa'. Abortando.\n${WHITE}"
      exit 1
    fi
  fi
  
  # Verifica se o diretório do código existe
  if [ ! -d "/home/deploy/${empresa}" ]; then
    printf "${RED} >> ERRO: Diretório /home/deploy/${empresa} não existe!\n${WHITE}"
    printf "${YELLOW} >> O código precisa ser clonado primeiro. Verifique a etapa anterior.\n${WHITE}"
    exit 1
  fi
  
  {
    sleep 2
    subdominio_backend=$(echo "${subdominio_backend/https:\/\//}")
    subdominio_backend=${subdominio_backend%%/*}
    subdominio_backend=https://${subdominio_backend}
    subdominio_frontend=$(echo "${subdominio_frontend/https:\/\//}")
    subdominio_frontend=${subdominio_frontend%%/*}
    subdominio_frontend=https://${subdominio_frontend}
    # subdominio_perfex=$(echo "${subdominio_perfex/https:\/\//}")
    # subdominio_perfex=${subdominio_perfex%%/*}
    # subdominio_perfex=https://${subdominio_perfex}
    if [ "${ALTA_PERFORMANCE}" = "1" ]; then
      db_host_instalador="127.0.0.1"
      db_port_instalador="6732"
      redis_uri_instalador="redis://127.0.0.1:1569"
    else
      db_host_instalador="localhost"
      db_port_instalador="5432"
      redis_uri_instalador="redis://:${senha_deploy}@127.0.0.1:6379"
    fi
    sudo su - deploy <<EOF
  cat <<[-]EOF > /home/deploy/${empresa}/backend/.env
# Scripts WhiteLabel - All Rights Reserved - (18) 9 8802-9627
NODE_ENV=
BACKEND_URL=${subdominio_backend}
FRONTEND_URL=${subdominio_frontend}
PROXY_PORT=443
PORT=${backend_port}

# CREDENCIAIS BD
DB_HOST=${db_host_instalador}
DB_DIALECT=postgres
DB_PORT=${db_port_instalador}
DB_USER=${empresa}
DB_PASS=${senha_deploy}
DB_NAME=${empresa}

# DADOS REDIS
REDIS_URI=${redis_uri_instalador}
REDIS_OPT_LIMITER_MAX=1
REDIS_OPT_LIMITER_DURATION=3000
# REDIS_URI_ACK=redis://:${senha_deploy}@127.0.0.1:6379
# BULL_BOARD=true
# BULL_USER=${email_deploy}
# BULL_PASS=${senha_deploy}

# --- RabbitMQ ---
RABBITMQ_HOST=localhost
RABBITMQ_PORT=5672
RABBIT_USER=${empresa}
RABBIT_PASS=${senha_deploy}
RABBITMQ_URI=amqp://\${empresa}:\${senha_deploy}@localhost:5672/

TIMEOUT_TO_IMPORT_MESSAGE=1000

# SECRETS
JWT_SECRET=${jwt_secret}
JWT_REFRESH_SECRET=${jwt_refresh_secret}
MASTER_KEY=${senha_master}

# PERFEX_URL=${subdominio_perfex}
# PERFEX_MODULE=Multi100
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
# URL_API_OFICIAL=https://SubDominioDaOficial.SEUDOMINIO.com.br
TOKEN_API_OFICIAL="adminpro"
OFFICIAL_CAMPAIGN_CONCURRENCY=10  # Processa até 10 campanhas ao mesmo tempo

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
  # Configura PATH para Node.js
  if [ -d /usr/local/n/versions/node/20.19.4/bin ]; then
    export PATH=/usr/local/n/versions/node/20.19.4/bin:/usr/bin:/usr/local/bin:\$PATH
  elif [ -f /usr/bin/node ]; then
    export PATH=/usr/bin:/usr/local/bin:\$PATH
  else
    # Tenta encontrar node no sistema
    NODE_DIR=\$(find /usr -type d -name "node" -o -type f -name "node" 2>/dev/null | head -1 | xargs dirname 2>/dev/null)
    if [ -n "\$NODE_DIR" ]; then
      export PATH=\$NODE_DIR:/usr/bin:\$PATH
    fi
  fi
  
  # Verifica se node e npm estão disponíveis
  if ! command -v node &> /dev/null || ! command -v npm &> /dev/null; then
    echo "ERRO: Node.js ou npm não encontrado. PATH atual: \$PATH"
    which node || echo "node não encontrado"
    which npm || echo "npm não encontrado"
    exit 1
  fi
  
  # Verifica se o diretório existe antes de tentar acessar
  BACKEND_DIR="/home/deploy/${empresa}/backend"
  if [ ! -d "\$BACKEND_DIR" ]; then
    echo "ERRO: Diretório do backend não existe: \$BACKEND_DIR"
    echo "Verificando diretórios disponíveis em /home/deploy/${empresa}/..."
    ls -la /home/deploy/${empresa}/ 2>/dev/null || echo "Diretório /home/deploy/${empresa}/ não existe"
    exit 1
  fi
  
  cd "\$BACKEND_DIR"
  
  # Verifica se package.json existe
  if [ ! -f "package.json" ]; then
    echo "ERRO: package.json não encontrado em \$BACKEND_DIR"
    echo "Conteúdo do diretório:"
    ls -la
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
  BACKEND_DIR="/home/deploy/${empresa}/backend"
  FFMPEG_FILE="\${BACKEND_DIR}/node_modules/@ffmpeg-installer/ffmpeg/index.js"
  
  # Verifica se o arquivo existe antes de tentar modificá-lo
  if [ -f "\$FFMPEG_FILE" ]; then
    sed -i 's|npm3Binary = .*|npm3Binary = "/usr/bin/ffmpeg";|' "\$FFMPEG_FILE"
  else
    echo "Aviso: Arquivo ffmpeg-installer não encontrado. Pulando modificação."
  fi
  
  # Cria o diretório e arquivo se necessário
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
  # Configura PATH para Node.js
  if [ -d /usr/local/n/versions/node/20.19.4/bin ]; then
    export PATH=/usr/local/n/versions/node/20.19.4/bin:/usr/bin:/usr/local/bin:\$PATH
  else
    export PATH=/usr/bin:/usr/local/bin:\$PATH
  fi
  
  BACKEND_DIR="/home/deploy/${empresa}/backend"
  if [ ! -d "\$BACKEND_DIR" ]; then
    echo "ERRO: Diretório do backend não existe: \$BACKEND_DIR"
    exit 1
  fi
  
  cd "\$BACKEND_DIR"
  npx sequelize db:migrate
MIGRATEINSTALL

    sleep 2

    banner
    printf "${WHITE} >> Executando db:seed...\n"
    echo
    sudo su - deploy <<SEEDINSTALL
  # Configura PATH para Node.js
  if [ -d /usr/local/n/versions/node/20.19.4/bin ]; then
    export PATH=/usr/local/n/versions/node/20.19.4/bin:/usr/bin:/usr/local/bin:\$PATH
  else
    export PATH=/usr/bin:/usr/local/bin:\$PATH
  fi
  
  BACKEND_DIR="/home/deploy/${empresa}/backend"
  if [ ! -d "\$BACKEND_DIR" ]; then
    echo "ERRO: Diretório do backend não existe: \$BACKEND_DIR"
    exit 1
  fi
  
  cd "\$BACKEND_DIR"
  npx sequelize db:seed:all
SEEDINSTALL

    sleep 2

    banner
    printf "${WHITE} >> Iniciando pm2 ${BLUE}backend${WHITE}...\n"
    echo
    sudo su - deploy <<PM2BACKEND
  # Configura PATH para Node.js e PM2
  if [ -d /usr/local/n/versions/node/20.19.4/bin ]; then
    export PATH=/usr/local/n/versions/node/20.19.4/bin:/usr/bin:/usr/local/bin:\$PATH
  else
    export PATH=/usr/bin:/usr/local/bin:\$PATH
  fi
  
  BACKEND_DIR="/home/deploy/${empresa}/backend"
  if [ ! -d "\$BACKEND_DIR" ]; then
    echo "ERRO: Diretório do backend não existe: \$BACKEND_DIR"
    exit 1
  fi
  
  cd "\$BACKEND_DIR"
  
  # Verifica se o arquivo dist/server.js existe
  if [ ! -f "dist/server.js" ]; then
    echo "ERRO: Arquivo dist/server.js não encontrado. O build pode ter falhado."
    exit 1
  fi
  
  pm2 start dist/server.js --name ${empresa}-backend
PM2BACKEND

    sleep 2
  } || trata_erro "instala_backend_base"
}

# Instala e configura frontend
instala_frontend_base() {
  banner
  printf "${WHITE} >> Instalando dependências do ${BLUE}frontend${WHITE}...\n"
  echo
  
  # Verifica se a variável empresa está definida
  if [ -z "${empresa}" ]; then
    printf "${RED} >> ERRO: Variável 'empresa' não está definida!\n${WHITE}"
    printf "${YELLOW} >> Carregando variáveis salvas...\n${WHITE}"
    carregar_variaveis
    if [ -z "${empresa}" ]; then
      printf "${RED} >> ERRO: Não foi possível carregar a variável 'empresa'. Abortando.\n${WHITE}"
      exit 1
    fi
  fi
  
  # Verifica se o diretório do código existe
  if [ ! -d "/home/deploy/${empresa}" ]; then
    printf "${RED} >> ERRO: Diretório /home/deploy/${empresa} não existe!\n${WHITE}"
    printf "${YELLOW} >> O código precisa ser clonado primeiro. Verifique a etapa anterior.\n${WHITE}"
    exit 1
  fi
  
  {
    sudo su - deploy <<FRONTENDINSTALL
  # Configura PATH para Node.js
  if [ -d /usr/local/n/versions/node/20.19.4/bin ]; then
    export PATH=/usr/local/n/versions/node/20.19.4/bin:/usr/bin:/usr/local/bin:\$PATH
  else
    export PATH=/usr/bin:/usr/local/bin:\$PATH
  fi
  
  FRONTEND_DIR="/home/deploy/${empresa}/frontend"
  if [ ! -d "\$FRONTEND_DIR" ]; then
    echo "ERRO: Diretório do frontend não existe: \$FRONTEND_DIR"
    exit 1
  fi
  
  cd "\$FRONTEND_DIR"
  
  # Verifica se package.json existe
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
    subdominio_backend=$(echo "${subdominio_backend/https:\/\//}")
    subdominio_backend=${subdominio_backend%%/*}
    subdominio_backend=https://${subdominio_backend}
    frontend_chatbot_url=$(echo "${frontend_chatbot_url/https:\/\//}")
    frontend_chatbot_url=${frontend_chatbot_url%%/*}
    frontend_chatbot_url=https://${frontend_chatbot_url}
    sudo su - deploy <<EOF
  cat <<[-]EOF > /home/deploy/${empresa}/frontend/.env
REACT_APP_BACKEND_URL=${subdominio_backend}
REACT_APP_FACEBOOK_APP_ID=${facebook_app_id}
REACT_APP_REQUIRE_BUSINESS_MANAGEMENT=TRUE
REACT_APP_NAME_SYSTEM=${nome_titulo}
REACT_APP_NUMBER_SUPPORT=${numero_suporte}
SERVER_PORT=${frontend_port}
[-]EOF
EOF

    sleep 2

    banner
    printf "${WHITE} >> Compilando o código do ${BLUE}frontend${WHITE}...\n"
    echo
    sudo su - deploy <<FRONTENDBUILD
  # Configura PATH para Node.js
  if [ -d /usr/local/n/versions/node/20.19.4/bin ]; then
    export PATH=/usr/local/n/versions/node/20.19.4/bin:/usr/bin:/usr/local/bin:\$PATH
  else
    export PATH=/usr/bin:/usr/local/bin:\$PATH
  fi
  
  FRONTEND_DIR="/home/deploy/${empresa}/frontend"
  if [ ! -d "\$FRONTEND_DIR" ]; then
    echo "ERRO: Diretório do frontend não existe: \$FRONTEND_DIR"
    exit 1
  fi
  
  cd "\$FRONTEND_DIR"
  
  # Verifica se server.js existe
  if [ ! -f "server.js" ]; then
    echo "ERRO: Arquivo server.js não encontrado em \$FRONTEND_DIR"
    exit 1
  fi
  
  sed -i 's/3000/'"${frontend_port}"'/g' server.js
  NODE_OPTIONS="--max-old-space-size=4096 --openssl-legacy-provider" npm run build
FRONTENDBUILD

    sleep 2

    banner
    printf "${WHITE} >> Iniciando pm2 ${BLUE}frontend${WHITE}...\n"
    echo
    sudo su - deploy <<PM2FRONTEND
  # Configura PATH para Node.js e PM2
  if [ -d /usr/local/n/versions/node/20.19.4/bin ]; then
    export PATH=/usr/local/n/versions/node/20.19.4/bin:/usr/bin:/usr/local/bin:\$PATH
  else
    export PATH=/usr/bin:/usr/local/bin:\$PATH
  fi
  
  FRONTEND_DIR="/home/deploy/${empresa}/frontend"
  if [ ! -d "\$FRONTEND_DIR" ]; then
    echo "ERRO: Diretório do frontend não existe: \$FRONTEND_DIR"
    exit 1
  fi
  
  cd "\$FRONTEND_DIR"
  
  # Verifica se server.js existe
  if [ ! -f "server.js" ]; then
    echo "ERRO: Arquivo server.js não encontrado em \$FRONTEND_DIR"
    exit 1
  fi
  
  pm2 start server.js --name ${empresa}-frontend
  pm2 save
PM2FRONTEND

    sleep 2
  } || trata_erro "instala_frontend_base"
}

# Configura cron de atualização de dados da pasta public
config_cron_base() {
  printf "${GREEN} >> Adicionando cron atualizar o uso da public às 3h da manhã...${WHITE} \n"
  echo
  {
    if ! command -v cron >/dev/null 2>&1; then
      sudo apt-get update
      sudo apt-get install -y cron
    fi
    sleep 2
    wget -O /home/deploy/atualiza_public.sh https://raw.githubusercontent.com/FilipeCamillo/busca_tamaho_pasta/main/busca_tamaho_pasta.sh >/dev/null 2>&1
    chmod +x /home/deploy/atualiza_public.sh >/dev/null 2>&1
    chown deploy:deploy /home/deploy/atualiza_public.sh >/dev/null 2>&1
    echo '#!/bin/bash
# Configura PATH para Node.js e PM2
if [ -d /usr/local/n/versions/node/20.19.4/bin ]; then
  export PATH=/usr/local/n/versions/node/20.19.4/bin:/usr/bin:/usr/local/bin:$PATH
elif [ -f /usr/bin/node ]; then
  export PATH=/usr/bin:/usr/local/bin:$PATH
else
  # Tenta encontrar node no sistema
  NODE_DIR=$(find /usr -type d -name "node" -o -type f -name "node" 2>/dev/null | head -1 | xargs dirname 2>/dev/null)
  if [ -n "$NODE_DIR" ]; then
    export PATH=$NODE_DIR:/usr/bin:$PATH
  fi
fi
pm2 restart all' >/home/deploy/reinicia_instancia.sh
    chmod +x /home/deploy/reinicia_instancia.sh
    chown deploy:deploy /home/deploy/reinicia_instancia.sh >/dev/null 2>&1
    sudo su - deploy <<'EOF'
        CRON_JOB1="0 3 * * * wget -O /home/deploy/atualiza_public.sh https://raw.githubusercontent.com/FilipeCamillo/busca_tamaho_pasta/main/busca_tamaho_pasta.sh && bash /home/deploy/atualiza_public.sh >> /home/deploy/cron.log 2>&1"
        CRON_JOB2="0 1 * * * /bin/bash /home/deploy/reinicia_instancia.sh >> /home/deploy/cron.log 2>&1"
        CRON_EXISTS1=$(crontab -l 2>/dev/null | grep -F "${CRON_JOB1}")
        CRON_EXISTS2=$(crontab -l 2>/dev/null | grep -F "${CRON_JOB2}")

        if [[ -z "${CRON_EXISTS1}" ]] || [[ -z "${CRON_EXISTS2}" ]]; then
            printf "${GREEN} >> Cron não detectado, agendando agora...${WHITE} "
            {
                crontab -l 2>/dev/null
                [[ -z "${CRON_EXISTS1}" ]] && echo "${CRON_JOB1}"
                [[ -z "${CRON_EXISTS2}" ]] && echo "${CRON_JOB2}"
            } | crontab -
        else
            printf "${GREEN} >> Crons já existem, continuando...${WHITE} \n"
        fi
EOF

    sleep 2
  } || trata_erro "config_cron_base"
}

# Configura Nginx
config_nginx_base() {
  banner
  printf "${WHITE} >> Configurando nginx ${BLUE}frontend${WHITE}...\n"
  echo
  {
    frontend_hostname=$(echo "${subdominio_frontend/https:\/\//}")
    sudo su - root <<EOF
cat > /etc/nginx/sites-available/${empresa}-frontend << 'END'
server {
  server_name ${frontend_hostname};
  location / {
    proxy_pass http://127.0.0.1:${frontend_port};
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
ln -s /etc/nginx/sites-available/${empresa}-frontend /etc/nginx/sites-enabled
EOF

    sleep 2

    banner
    printf "${WHITE} >> Configurando Nginx ${BLUE}backend${WHITE}...\n"
    echo
    backend_hostname=$(echo "${subdominio_backend/https:\/\//}")
    sudo su - root <<EOF
cat > /etc/nginx/sites-available/${empresa}-backend << 'END'
upstream backend {
        server 127.0.0.1:${backend_port};
        keepalive 32;
    }
server {
  server_name ${backend_hostname};
  location / {
    proxy_pass http://backend;
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
ln -s /etc/nginx/sites-available/${empresa}-backend /etc/nginx/sites-enabled
EOF

    sleep 2

    banner
    printf "${WHITE} >> Emitindo SSL do ${subdominio_backend}...\n"
    echo
    backend_domain=$(echo "${subdominio_backend/https:\/\//}")
    sudo su - root <<EOF
    certbot -m ${email_deploy} \
            --nginx \
            --agree-tos \
            -n \
            -d ${backend_domain}
EOF

    sleep 2

    banner
    printf "${WHITE} >> Emitindo SSL do ${subdominio_frontend}...\n"
    echo
    frontend_domain=$(echo "${subdominio_frontend/https:\/\//}")
    sudo su - root <<EOF
    certbot -m ${email_deploy} \
            --nginx \
            --agree-tos \
            -n \
            -d ${frontend_domain}
EOF

    sleep 2
  } || trata_erro "config_nginx_base"
}

# Configura Traefik
config_traefik_base() {
  {
    source /home/deploy/${empresa}/backend/.env
    subdominio_backend=$(echo ${BACKEND_URL} | sed 's|https://||')
    subdominio_frontend=$(echo ${FRONTEND_URL} | sed 's|https://||')
    sudo su - root <<EOF
cat > /etc/traefik/conf.d/routers-${subdominio_backend}.toml << 'END'
[http.routers]
  [http.routers.backend]
    rule = "Host(\`${subdominio_backend}\`)"
    service = "backend"
    entryPoints = ["web"]
    middlewares = ["https-redirect"]

  [http.routers.backend-secure]
    rule = "Host(\`${subdominio_backend}\`)"
    service = "backend"
    entryPoints = ["websecure"]
    [http.routers.backend-secure.tls]
      certResolver = "letsencryptresolver"

[http.services]
  [http.services.backend]
    [http.services.backend.loadBalancer]
      [[http.services.backend.loadBalancer.servers]]
        url = "http://127.0.0.1:${backend_port}"

[http.middlewares]
  [http.middlewares.https-redirect.redirectScheme]
    scheme = "https"
    permanent = true
END
EOF

    sleep 2

    sudo su - root <<EOF
cat > /etc/traefik/conf.d/routers-${subdominio_frontend}.toml << 'END'
[http.routers]
  [http.routers.frontend]
    rule = "Host(\`${subdominio_frontend}\`)"
    service = "frontend"
    entryPoints = ["web"]
    middlewares = ["https-redirect"]

  [http.routers.frontend-secure]
    rule = "Host(\`${subdominio_frontend}\`)"
    service = "frontend"
    entryPoints = ["websecure"]
    [http.routers.frontend-secure.tls]
      certResolver = "letsencryptresolver"

[http.services]
  [http.services.frontend]
    [http.services.frontend.loadBalancer]
      [[http.services.frontend.loadBalancer.servers]]
        url = "http://127.0.0.1:${frontend_port}"

[http.middlewares]
  [http.middlewares.https-redirect.redirectScheme]
    scheme = "https"
    permanent = true
END
EOF

    sleep 2
  } || trata_erro "config_traefik_base"
}

# Ajusta latência - necessita reiniciar a VPS para funcionar de fato
config_latencia_base() {
  banner
  printf "${WHITE} >> Reduzindo Latência...\n"
  echo
  {
    sudo su - root <<EOF
cat >> /etc/hosts << 'END'
127.0.0.1   ${subdominio_backend}
127.0.0.1   ${subdominio_frontend}
END
EOF

    sleep 2

    sudo su - deploy <<RESTARTPM2
  # Configura PATH para Node.js e PM2
  if [ -d /usr/local/n/versions/node/20.19.4/bin ]; then
    export PATH=/usr/local/n/versions/node/20.19.4/bin:/usr/bin:/usr/local/bin:\$PATH
  else
    export PATH=/usr/bin:/usr/local/bin:\$PATH
  fi
  # Reiniciar apenas processos PM2 relacionados à empresa específica
  # Detecta todos os processos que começam com o nome da empresa (independente do sufixo)
  pm2 list | grep "${empresa}-" | awk '{print \$2}' | while read process_name; do
    if [ -n "\$process_name" ] && [ "\$process_name" != "name" ]; then
      pm2 restart "\$process_name" 2>/dev/null || true
    fi
  done
RESTARTPM2

    sleep 2
  } || trata_erro "config_latencia_base"
}

# Finaliza a instalação e mostra dados de acesso
fim_instalacao_base() {
  [ "${ALTA_PERFORMANCE}" = "1" ] && [ -f "ALTA_PERFORMANCE_MODE" ] && rm -f "ALTA_PERFORMANCE_MODE"
  banner
  printf "   ${GREEN} >> Instalação concluída...\n"
  echo
  printf "   ${WHITE}Banckend: ${BLUE}${subdominio_backend}\n"
  printf "   ${WHITE}Frontend: ${BLUE}${subdominio_frontend}\n"
  echo
  printf "   ${WHITE}Usuário ${BLUE}admin@multi100.com.br\n"
  printf "   ${WHITE}Senha   ${BLUE}adminpro\n"
  echo
  printf "${WHITE}>> Aperte qualquer tecla para voltar ao menu principal ou CTRL+C Para finalizar esse script\n"
  read -p ""
  echo
}

################################################################
#                         ATUALIZAÇÃO                          #
################################################################

backup_app_atualizar() {
  # Verifica se a variável empresa está definida (já foi carregada por selecionar_instancia_atualizar)
  if [ -z "${empresa}" ]; then
    printf "${RED} >> ERRO: Variável 'empresa' não está definida!\n${WHITE}"
    exit 1
  fi
  
  source /home/deploy/${empresa}/backend/.env
  {
    banner
    printf "${WHITE} >> Antes de atualizar deseja fazer backup do banco de dados? ${GREEN}S/${RED}N:${WHITE}\n"
    echo
    read -p "> " confirmacao_backup
    echo
    confirmacao_backup=$(echo "${confirmacao_backup}" | tr '[:lower:]' '[:upper:]')
    if [ "${confirmacao_backup}" == "S" ]; then
      db_password=$(grep "DB_PASS=" /home/deploy/${empresa}/backend/.env | cut -d '=' -f2)
      [ ! -d "/home/deploy/backups" ] && mkdir -p "/home/deploy/backups"
      backup_file="/home/deploy/backups/${empresa}_$(date +%d-%m-%Y_%Hh).sql"
      PGPASSWORD="${db_password}" pg_dump -U ${empresa} -h localhost ${empresa} >"${backup_file}"
      printf "${GREEN} >> Backup do banco de dados ${empresa} concluído. Arquivo de backup: ${backup_file}\n"
      sleep 2
    else
      printf " >> Continuando a atualização...\n"
      echo
    fi

    sleep 2
  } || trata_erro "backup_app_atualizar"
}

baixa_codigo_atualizar() {
  banner
  printf "${WHITE} >> Recuperando Permissões... \n"
  echo
  sleep 2
  chown deploy -R /home/deploy/${empresa}
  chmod 775 -R /home/deploy/${empresa}

  sleep 2

  banner
  printf "${WHITE} >> Parando Instancias da empresa ${empresa}... \n"
  echo
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

  # Verifica se a variável empresa está definida (já foi carregada por selecionar_instancia_atualizar)
  if [ -z "${empresa}" ]; then
    printf "${RED} >> ERRO: Variável 'empresa' não está definida!\n${WHITE}"
    exit 1
  fi
  
  banner
  printf "${WHITE} >> Atualizando a Aplicação da Empresa ${empresa}... \n"
  echo
  sleep 2

  source /home/deploy/${empresa}/frontend/.env
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
  
  printf "${WHITE} >> Atualizando Backend da empresa ${empresa}...\n"
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
  printf "${WHITE} >> Atualizando Frontend da empresa ${empresa}...\n"
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
  menu
}

otimiza_banco_atualizar() {
  # Verifica se a variável empresa está definida (já foi carregada por selecionar_instancia_atualizar)
  if [ -z "${empresa}" ]; then
    printf "${RED} >> ERRO: Variável 'empresa' não está definida!\n${WHITE}"
    return 0
  fi
  
  [ -f "$ARQUIVO_VARIAVEIS" ] && source "$ARQUIVO_VARIAVEIS" 2>/dev/null
  if [ "${ALTA_PERFORMANCE}" = "1" ]; then
    db_host_opt="127.0.0.1"
    db_port_opt="7532"
  else
    db_host_opt="localhost"
    db_port_opt="5432"
  fi
  
  banner
  printf "${WHITE} >> Realizando Manutenção do Banco de Dados da empresa ${empresa}... \n"
  echo
  {
    db_password=$(grep "DB_PASS=" /home/deploy/${empresa}/backend/.env | cut -d '=' -f2)
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
  # Verifica se a variável empresa está definida (já foi carregada por selecionar_instancia_atualizar)
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

# Adicionar função para instalar transcrição de áudio nativa
instalar_transcricao_audio_nativa() {
  banner
  printf "${WHITE} >> Instalando Transcrição de Áudio Nativa...\n"
  echo
  
  # Verificar e selecionar instância para instalar a transcrição
  if ! selecionar_instancia_atualizar; then
    printf "${RED} >> Erro ao selecionar instância. Voltando ao menu principal...${WHITE}\n"
    sleep 2
    menu
    return
  fi
  
  # Identificar o arquivo de variáveis usado (salvo pela função selecionar_instancia_atualizar)
  # A função já salva o arquivo em ARQUIVO_VARIAVEIS_USADO como variável global
  ARQUIVO_VARIAVEIS_INSTANCIA="${ARQUIVO_VARIAVEIS_USADO:-}"
  
  # Se não foi salvo pela função, tentar identificar agora baseado na empresa atual
  if [ -z "$ARQUIVO_VARIAVEIS_INSTANCIA" ] || [ ! -f "$ARQUIVO_VARIAVEIS_INSTANCIA" ]; then
    INSTALADOR_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    local empresa_atual="${empresa}"
    
    # Verificar se é a instalação base
    if [ -f "${INSTALADOR_DIR}/${ARQUIVO_VARIAVEIS}" ]; then
      local temp_empresa_base=""
      source "${INSTALADOR_DIR}/${ARQUIVO_VARIAVEIS}" 2>/dev/null
      temp_empresa_base="${empresa:-}"
      empresa="${empresa_atual}"
      
      if [ "${temp_empresa_base}" = "${empresa_atual}" ]; then
        ARQUIVO_VARIAVEIS_INSTANCIA="${INSTALADOR_DIR}/${ARQUIVO_VARIAVEIS}"
      fi
    fi
    
    # Se não é a base, procurar em instâncias adicionais
    if [ -z "$ARQUIVO_VARIAVEIS_INSTANCIA" ] || [ ! -f "$ARQUIVO_VARIAVEIS_INSTANCIA" ]; then
      for arquivo_instancia in "${INSTALADOR_DIR}"/VARIAVEIS_INSTALACAO_INSTANCIA_*; do
        if [ -f "$arquivo_instancia" ]; then
          local temp_empresa_inst=""
          source "$arquivo_instancia" 2>/dev/null
          temp_empresa_inst="${empresa:-}"
          empresa="${empresa_atual}"
          
          if [ "${temp_empresa_inst}" = "${empresa_atual}" ]; then
            ARQUIVO_VARIAVEIS_INSTANCIA="$arquivo_instancia"
            break
          fi
        fi
      done
    fi
  fi
  
  # Verificar se a instância existe
  if [ ! -d "/home/deploy/${empresa}" ]; then
    printf "${RED} >> ERRO: Diretório /home/deploy/${empresa} não existe!${WHITE}\n"
    sleep 2
    menu
    return
  fi
  
  # Verificar se a pasta api_transcricao existe
  if [ ! -d "/home/deploy/${empresa}/api_transcricao" ]; then
    printf "${RED} >> ERRO: Pasta api_transcricao não encontrada em /home/deploy/${empresa}/api_transcricao${WHITE}\n"
    printf "${YELLOW} >> A pasta api_transcricao deve existir no repositório da instância.${WHITE}\n"
    sleep 3
    menu
    return
  fi
  
  # Solicitar porta da transcrição
  banner
  printf "${WHITE} >> Configuração da Porta de Transcrição${WHITE}\n"
  echo
  printf "${YELLOW}══════════════════════════════════════════════════════════════════${WHITE}\n"
  echo
  printf "${WHITE} >> Digite a porta para o serviço de transcrição (padrão: 4002):${WHITE}\n"
  read -p "> " porta_transcricao
  
  # Validar porta
  if [ -z "$porta_transcricao" ]; then
    porta_transcricao="4002"
    printf "${YELLOW} >> Usando porta padrão: 4002${WHITE}\n"
  fi
  
  # Validar se é um número válido
  if ! [[ "$porta_transcricao" =~ ^[0-9]+$ ]]; then
    printf "${RED} >> ERRO: Porta inválida! Deve ser um número.${WHITE}\n"
    sleep 2
    menu
    return
  fi
  
  # Verificar se a porta está em uso
  if lsof -i:${porta_transcricao} &>/dev/null; then
    printf "${YELLOW} >> ATENÇÃO: A porta ${porta_transcricao} já está em uso.${WHITE}\n"
    printf "${WHITE} >> Deseja continuar mesmo assim? (S/N):${WHITE}\n"
    read -p "> " continuar_porta
    continuar_porta=$(echo "${continuar_porta}" | tr '[:lower:]' '[:upper:]')
    if [ "${continuar_porta}" != "S" ]; then
      printf "${GREEN} >> Operação cancelada. Voltando ao menu...${WHITE}\n"
      sleep 2
      menu
      return
    fi
  fi
  
  printf "${GREEN} >> Porta selecionada: ${BLUE}${porta_transcricao}${WHITE}\n"
  echo
  sleep 2
  
  # Instalar bibliotecas compartilhadas do ffmpeg necessárias para transcrição
  banner
  printf "${WHITE} >> Instalando bibliotecas compartilhadas do ffmpeg...\n"
  echo
  
  {
    sudo apt-get update -qq
    
    # Verificar se o ffmpeg está instalado, se não estiver, instalar
    if ! command -v ffmpeg >/dev/null 2>&1; then
      printf "${YELLOW} >> FFmpeg não encontrado. Instalando...${WHITE}\n"
      sudo apt-get install -y ffmpeg
    fi
    
    printf "${WHITE} >> Verificando dependências do ffmpeg instalado...${WHITE}\n"
    
    # Verificar quais bibliotecas o ffmpeg precisa usando ldd
    FFMPEG_PATH=$(which ffmpeg)
    if [ -n "$FFMPEG_PATH" ] && [ -f "$FFMPEG_PATH" ]; then
      printf "${WHITE} >> Analisando dependências de: $FFMPEG_PATH${WHITE}\n"
      MISSING_LIBS=$(ldd "$FFMPEG_PATH" 2>/dev/null | grep "not found" | awk '{print $1}' | sed 's/://' || true)
      
      if [ -n "$MISSING_LIBS" ]; then
        printf "${YELLOW} >> Bibliotecas faltantes detectadas:${WHITE}\n"
        echo "$MISSING_LIBS" | while read lib; do
          printf "${YELLOW}   - $lib${WHITE}\n"
        done
        
        # Extrair versão da biblioteca faltante e tentar instalar
        for lib in $MISSING_LIBS; do
          if echo "$lib" | grep -qE "libav(device|format|codec)"; then
            # Extrair número da versão (ex: libavdevice.so.62 -> 62)
            VERSION=$(echo "$lib" | grep -oE '[0-9]+' | head -1)
            LIB_NAME=$(echo "$lib" | sed 's/\.so.*//' | sed 's/lib//')
            
            if [ -n "$VERSION" ] && [ -n "$LIB_NAME" ]; then
              printf "${WHITE} >> Tentando instalar $LIB_NAME versão $VERSION...${WHITE}\n"
              # Tentar diferentes formatos de nome de pacote
              sudo apt-get install -y "lib${LIB_NAME}${VERSION}" 2>/dev/null || \
              sudo apt-get install -y "lib${LIB_NAME}${VERSION:0:2}" 2>/dev/null || \
              sudo apt-get install -y "lib${LIB_NAME}" 2>/dev/null || true
            fi
          fi
        done
      fi
    fi
    
    printf "${WHITE} >> Instalando todas as bibliotecas do ffmpeg...${WHITE}\n"
    
    # Primeiro, tentar corrigir dependências quebradas
    sudo apt-get install -f -y 2>/dev/null || true
    
    # Instalar ffmpeg e todas suas dependências de uma vez
    sudo apt-get install --reinstall -y ffmpeg 2>/dev/null || true
    
    # Instalar bibliotecas específicas - tentar todas as versões possíveis
    printf "${WHITE} >> Instalando bibliotecas libavdevice, libavformat e libavcodec (todas as versões)...${WHITE}\n"
    
    # Instalar todas as versões disponíveis (não usar elif, instalar todas que estiverem disponíveis)
    sudo apt-get install -y \
      libavdevice58 libavformat58 libavcodec58 \
      libavdevice59 libavformat59 libavcodec59 \
      libavdevice60 libavformat60 libavcodec60 \
      libavdevice61 libavformat61 libavcodec61 \
      libavdevice62 libavformat62 libavcodec62 \
      libavdevice63 libavformat63 libavcodec63 \
      libavdevice libavformat libavcodec \
      2>/dev/null || true
    
    # Instalar pacotes de desenvolvimento também (podem conter as bibliotecas necessárias)
    sudo apt-get install -y \
      libavdevice-dev libavformat-dev libavcodec-dev \
      libavutil-dev libswscale-dev libswresample-dev \
      2>/dev/null || true
    
    # Adicionar PPA do ffmpeg se disponível (para versões mais recentes)
    if ! grep -q "ppa:savoury1/ffmpeg" /etc/apt/sources.list.d/*.list 2>/dev/null; then
      printf "${WHITE} >> Adicionando PPA do ffmpeg para versões mais recentes...${WHITE}\n"
      sudo add-apt-repository -y ppa:savoury1/ffmpeg5 2>/dev/null || \
      sudo add-apt-repository -y ppa:savoury1/ffmpeg6 2>/dev/null || true
      sudo apt-get update -qq 2>/dev/null || true
      
      # Tentar instalar novamente após adicionar o PPA
      sudo apt-get install -y \
        libavdevice62 libavformat62 libavcodec62 \
        libavdevice63 libavformat63 libavcodec63 \
        2>/dev/null || true
    fi
    
    # Atualizar cache do ldconfig para que o sistema encontre as bibliotecas
    printf "${WHITE} >> Atualizando cache de bibliotecas compartilhadas...${WHITE}\n"
    sudo ldconfig 2>/dev/null || true
    
    # Verificar novamente quais bibliotecas o ffmpeg precisa
    if [ -n "$FFMPEG_PATH" ] && [ -f "$FFMPEG_PATH" ]; then
      MISSING_LIBS_AFTER=$(ldd "$FFMPEG_PATH" 2>/dev/null | grep "not found" | awk '{print $1}' | sed 's/://' || true)
      
      if [ -z "$MISSING_LIBS_AFTER" ]; then
        printf "${GREEN} >> ✓ Todas as dependências do ffmpeg foram instaladas com sucesso!${WHITE}\n"
      else
        printf "${YELLOW} >> AVISO: Ainda há bibliotecas faltantes:${WHITE}\n"
        echo "$MISSING_LIBS_AFTER" | while read lib; do
          printf "${YELLOW}   - $lib${WHITE}\n"
        done
        
        # Se ainda faltam bibliotecas, pode ser que o ffmpeg foi instalado do BtbN/FFmpeg-Builds
        # Nesse caso, precisamos instalar o ffmpeg do repositório do sistema
        printf "${WHITE} >> O ffmpeg pode ter sido instalado de fonte externa. Reinstalando do repositório do sistema...${WHITE}\n"
        sudo apt-get remove -y ffmpeg 2>/dev/null || true
        sudo apt-get install -y ffmpeg 2>/dev/null || true
        sudo apt-get install -f -y 2>/dev/null || true
        sudo ldconfig 2>/dev/null || true
        
        # Verificar novamente
        MISSING_LIBS_FINAL=$(ldd "$(which ffmpeg)" 2>/dev/null | grep "not found" | awk '{print $1}' | sed 's/://' || true)
        if [ -z "$MISSING_LIBS_FINAL" ]; then
          printf "${GREEN} >> ✓ FFmpeg reinstalado e funcionando!${WHITE}\n"
        else
          printf "${RED} >> ERRO: Ainda há bibliotecas faltantes após reinstalação.${WHITE}\n"
          printf "${YELLOW} >> Bibliotecas faltantes: $MISSING_LIBS_FINAL${WHITE}\n"
        fi
      fi
    fi
    
    # Verificação final usando ldconfig
    if ldconfig -p | grep -q libavdevice && ldconfig -p | grep -q libavformat && ldconfig -p | grep -q libavcodec; then
      printf "${GREEN} >> ✓ Bibliotecas do ffmpeg verificadas no sistema!${WHITE}\n"
    else
      printf "${YELLOW} >> AVISO: Algumas bibliotecas podem não estar no cache do sistema.${WHITE}\n"
    fi
    
    # Teste final: tentar executar o ffmpeg para verificar se funciona
    if ffmpeg -version >/dev/null 2>&1; then
      printf "${GREEN} >> ✓ FFmpeg está funcionando corretamente!${WHITE}\n"
    else
      printf "${YELLOW} >> AVISO: FFmpeg pode ter problemas. Verifique manualmente.${WHITE}\n"
    fi
    
  } || {
    printf "${YELLOW} >> AVISO: Algumas bibliotecas podem não ter sido instaladas. Continuando...${WHITE}\n"
  }
  
  echo
  sleep 2
  
  # Atualizar .env do backend com a nova porta
  banner
  printf "${WHITE} >> Atualizando configuração do backend...\n"
  echo
  
  local env_file="/home/deploy/${empresa}/backend/.env"
  if [ -f "$env_file" ]; then
    # Verificar se TRANSCRIBE_URL já existe
    if grep -q "^TRANSCRIBE_URL=" "$env_file"; then
      # Atualizar porta existente
      sed -i "s|^TRANSCRIBE_URL=.*|TRANSCRIBE_URL=http://localhost:${porta_transcricao}|" "$env_file"
      printf "${GREEN} >> TRANSCRIBE_URL atualizado para http://localhost:${porta_transcricao}${WHITE}\n"
    else
      # Adicionar TRANSCRIBE_URL se não existir
      echo "" >> "$env_file"
      echo "# API de Transcrição de Audio" >> "$env_file"
      echo "TRANSCRIBE_URL=http://localhost:${porta_transcricao}" >> "$env_file"
      printf "${GREEN} >> TRANSCRIBE_URL adicionado: http://localhost:${porta_transcricao}${WHITE}\n"
    fi
  else
    printf "${RED} >> ERRO: Arquivo .env não encontrado em $env_file${WHITE}\n"
    sleep 2
    menu
    return
  fi
  
  echo
  sleep 2
  
  # IMPORTANTE: Reiniciar o PM2 do backend para aplicar a nova variável TRANSCRIBE_URL
  banner
  printf "${WHITE} >> Reiniciando backend para aplicar a nova configuração TRANSCRIBE_URL...\n"
  echo
  
  sudo su - deploy <<RESTARTBACKEND
  # Configura PATH para Node.js e PM2
  if [ -d /usr/local/n/versions/node/20.19.4/bin ]; then
    export PATH=/usr/local/n/versions/node/20.19.4/bin:/usr/bin:/usr/local/bin:\$PATH
  else
    export PATH=/usr/bin:/usr/local/bin:\$PATH
  fi
  
  # Reiniciar apenas o backend desta instância para carregar a nova variável TRANSCRIBE_URL
  if pm2 list | grep -qE "${empresa}-backend[[:space:]]"; then
    printf "Reiniciando backend ${empresa}-backend...\n"
    pm2 restart ${empresa}-backend
    pm2 save
    printf "${GREEN} >> Backend reiniciado com sucesso! Nova porta TRANSCRIBE_URL aplicada.${WHITE}\n"
  else
    printf "${YELLOW} >> AVISO: Backend ${empresa}-backend não encontrado no PM2${WHITE}\n"
    printf "${YELLOW} >> A configuração foi salva, mas será aplicada quando o backend for iniciado${WHITE}\n"
  fi
RESTARTBACKEND
  
  echo
  sleep 2
  
  # Verificar se há processos PM2 existentes desta instância (apenas se já estiver instalado)
  # Na primeira instalação, não haverá processos para parar
  banner
  printf "${WHITE} >> Verificando se há processos PM2 existentes da transcrição...\n"
  echo
  
  sudo su - deploy <<CHECKPM2TRANSC
  # Configura PATH para Node.js e PM2
  if [ -d /usr/local/n/versions/node/20.19.4/bin ]; then
    export PATH=/usr/local/n/versions/node/20.19.4/bin:/usr/bin:/usr/local/bin:\$PATH
  else
    export PATH=/usr/bin:/usr/local/bin:\$PATH
  fi
  
  # Verificar se existe processo PM2 desta instância ESPECÍFICA e parar apenas se existir
  # IMPORTANTE: Só para processos com o nome exato desta instância (${empresa}-transcricao)
  # NÃO afeta processos genéricos como "transcricao" ou processos de outras instâncias
  # Na primeira instalação, não haverá nada para parar
    if pm2 list | grep -qE "${empresa}-transcricao[[:space:]]"; then
    printf "Processos PM2 encontrados para a instância ${empresa}. Parando apenas processos desta instância...\n"
    # Parar APENAS processos com o nome exato desta instância
    # Não para processos genéricos ou de outras instâncias
    pm2 stop ${empresa}-transcricao 2>/dev/null || true
    pm2 delete ${empresa}-transcricao 2>/dev/null || true
    pm2 save 2>/dev/null || true
    printf "Processos da instância ${empresa} parados com sucesso.\n"
  else
    printf "Nenhum processo PM2 encontrado para esta instância (${empresa}). Primeira instalação ou processo não existe.\n"
    printf "Processos de outras instâncias (incluindo instalação principal) não serão afetados.\n"
  fi
CHECKPM2TRANSC
  
  echo
  sleep 2
  
  # Atualizar main.py com a nova porta
  banner
  printf "${WHITE} >> Atualizando configuração do main.py...\n"
  echo
  
  local main_py="/home/deploy/${empresa}/api_transcricao/main.py"
  if [ -f "$main_py" ]; then
    # Fazer backup do arquivo original
    cp "$main_py" "${main_py}.bak" 2>/dev/null || true
    
    # Atualizar porta no app.run com diferentes padrões usando Python para maior precisão
    python3 <<PYTHON_SCRIPT
import re
import sys

file_path = "$main_py"
new_port = "$porta_transcricao"

try:
    with open(file_path, 'r', encoding='utf-8') as f:
        content = f.read()
    
    original_content = content
    
    # Substituir port=XXXX ou port = XXXX (qualquer número de dígitos)
    # Padrão 1: app.run(host='0.0.0.0', port=4002, debug=True)
    # Padrão 2: app.run(host="0.0.0.0", port=4002, debug=True)
    # Padrão 3: app.run(host='0.0.0.0', port = 4002, debug=True)
    # Preservar o formato original (com ou sem espaços)
    def replace_port(match):
        # Manter o formato original (port= ou port =)
        original = match.group(0)
        if ' = ' in original:
            return f"port = {new_port}"
        else:
            return f"port={new_port}"
    
    content = re.sub(r"port\s*=\s*\d+", replace_port, content)
    
    # Atualizar mensagens de log (português) - qualquer porta
    content = re.sub(r"porta\s+\d+", f"porta {new_port}", content, flags=re.IGNORECASE)
    
    # Atualizar mensagens de log (inglês) - qualquer porta
    content = re.sub(r"Servidor iniciado na porta \d+", f"Servidor iniciado na porta {new_port}", content, flags=re.IGNORECASE)
    content = re.sub(r"Server started on port \d+", f"Server started on port {new_port}", content, flags=re.IGNORECASE)
    
    if content != original_content:
        with open(file_path, 'w', encoding='utf-8') as f:
            f.write(content)
        print(f"SUCCESS: Porta atualizada para {new_port}")
        sys.exit(0)
    else:
        print(f"WARNING: Nenhuma alteração detectada. Verifique se a porta já está correta ou se o padrão é diferente.")
        sys.exit(1)
except Exception as e:
    print(f"ERROR: {str(e)}")
    sys.exit(1)
PYTHON_SCRIPT
    
    if [ $? -eq 0 ]; then
      printf "${GREEN} >> Porta atualizada no main.py para ${porta_transcricao}${WHITE}\n"
      
      # Verificar se a porta foi realmente alterada
      if grep -q "port=${porta_transcricao}\|port = ${porta_transcricao}" "$main_py"; then
        printf "${GREEN} >> Verificação: Porta ${porta_transcricao} confirmada no main.py${WHITE}\n"
      else
        printf "${YELLOW} >> AVISO: Não foi possível verificar a porta no main.py${WHITE}\n"
      fi
    else
      # Fallback para sed se Python falhar
      printf "${YELLOW} >> Tentando método alternativo (sed)...${WHITE}\n"
      
      # Substituir qualquer porta de 4 dígitos
      sed -i "s|port=[0-9][0-9][0-9][0-9]|port=${porta_transcricao}|g" "$main_py" 2>/dev/null || true
      sed -i "s|port = [0-9][0-9][0-9][0-9]|port = ${porta_transcricao}|g" "$main_py" 2>/dev/null || true
      sed -i "s|porta [0-9][0-9][0-9][0-9]|porta ${porta_transcricao}|g" "$main_py" 2>/dev/null || true
      
      # Verificar novamente
      if grep -q "port=${porta_transcricao}\|port = ${porta_transcricao}" "$main_py"; then
        printf "${GREEN} >> Porta atualizada com sucesso usando sed${WHITE}\n"
      else
        printf "${RED} >> ERRO: Não foi possível atualizar a porta no main.py${WHITE}\n"
        printf "${YELLOW} >> Por favor, verifique manualmente o arquivo: $main_py${WHITE}\n"
      fi
    fi
    
    # Mostrar a linha do app.run para confirmação
    printf "${WHITE} >> Linha app.run encontrada:${WHITE}\n"
    grep "app.run" "$main_py" | head -1 || printf "${YELLOW} >> Não foi possível encontrar app.run${WHITE}\n"
    
  else
    printf "${YELLOW} >> AVISO: Arquivo main.py não encontrado em $main_py${WHITE}\n"
    printf "${YELLOW} >> A porta será configurada apenas no .env do backend${WHITE}\n"
  fi
  
  echo
  sleep 2
  
  # Fazer backup do main.py atualizado ANTES de executar o script
  # O script pode fazer git checkout/reset que sobrescreve o main.py
  local main_py="/home/deploy/${empresa}/api_transcricao/main.py"
  local main_py_backup_protected="${main_py}.protected_backup"
  if [ -f "$main_py" ]; then
    printf "${WHITE} >> Criando backup protegido do main.py atualizado...${WHITE}\n"
    cp "$main_py" "$main_py_backup_protected" 2>/dev/null || true
    # Garantir que o backup tenha permissões corretas para deploy
    chown deploy:deploy "$main_py_backup_protected" 2>/dev/null || true
    chmod 644 "$main_py_backup_protected" 2>/dev/null || true
    printf "${GREEN} >> Backup criado: ${main_py_backup_protected}${WHITE}\n"
    echo
  fi
  
  # Executar script de instalação como usuário DEPLOY (não root)
  # Isso garante que o PM2 não será iniciado como root
  banner
  printf "${WHITE} >> Executando script de instalação da transcrição como usuário DEPLOY...\n"
  printf "${GREEN} >> Isso garante que o PM2 não será iniciado como root${WHITE}\n"
  echo
  
  local script_path="/home/deploy/${empresa}/api_transcricao/install-python-app.sh"
  if [ -f "$script_path" ]; then
    chmod 775 "$script_path"
    
    # Passar o nome do app como variável de ambiente (padrão: ${empresa}-transcricao)
    # O nome é obtido do arquivo de variáveis da instância
    export PM2_APP_NAME="${empresa}-transcricao"
    export APP_NAME="${empresa}-transcricao"
    export PM2_NAME="${empresa}-transcricao"
    
    # Executar o script como usuário DEPLOY para evitar que inicie PM2 como root
    # Criar um script temporário para executar como deploy
    local temp_script="/tmp/exec_install_transc_${empresa}.sh"
    cat > "$temp_script" <<TEMPSCRIPT
#!/bin/bash
# Configura PATH para Node.js e PM2
if [ -d /usr/local/n/versions/node/20.19.4/bin ]; then
  export PATH=/usr/local/n/versions/node/20.19.4/bin:/usr/bin:/usr/local/bin:\$PATH
else
  export PATH=/usr/bin:/usr/local/bin:\$PATH
fi

cd /home/deploy/${empresa}/api_transcricao || exit 1

# Passar variáveis de ambiente
export PM2_APP_NAME="${empresa}-transcricao"
export APP_NAME="${empresa}-transcricao"
export PM2_NAME="${empresa}-transcricao"

# Executar o script passando o nome automaticamente quando ele pedir
# Redirecionar stderr para evitar mensagens de sudo que podem aparecer
echo "${empresa}-transcricao" | bash ${script_path} 2>/dev/null || {
  # Se falhar, tentar novamente sem redirecionar stderr para ver o erro real
  echo "${empresa}-transcricao" | bash ${script_path} || true
}
TEMPSCRIPT
    
    chmod +x "$temp_script"
    chown deploy:deploy "$temp_script" 2>/dev/null || true
    
    # Executar o script temporário como deploy
    # Redirecionar stderr para evitar mensagens de sudo que podem aparecer do script interno
    # O script install-python-app.sh pode tentar executar comandos sudo internamente
    # Esses avisos não impedem a instalação, então podemos ignorá-los
    sudo su - deploy -c "bash $temp_script" 2>&1 | grep -v "sudo: a terminal is required\|sudo: a password is required\|multiflcw" || true
    
    # Remover script temporário
    rm -f "$temp_script" 2>/dev/null || true
    
    printf "${GREEN} >> Script de instalação executado!${WHITE}\n"
    printf "${GREEN} >> Nome do app PM2 usado automaticamente: ${BLUE}${empresa}-transcricao${WHITE}\n"
    echo
    
    # Instalar dependências Python após o script de instalação
    banner
    printf "${WHITE} >> Verificando e instalando dependências Python...\n"
    echo
    
    # Tentar instalar pip3 primeiro (se não estiver disponível)
    if ! command -v pip3 &>/dev/null && ! python3 -m pip --version &>/dev/null; then
      printf "${YELLOW} >> pip3 não está disponível. Tentando instalar via apt-get...${WHITE}\n"
      if sudo -n apt-get update -qq && sudo -n apt-get install -y python3-pip 2>/dev/null; then
        printf "${GREEN} >> pip3 instalado com sucesso!${WHITE}\n"
      else
        printf "${YELLOW} >> Não foi possível instalar pip3 automaticamente (pode requerer senha)${WHITE}\n"
        printf "${YELLOW} >> Tentando instalar Flask diretamente via apt-get...${WHITE}\n"
        if sudo -n apt-get install -y python3-flask python3-flask-cors python3-requests 2>/dev/null; then
          printf "${GREEN} >> Flask instalado via apt-get!${WHITE}\n"
        else
          printf "${RED} >> AVISO: Não foi possível instalar pip3 ou Flask automaticamente${WHITE}\n"
          printf "${YELLOW} >> Execute manualmente: sudo apt-get install -y python3-pip python3-flask python3-flask-cors${WHITE}\n"
        fi
      fi
    fi
    
    # Verificar se Flask está disponível antes de continuar
    if ! sudo su - deploy -c "python3 -c 'import flask'" 2>/dev/null; then
      printf "${YELLOW} >> Flask não está disponível. Tentando instalar via apt-get...${WHITE}\n"
      if sudo -n apt-get install -y python3-flask python3-flask-cors python3-requests 2>/dev/null; then
        printf "${GREEN} >> Flask instalado via apt-get!${WHITE}\n"
      else
        printf "${YELLOW} >> Não foi possível instalar via apt-get sem senha. Continuando...${WHITE}\n"
      fi
    fi
    
    sudo su - deploy <<INSTALLPYTHONDEP
    # Configura PATH
    if [ -d /usr/local/n/versions/node/20.19.4/bin ]; then
      export PATH=/usr/local/n/versions/node/20.19.4/bin:/usr/bin:/usr/local/bin:\$PATH
    else
      export PATH=/usr/bin:/usr/local/bin:\$PATH
    fi
    
    TRANSC_DIR="/home/deploy/${empresa}/api_transcricao"
    cd "\$TRANSC_DIR" || exit 1
    
    # Verificar se pip3 está disponível
    if ! command -v pip3 &> /dev/null; then
      printf "${YELLOW} >> pip3 não encontrado. Tentando instalar...${WHITE}\n"
      
      # Tentar instalar pip3 usando apt-get (requer sudo, mas tenta sem senha)
      if sudo -n apt-get install -y python3-pip 2>/dev/null; then
        printf "${GREEN} >> pip3 instalado com sucesso via apt-get${WHITE}\n"
      else
        printf "${YELLOW} >> Não foi possível instalar pip3 via apt-get (pode requerer senha)${WHITE}\n"
        printf "${YELLOW} >> Tentando métodos alternativos...${WHITE}\n"
        
        # Tentar usar python3 -m pip (geralmente disponível mesmo sem pip3 instalado)
        if python3 -m pip --version &>/dev/null; then
          printf "${GREEN} >> python3 -m pip está disponível${WHITE}\n"
          alias pip3="python3 -m pip"
        else
          # Tentar instalar pip3 usando get-pip.py (não requer sudo)
          printf "${YELLOW} >> Tentando instalar pip usando get-pip.py...${WHITE}\n"
          curl -sS https://bootstrap.pypa.io/get-pip.py -o /tmp/get-pip.py 2>/dev/null || wget -q https://bootstrap.pypa.io/get-pip.py -O /tmp/get-pip.py 2>/dev/null || true
          if [ -f /tmp/get-pip.py ]; then
            python3 /tmp/get-pip.py --user --break-system-packages 2>&1 | grep -v "already installed\|Requirement already satisfied" || true
            rm -f /tmp/get-pip.py 2>/dev/null || true
            # Verificar se pip3 está disponível agora
            if command -v pip3 &>/dev/null || python3 -m pip --version &>/dev/null; then
              printf "${GREEN} >> pip instalado com sucesso${WHITE}\n"
              if ! command -v pip3 &>/dev/null; then
                alias pip3="python3 -m pip"
              fi
            fi
          fi
        fi
      fi
    fi
    
    # Se ainda não tiver pip3, usar python3 -m pip como fallback
    if ! command -v pip3 &> /dev/null && ! python3 -m pip --version &>/dev/null; then
      printf "${RED} >> ERRO CRÍTICO: pip3 e python3 -m pip não estão disponíveis!${WHITE}\n"
      printf "${YELLOW} >> Instalando pip3 manualmente...${WHITE}\n"
      printf "${YELLOW} >> Execute manualmente: sudo apt-get install -y python3-pip${WHITE}\n"
      printf "${YELLOW} >> Ou instale Flask via apt: sudo apt-get install -y python3-flask${WHITE}\n"
      
      # Tentar instalar Flask via apt-get como último recurso
      if sudo -n apt-get install -y python3-flask python3-flask-cors 2>/dev/null; then
        printf "${GREEN} >> Flask instalado via apt-get${WHITE}\n"
      else
        printf "${RED} >> Não foi possível instalar Flask automaticamente${WHITE}\n"
        printf "${RED} >> Por favor, execute manualmente: sudo apt-get install -y python3-pip python3-flask python3-flask-cors${WHITE}\n"
      fi
    fi
    
    # Obter o caminho do site-packages do usuário
    USER_SITE=\$(python3 -m site --user-site 2>/dev/null || echo "")
    if [ -n "\$USER_SITE" ]; then
      export PYTHONPATH="\$USER_SITE:\$PYTHONPATH"
    fi
    
    # Determinar comando pip a usar
    PIP_CMD="pip3"
    if ! command -v pip3 &>/dev/null; then
      if python3 -m pip --version &>/dev/null; then
        PIP_CMD="python3 -m pip"
        printf "${GREEN} >> Usando python3 -m pip como alternativa${WHITE}\n"
      else
        printf "${RED} >> ERRO: pip3 e python3 -m pip não estão disponíveis!${WHITE}\n"
        printf "${YELLOW} >> Instale pip3 manualmente: sudo apt-get install -y python3-pip${WHITE}\n"
        exit 1
      fi
    fi
    
    # Instalar dependências (usar --break-system-packages para ambientes externally managed)
    if [ -f "\$TRANSC_DIR/requirements.txt" ]; then
      printf "${GREEN} >> Instalando dependências do requirements.txt...${WHITE}\n"
      # Tentar com --user primeiro
      INSTALL_OUTPUT=\$(\$PIP_CMD install --user -r "\$TRANSC_DIR/requirements.txt" 2>&1)
      INSTALL_STATUS=\$?
      if [ \$INSTALL_STATUS -eq 0 ] || echo "\$INSTALL_OUTPUT" | grep -q "already satisfied\|Requirement already satisfied"; then
        printf "${GREEN} >> ✓ Dependências instaladas${WHITE}\n"
      elif echo "\$INSTALL_OUTPUT" | grep -q "externally-managed-environment"; then
        # Se falhar por externally-managed, usar --break-system-packages com --user
        printf "${YELLOW} >> Ambiente externally-managed detectado. Usando --break-system-packages...${WHITE}\n"
        \$PIP_CMD install --user --break-system-packages -r "\$TRANSC_DIR/requirements.txt" 2>&1 | grep -v "already satisfied\|Requirement already satisfied" || true
        printf "${GREEN} >> ✓ Dependências instaladas${WHITE}\n"
      else
        # Outro erro, mostrar e tentar com --break-system-packages
        printf "${YELLOW} >> Erro na instalação. Tentando com --break-system-packages...${WHITE}\n"
        \$PIP_CMD install --user --break-system-packages -r "\$TRANSC_DIR/requirements.txt" 2>&1 | grep -v "already satisfied\|Requirement already satisfied" || true
        printf "${GREEN} >> ✓ Dependências instaladas${WHITE}\n"
      fi
    else
      printf "${YELLOW} >> requirements.txt não encontrado. Instalando dependências básicas...${WHITE}\n"
      # Tentar com --user primeiro
      INSTALL_OUTPUT=\$(\$PIP_CMD install --user flask flask-cors requests 2>&1)
      INSTALL_STATUS=\$?
      if [ \$INSTALL_STATUS -eq 0 ] || echo "\$INSTALL_OUTPUT" | grep -q "already satisfied\|Requirement already satisfied"; then
        printf "${GREEN} >> ✓ Dependências básicas instaladas${WHITE}\n"
      elif echo "\$INSTALL_OUTPUT" | grep -q "externally-managed-environment"; then
        # Se falhar por externally-managed, usar --break-system-packages com --user
        printf "${YELLOW} >> Ambiente externally-managed detectado. Usando --break-system-packages...${WHITE}\n"
        \$PIP_CMD install --user --break-system-packages flask flask-cors requests 2>&1 | grep -v "already satisfied\|Requirement already satisfied" || true
        printf "${GREEN} >> ✓ Dependências básicas instaladas (Flask, Flask-CORS, Requests)${WHITE}\n"
      else
        # Outro erro, mostrar e tentar com --break-system-packages
        printf "${YELLOW} >> Erro na instalação. Tentando com --break-system-packages...${WHITE}\n"
        \$PIP_CMD install --user --break-system-packages flask flask-cors requests 2>&1 | grep -v "already satisfied\|Requirement already satisfied" || true
        printf "${GREEN} >> ✓ Dependências básicas instaladas${WHITE}\n"
      fi
    fi
    
    # Atualizar USER_SITE após instalação
    USER_SITE=\$(python3 -m site --user-site 2>/dev/null || echo "")
    if [ -n "\$USER_SITE" ] && [ -d "\$USER_SITE" ]; then
      export PYTHONPATH="\$USER_SITE:\$PYTHONPATH"
      printf "${GREEN} >> PYTHONPATH configurado: \$USER_SITE${WHITE}\n"
    fi
    
    # Verificar se Flask está instalado
    if python3 -c "import flask" 2>/dev/null; then
      printf "${GREEN} >> ✓ Flask está instalado e acessível${WHITE}\n"
    else
      printf "${RED} >> ERRO: Flask não está instalado! Tentando instalar novamente...${WHITE}\n"
      # Tentar com --user primeiro
      INSTALL_OUTPUT=\$(\$PIP_CMD install --user --force-reinstall flask 2>&1)
      INSTALL_STATUS=\$?
      if [ \$INSTALL_STATUS -eq 0 ] || echo "\$INSTALL_OUTPUT" | grep -q "already satisfied\|Requirement already satisfied"; then
        printf "${GREEN} >> Flask reinstalado${WHITE}\n"
      elif echo "\$INSTALL_OUTPUT" | grep -q "externally-managed-environment"; then
        # Se falhar, usar --break-system-packages
        printf "${YELLOW} >> Usando --break-system-packages...${WHITE}\n"
        \$PIP_CMD install --user --break-system-packages --force-reinstall flask 2>&1 || true
      else
        # Tentar com --break-system-packages de qualquer forma
        \$PIP_CMD install --user --break-system-packages --force-reinstall flask 2>&1 || true
      fi
      # Atualizar USER_SITE novamente
      USER_SITE=\$(python3 -m site --user-site 2>/dev/null || echo "")
      if [ -n "\$USER_SITE" ] && [ -d "\$USER_SITE" ]; then
        export PYTHONPATH="\$USER_SITE:\$PYTHONPATH"
      fi
      # Verificar novamente
      if python3 -c "import flask" 2>/dev/null; then
        printf "${GREEN} >> ✓ Flask instalado com sucesso${WHITE}\n"
      else
        printf "${RED} >> ERRO: Ainda não foi possível importar Flask!${WHITE}\n"
      fi
    fi
    echo
INSTALLPYTHONDEP
    
    echo
    sleep 2
    
    # RESTAURAR o main.py atualizado imediatamente após o script
    # O script pode ter feito git checkout/reset que sobrescreveu o main.py
    if [ -f "$main_py_backup_protected" ]; then
      printf "${WHITE} >> Restaurando main.py com a porta correta após execução do script...${WHITE}\n"
      cp "$main_py_backup_protected" "$main_py" 2>/dev/null || true
      
      # Garantir permissões corretas para deploy
      chown deploy:deploy "$main_py" 2>/dev/null || true
      chmod 644 "$main_py" 2>/dev/null || true
      
      # Verificar se a porta está correta após restaurar
      if grep -q "port=${porta_transcricao}\|port = ${porta_transcricao}" "$main_py"; then
        printf "${GREEN} >> ✓ main.py restaurado com porta ${porta_transcricao}${WHITE}\n"
      else
        printf "${YELLOW} >> AVISO: Porta não confirmada após restaurar. Corrigindo agora...${WHITE}\n"
        # Corrigir usando sed forçado
        sed -i "s|port=[0-9]\+|port=${porta_transcricao}|g" "$main_py" 2>/dev/null || true
        sed -i "s|port = [0-9]\+|port = ${porta_transcricao}|g" "$main_py" 2>/dev/null || true
        # Garantir permissões após modificar
        chown deploy:deploy "$main_py" 2>/dev/null || true
        chmod 644 "$main_py" 2>/dev/null || true
      fi
      echo
    fi
    
    # Parar qualquer PM2 que o script possa ter iniciado como DEPLOY
    # IMPORTANTE: Não vamos iniciar o PM2 agora, apenas depois de atualizar o main.py
    sleep 2
    banner
    printf "${WHITE} >> Parando qualquer PM2 iniciado pelo script de instalação...\n"
    echo
    
    # Limpar processos PM2 iniciados como DEPLOY (o script foi executado como deploy)
    sudo su - deploy <<CLEANDEPLOYAFTER
    if [ -d /usr/local/n/versions/node/20.19.4/bin ]; then
      export PATH=/usr/local/n/versions/node/20.19.4/bin:/usr/bin:/usr/local/bin:\$PATH
    else
      export PATH=/usr/bin:/usr/local/bin:\$PATH
    fi
    # Limpar processos desta instância se existirem
    pm2 stop ${empresa}-transcricao 2>/dev/null || true
    pm2 delete ${empresa}-transcricao 2>/dev/null || true
    pm2 stop transc-${empresa} 2>/dev/null || true
    pm2 delete transc-${empresa} 2>/dev/null || true
    pm2 save --force 2>/dev/null || true
CLEANDEPLOYAFTER
    
    printf "${GREEN} >> Processos PM2 parados. Agora vamos atualizar o main.py e iniciar o PM2 corretamente como DEPLOY.${WHITE}\n"
    echo
    sleep 2
    
    # Verificar e corrigir a porta no main.py novamente (caso o script tenha sobrescrito)
    # IMPORTANTE: Esta verificação é CRÍTICA - o script pode ter feito git checkout/reset
    banner
    printf "${WHITE} >> Verificando e corrigindo configuração final da porta...\n"
    printf "${YELLOW} >> (O script pode ter restaurado o main.py do repositório)${WHITE}\n"
    echo
    
    local main_py="/home/deploy/${empresa}/api_transcricao/main.py"
    if [ -f "$main_py" ]; then
      # Verificar qual porta está configurada atualmente
      current_port=$(grep -oP "port\s*=\s*\K\d+" "$main_py" | head -1 || echo "")
      
      if [ -n "$current_port" ]; then
        printf "${WHITE} >> Porta atual encontrada no main.py: ${YELLOW}${current_port}${WHITE}\n"
        printf "${WHITE} >> Porta esperada: ${GREEN}${porta_transcricao}${WHITE}\n"
      fi
      
      if grep -q "port=${porta_transcricao}\|port = ${porta_transcricao}" "$main_py"; then
        printf "${GREEN} >> ✓ Porta ${porta_transcricao} confirmada no main.py${WHITE}\n"
      else
        printf "${RED} >> ✗ ERRO: Porta não está correta no main.py!${WHITE}\n"
        printf "${RED} >> Porta encontrada: ${current_port:-'NÃO ENCONTRADA'}${WHITE}\n"
        printf "${RED} >> Porta esperada: ${porta_transcricao}${WHITE}\n"
        printf "${YELLOW} >> Corrigindo agora...${WHITE}\n"
        
        # Corrigir usando Python novamente
        python3 <<PYTHON_FIX
import re
import sys
import os
import pwd
import grp

file_path = "$main_py"
new_port = "$porta_transcricao"

try:
    with open(file_path, 'r', encoding='utf-8') as f:
        content = f.read()
    
    original_content = content
    
    def replace_port(match):
        original = match.group(0)
        if ' = ' in original:
            return f"port = {new_port}"
        else:
            return f"port={new_port}"
    
    # Substituir TODAS as ocorrências de porta
    content = re.sub(r"port\s*=\s*\d+", replace_port, content)
    content = re.sub(r"porta\s+\d+", f"porta {new_port}", content, flags=re.IGNORECASE)
    content = re.sub(r"Servidor iniciado na porta \d+", f"Servidor iniciado na porta {new_port}", content, flags=re.IGNORECASE)
    content = re.sub(r"Server started on port \d+", f"Server started on port {new_port}", content, flags=re.IGNORECASE)
    
    if content != original_content:
        with open(file_path, 'w', encoding='utf-8') as f:
            f.write(content)
        # Ajustar permissões para deploy
        try:
            deploy_uid = pwd.getpwnam('deploy').pw_uid
            deploy_gid = grp.getgrnam('deploy').gr_gid
            os.chown(file_path, deploy_uid, deploy_gid)
            os.chmod(file_path, 0o644)
        except:
            pass  # Se não conseguir ajustar permissões, continua
        print(f"SUCCESS: Porta corrigida para {new_port}")
        sys.exit(0)
    else:
        print(f"WARNING: Nenhuma alteração necessária")
        sys.exit(0)
except Exception as e:
    print(f"ERROR: {str(e)}")
    sys.exit(1)
PYTHON_FIX
        
        # Garantir permissões após Python (mesmo se não modificou)
        chown deploy:deploy "$main_py" 2>/dev/null || true
        chmod 644 "$main_py" 2>/dev/null || true
        
        # Fallback para sed se Python falhar - substituir QUALQUER porta de 4 dígitos
        if [ $? -ne 0 ]; then
          printf "${YELLOW} >> Tentando correção com sed...${WHITE}\n"
          sed -i "s|port=[0-9][0-9][0-9][0-9]|port=${porta_transcricao}|g" "$main_py" 2>/dev/null || true
          sed -i "s|port = [0-9][0-9][0-9][0-9]|port = ${porta_transcricao}|g" "$main_py" 2>/dev/null || true
          sed -i "s|porta [0-9][0-9][0-9][0-9]|porta ${porta_transcricao}|g" "$main_py" 2>/dev/null || true
          # Garantir permissões após modificar
          chown deploy:deploy "$main_py" 2>/dev/null || true
          chmod 644 "$main_py" 2>/dev/null || true
        fi
        
        # Verificar novamente
        sleep 1
        if grep -q "port=${porta_transcricao}\|port = ${porta_transcricao}" "$main_py"; then
          printf "${GREEN} >> ✓ Porta corrigida com sucesso!${WHITE}\n"
          # Garantir permissões finais
          chown deploy:deploy "$main_py" 2>/dev/null || true
          chmod 644 "$main_py" 2>/dev/null || true
        else
          printf "${RED} >> ✗ ERRO CRÍTICO: Não foi possível corrigir automaticamente${WHITE}\n"
          printf "${YELLOW} >> Por favor, edite manualmente o arquivo: $main_py${WHITE}\n"
          printf "${YELLOW} >> Procure por 'app.run' e altere a porta para: ${porta_transcricao}${WHITE}\n"
          printf "${RED} >> Não será possível continuar sem corrigir a porta!${WHITE}\n"
        fi
      fi
      
      # Mostrar a linha atual do app.run para confirmação
      printf "${WHITE} >> Configuração atual do app.run:${WHITE}\n"
      grep "app.run" "$main_py" | head -1 || printf "${YELLOW} >> Não encontrado${WHITE}\n"
      
      # Verificação final antes de prosseguir
      if ! grep -q "port=${porta_transcricao}\|port = ${porta_transcricao}" "$main_py"; then
        printf "${RED} >> ERRO: Porta ainda não está correta após todas as tentativas!${WHITE}\n"
        printf "${RED} >> Abortando instalação para evitar conflitos.${WHITE}\n"
        return 1
      fi
      
      # Garantir permissões finais antes de iniciar PM2
      printf "${WHITE} >> Ajustando permissões finais dos arquivos para deploy...${WHITE}\n"
      chown deploy:deploy "$main_py" 2>/dev/null || true
      chmod 644 "$main_py" 2>/dev/null || true
      if [ -f "$main_py_backup_protected" ]; then
        chown deploy:deploy "$main_py_backup_protected" 2>/dev/null || true
        chmod 644 "$main_py_backup_protected" 2>/dev/null || true
      fi
      # Ajustar permissões do diretório também
      chown deploy:deploy "/home/deploy/${empresa}/api_transcricao" -R 2>/dev/null || true
      printf "${GREEN} >> ✓ Permissões ajustadas para deploy${WHITE}\n"
      echo
      
      printf "${GREEN} >> ✓ main.py atualizado com sucesso para porta ${porta_transcricao}${WHITE}\n"
      echo
      sleep 2
      
      # Agora sim, iniciar o PM2 DEPOIS de tudo estar instalado e o main.py estar correto
      banner
      printf "${WHITE} >> Iniciando PM2 com a porta correta (${porta_transcricao})...${WHITE}\n"
      printf "${GREEN} >> NOTA: A transcrição roda como DEPLOY (mesmo que backend e frontend)${WHITE}\n"
      echo
      
      # Iniciar o PM2 como usuário DEPLOY (consistente com backend e frontend)
      sudo su - deploy <<STARTPM2CORRECT
      # Configura PATH para Node.js e PM2
      if [ -d /usr/local/n/versions/node/20.19.4/bin ]; then
        export PATH=/usr/local/n/versions/node/20.19.4/bin:/usr/bin:/usr/local/bin:\$PATH
      else
        export PATH=/usr/bin:/usr/local/bin:\$PATH
      fi
      
      TRANSC_DIR="/home/deploy/${empresa}/api_transcricao"
      MAIN_PY_PATH="\$TRANSC_DIR/main.py"
      
      if [ ! -f "\$MAIN_PY_PATH" ]; then
        printf "${RED} >> ERRO: Arquivo main.py não encontrado em \$MAIN_PY_PATH${WHITE}\n"
        exit 1
      fi
      
      # Mudar para o diretório correto
      cd "\$TRANSC_DIR" || {
        printf "${RED} >> ERRO: Não foi possível acessar o diretório \$TRANSC_DIR${WHITE}\n"
        exit 1
      }
      
      # Limpar cache do Python antes de iniciar
      printf "${WHITE} >> Limpando cache do Python...${WHITE}\n"
      find "\$TRANSC_DIR" -type d -name "__pycache__" -exec rm -rf {} + 2>/dev/null || true
      find "\$TRANSC_DIR" -name "*.pyc" -delete 2>/dev/null || true
      find "\$TRANSC_DIR" -name "*.pyo" -delete 2>/dev/null || true
      
      # Instalar dependências Python
      printf "${WHITE} >> Instalando dependências Python...${WHITE}\n"
      
      # Determinar comando pip a usar
      PIP_CMD="pip3"
      if ! command -v pip3 &>/dev/null; then
        if python3 -m pip --version &>/dev/null; then
          PIP_CMD="python3 -m pip"
          printf "${GREEN} >> Usando python3 -m pip como alternativa${WHITE}\n"
        else
          printf "${YELLOW} >> AVISO: pip3 não está disponível. Tentando continuar...${WHITE}\n"
        fi
      fi
      
      # Obter o caminho do site-packages do usuário
      USER_SITE=\$(python3 -m site --user-site 2>/dev/null || echo "")
      
      if [ -f "\$TRANSC_DIR/requirements.txt" ]; then
        printf "${GREEN} >> Arquivo requirements.txt encontrado. Instalando dependências...${WHITE}\n"
        # Tentar com --user primeiro
        INSTALL_OUTPUT=\$(\$PIP_CMD install --user -r "\$TRANSC_DIR/requirements.txt" 2>&1)
        INSTALL_STATUS=\$?
        if [ \$INSTALL_STATUS -eq 0 ] || echo "\$INSTALL_OUTPUT" | grep -q "already satisfied\|Requirement already satisfied"; then
          printf "${GREEN} >> ✓ Dependências instaladas${WHITE}\n"
        elif echo "\$INSTALL_OUTPUT" | grep -q "externally-managed-environment"; then
          printf "${YELLOW} >> Ambiente externally-managed detectado. Usando --break-system-packages...${WHITE}\n"
          \$PIP_CMD install --user --break-system-packages -r "\$TRANSC_DIR/requirements.txt" 2>&1 | grep -v "already satisfied\|Requirement already satisfied" || true
          printf "${GREEN} >> ✓ Dependências instaladas${WHITE}\n"
        else
          printf "${YELLOW} >> Tentando com --break-system-packages...${WHITE}\n"
          \$PIP_CMD install --user --break-system-packages -r "\$TRANSC_DIR/requirements.txt" 2>&1 | grep -v "already satisfied\|Requirement already satisfied" || true
          printf "${GREEN} >> ✓ Dependências instaladas${WHITE}\n"
        fi
      else
        printf "${YELLOW} >> Arquivo requirements.txt não encontrado. Instalando dependências básicas...${WHITE}\n"
        # Tentar com --user primeiro
        INSTALL_OUTPUT=\$(\$PIP_CMD install --user flask flask-cors requests 2>&1)
        INSTALL_STATUS=\$?
        if [ \$INSTALL_STATUS -eq 0 ] || echo "\$INSTALL_OUTPUT" | grep -q "already satisfied\|Requirement already satisfied"; then
          printf "${GREEN} >> ✓ Dependências básicas instaladas${WHITE}\n"
        elif echo "\$INSTALL_OUTPUT" | grep -q "externally-managed-environment"; then
          printf "${YELLOW} >> Ambiente externally-managed detectado. Usando --break-system-packages...${WHITE}\n"
          \$PIP_CMD install --user --break-system-packages flask flask-cors requests 2>&1 | grep -v "already satisfied\|Requirement already satisfied" || true
          printf "${GREEN} >> ✓ Dependências básicas instaladas (Flask, Flask-CORS, Requests)${WHITE}\n"
        else
          printf "${YELLOW} >> Tentando com --break-system-packages...${WHITE}\n"
          \$PIP_CMD install --user --break-system-packages flask flask-cors requests 2>&1 | grep -v "already satisfied\|Requirement already satisfied" || true
          printf "${GREEN} >> ✓ Dependências básicas instaladas${WHITE}\n"
        fi
      fi
      
      # Verificar se Flask está instalado e acessível
      if python3 -c "import flask" 2>/dev/null; then
        printf "${GREEN} >> ✓ Flask verificado e disponível${WHITE}\n"
      else
        printf "${RED} >> ERRO: Flask não está acessível! Tentando instalar novamente...${WHITE}\n"
        INSTALL_OUTPUT=\$(\$PIP_CMD install --user --force-reinstall flask 2>&1)
        INSTALL_STATUS=\$?
        if [ \$INSTALL_STATUS -ne 0 ] || echo "\$INSTALL_OUTPUT" | grep -q "externally-managed-environment"; then
          printf "${YELLOW} >> Usando --break-system-packages...${WHITE}\n"
          \$PIP_CMD install --user --break-system-packages --force-reinstall flask 2>&1 || true
        fi
        # Tentar novamente após reinstalar
        if python3 -c "import flask" 2>/dev/null; then
          printf "${GREEN} >> ✓ Flask instalado com sucesso${WHITE}\n"
        else
          printf "${RED} >> ERRO: Ainda não foi possível importar Flask!${WHITE}\n"
        fi
      fi
      echo
      
      # Verificar que a porta está correta no main.py
      final_port=\$(grep -oP "port\s*=\s*\K\d+" "\$MAIN_PY_PATH" | head -1 || echo "")
      if [ "\$final_port" != "${porta_transcricao}" ]; then
        printf "${RED} >> ERRO: Porta no arquivo (\$final_port) não corresponde à porta esperada (${porta_transcricao})!${WHITE}\n"
        exit 1
      fi
      printf "${GREEN} >> ✓ Porta ${porta_transcricao} confirmada no main.py${WHITE}\n"
      echo
      
      # Parar qualquer processo PM2 desta instância que possa existir
      pm2 stop ${empresa}-transcricao 2>/dev/null || true
      pm2 delete ${empresa}-transcricao 2>/dev/null || true
      pm2 stop transc-${empresa} 2>/dev/null || true
      pm2 delete transc-${empresa} 2>/dev/null || true
      
      # Obter o caminho do site-packages do usuário e configurar PYTHONPATH
      USER_SITE=\$(python3 -m site --user-site 2>/dev/null || echo "")
      if [ -n "\$USER_SITE" ] && [ -d "\$USER_SITE" ]; then
        export PYTHONPATH="\$USER_SITE:\$PYTHONPATH"
        printf "${GREEN} >> PYTHONPATH configurado: \$USER_SITE${WHITE}\n"
      fi
      
      # Determinar comando pip a usar
      PIP_CMD="pip3"
      if ! command -v pip3 &>/dev/null; then
        if python3 -m pip --version &>/dev/null; then
          PIP_CMD="python3 -m pip"
        fi
      fi
      
      # Verificar Flask antes de iniciar
      if ! python3 -c "import flask" 2>/dev/null; then
        printf "${RED} >> ERRO: Flask não está disponível! Instalando...${WHITE}\n"
        INSTALL_OUTPUT=\$(\$PIP_CMD install --user flask 2>&1)
        INSTALL_STATUS=\$?
        if [ \$INSTALL_STATUS -ne 0 ] || echo "\$INSTALL_OUTPUT" | grep -q "externally-managed-environment"; then
          printf "${YELLOW} >> Usando --break-system-packages...${WHITE}\n"
          \$PIP_CMD install --user --break-system-packages flask 2>&1 || true
        fi
        # Atualizar USER_SITE após instalação
        USER_SITE=\$(python3 -m site --user-site 2>/dev/null || echo "")
        if [ -n "\$USER_SITE" ] && [ -d "\$USER_SITE" ]; then
          export PYTHONPATH="\$USER_SITE:\$PYTHONPATH"
        fi
      fi
      
      # Configurar PYTHONPATH antes de iniciar PM2
      if [ -n "\$USER_SITE" ] && [ -d "\$USER_SITE" ]; then
        export PYTHONPATH="\$USER_SITE:\$PYTHONPATH"
        printf "${GREEN} >> PYTHONPATH configurado: \$USER_SITE${WHITE}\n"
      fi
      
      # Verificar Flask uma última vez antes de iniciar
      if ! python3 -c "import flask" 2>/dev/null; then
        printf "${RED} >> ERRO CRÍTICO: Flask ainda não está disponível!${WHITE}\n"
        printf "${YELLOW} >> Tentando instalação final...${WHITE}\n"
        
        # Tentar via pip primeiro
        if [ -n "\$PIP_CMD" ] && command -v \$PIP_CMD &>/dev/null 2>&1; then
          \$PIP_CMD install --user --break-system-packages flask flask-cors requests 2>&1 | grep -v "already satisfied\|Requirement already satisfied" || true
        fi
        
        # Atualizar USER_SITE após instalação
        USER_SITE=\$(python3 -m site --user-site 2>/dev/null || echo "")
        if [ -n "\$USER_SITE" ] && [ -d "\$USER_SITE" ]; then
          export PYTHONPATH="\$USER_SITE:\$PYTHONPATH"
        fi
        
        # Verificar novamente
        if ! python3 -c "import flask" 2>/dev/null; then
          printf "${RED} >> ERRO: Não foi possível instalar Flask via pip!${WHITE}\n"
          printf "${YELLOW} >> Por favor, execute manualmente: sudo apt-get install -y python3-flask python3-flask-cors${WHITE}\n"
          printf "${YELLOW} >> Ou: sudo apt-get install -y python3-pip && pip3 install --user flask flask-cors${WHITE}\n"
          printf "${RED} >> O PM2 será iniciado, mas falhará sem Flask instalado.${WHITE}\n"
        else
          printf "${GREEN} >> ✓ Flask instalado com sucesso!${WHITE}\n"
        fi
      fi
      
      # Criar script wrapper para garantir PYTHONPATH correto
      WRAPPER_SCRIPT="\$TRANSC_DIR/run_transcricao.sh"
      cat > "\$WRAPPER_SCRIPT" <<WRAPPEREOF
#!/bin/bash
cd "\$TRANSC_DIR"
# Configurar PYTHONPATH
USER_SITE=\$(python3 -m site --user-site 2>/dev/null || echo "")
if [ -n "\$USER_SITE" ] && [ -d "\$USER_SITE" ]; then
  export PYTHONPATH="\$USER_SITE:\$PYTHONPATH"
fi
# Executar o main.py
exec python3 "\$MAIN_PY_PATH"
WRAPPEREOF
      chmod +x "\$WRAPPER_SCRIPT"
      chown deploy:deploy "\$WRAPPER_SCRIPT" 2>/dev/null || true
      
      # Iniciar PM2 com o wrapper script
      printf "${GREEN} >> Iniciando PM2 com wrapper script (garante PYTHONPATH correto)...${WHITE}\n"
      pm2 start "\$WRAPPER_SCRIPT" --name ${empresa}-transcricao --interpreter bash --cwd "\$TRANSC_DIR"
      pm2 save --force
      
      # Verificar se iniciou corretamente
      sleep 3
        if pm2 list | grep -q "${empresa}-transcricao.*online"; then
          printf "${GREEN} >> ✓ Processo ${empresa}-transcricao está ONLINE${WHITE}\n"
          # Verificar logs para confirmar porta
          sleep 2
          pm2 logs ${empresa}-transcricao --lines 10 --nostream 2>/dev/null | grep -i "porta\|port\|Servidor iniciado" | head -3 || true
        else
          printf "${YELLOW} >> ⚠ Verifique o status: pm2 list${WHITE}\n"
          printf "${YELLOW} >> Verifique os logs: pm2 logs ${empresa}-transcricao${WHITE}\n"
        fi
STARTPM2CORRECT
      
    else
      printf "${YELLOW} >> AVISO: Arquivo main.py não encontrado${WHITE}\n"
    fi
    
    echo
    sleep 2
  else
    printf "${RED} >> Script não encontrado em: $script_path${WHITE}\n"
    printf "${YELLOW} >> A configuração da porta foi atualizada, mas o script de instalação não foi encontrado.${WHITE}\n"
    sleep 2
  fi
  
  # Salvar a porta da transcrição no arquivo de variáveis da instância
  if [ -n "${ARQUIVO_VARIAVEIS_INSTANCIA:-}" ] && [ -f "${ARQUIVO_VARIAVEIS_INSTANCIA}" ]; then
    banner
    printf "${WHITE} >> Salvando porta da transcrição no arquivo de variáveis...\n"
    echo
    
    # Verificar se já existe porta_transcricao no arquivo
    if grep -q "^porta_transcricao=" "$ARQUIVO_VARIAVEIS_INSTANCIA"; then
      # Atualizar porta existente
      sed -i "s|^porta_transcricao=.*|porta_transcricao=${porta_transcricao}|" "$ARQUIVO_VARIAVEIS_INSTANCIA"
      printf "${GREEN} >> Porta da transcrição atualizada no arquivo de variáveis: ${porta_transcricao}${WHITE}\n"
    else
      # Adicionar porta_transcricao se não existir
      echo "" >> "$ARQUIVO_VARIAVEIS_INSTANCIA"
      echo "# Porta do serviço de transcrição de áudio" >> "$ARQUIVO_VARIAVEIS_INSTANCIA"
      echo "porta_transcricao=${porta_transcricao}" >> "$ARQUIVO_VARIAVEIS_INSTANCIA"
      printf "${GREEN} >> Porta da transcrição salva no arquivo de variáveis: ${porta_transcricao}${WHITE}\n"
    fi
    
    printf "${GREEN} >> Arquivo: ${BLUE}$ARQUIVO_VARIAVEIS_INSTANCIA${WHITE}\n"
    echo
  sleep 2
  else
    printf "${YELLOW} >> AVISO: Não foi possível identificar o arquivo de variáveis para salvar a porta${WHITE}\n"
    printf "${YELLOW} >> A porta ${porta_transcricao} foi configurada, mas não foi salva no arquivo de variáveis${WHITE}\n"
    echo
  fi
  
  echo
  printf "${GREEN} >> Processo de instalação da transcrição finalizado!${WHITE}\n"
  printf "${GREEN} >> Porta configurada: ${BLUE}${porta_transcricao}${WHITE}\n"
  printf "${GREEN} >> Instância: ${BLUE}${empresa}${WHITE}\n"
  echo
  
  # Verificar se Flask está realmente instalado
  if ! sudo su - deploy -c "python3 -c 'import flask'" 2>/dev/null; then
    printf "${RED}══════════════════════════════════════════════════════════════════${WHITE}\n"
    printf "${RED} >> ATENÇÃO: Flask não está instalado!${WHITE}\n"
    printf "${RED}══════════════════════════════════════════════════════════════════${WHITE}\n"
    echo
    printf "${YELLOW} >> Para instalar Flask manualmente, execute:${WHITE}\n"
    printf "${BLUE}    sudo apt-get update${WHITE}\n"
    printf "${BLUE}    sudo apt-get install -y python3-pip python3-flask python3-flask-cors${WHITE}\n"
    echo
    printf "${YELLOW} >> Ou se preferir usar pip:${WHITE}\n"
    printf "${BLUE}    sudo apt-get install -y python3-pip${WHITE}\n"
    printf "${BLUE}    pip3 install --user --break-system-packages flask flask-cors requests${WHITE}\n"
    echo
    printf "${YELLOW} >> Após instalar, reinicie o serviço:${WHITE}\n"
    printf "${BLUE}    sudo su - deploy -c 'pm2 restart ${empresa}-transcricao'${WHITE}\n"
    echo
  else
    printf "${GREEN} >> ✓ Flask está instalado e disponível${WHITE}\n"
  fi
  
  printf "${YELLOW} >> IMPORTANTE: Verifique se o serviço está rodando corretamente${WHITE}\n"
  printf "${YELLOW} >> Use: pm2 list (para ver processos)${WHITE}\n"
  printf "${YELLOW} >> Use: pm2 logs ${empresa}-transcricao (para ver logs)${WHITE}\n"
  printf "${YELLOW} >> Use: lsof -i:${porta_transcricao} (para verificar a porta)${WHITE}\n"
  echo
  printf "${WHITE} >> Pressione Enter para voltar ao menu...${WHITE}\n"
  read -r
}

# Adicionar função para instalar API Oficial
instalar_api_oficial() {
  banner
  printf "${WHITE} >> Instalando API Oficial...\n"
  echo
  local script_path="$(pwd)/instalador_apioficial.sh"
  if [ -f "$script_path" ]; then
    chmod 775 "$script_path"
    bash "$script_path"
  else
    printf "${RED} >> Script não encontrado em: $script_path${WHITE}\n"
    sleep 2
  fi
  printf "${GREEN} >> Processo de instalação da API Oficial finalizado. Voltando ao menu...${WHITE}\n"
  sleep 2
}

# Adicionar função para atualizar API Oficial
atualizar_api_oficial() {
  banner
  printf "${WHITE} >> Atualizando API Oficial...\n"
  echo
  local script_path="$(pwd)/atualizar_apioficial.sh"
  if [ -f "$script_path" ]; then
    chmod 775 "$script_path"
    bash "$script_path"
  else
    printf "${RED} >> Script não encontrado em: $script_path${WHITE}\n"
    sleep 2
  fi
  printf "${GREEN} >> Processo de atualização da API Oficial finalizado. Voltando ao menu...${WHITE}\n"
  sleep 2
}

# Adicionar função para migrar para Multiflow-PRO
migrar_multiflow_pro() {
  banner
  printf "${WHITE} >> Migrando para Multiflow-PRO...\n"
  echo
  local script_path="$(pwd)/atualizador_pro.sh"
  if [ -f "$script_path" ]; then
    chmod 775 "$script_path"
    bash "$script_path"
  else
    printf "${RED} >> Script não encontrado em: $script_path${WHITE}\n"
    printf "${RED} >> Certifique-se de que o arquivo atualizador_pro.sh está no mesmo diretório do instalador.${WHITE}\n"
    sleep 2
  fi
  printf "${GREEN} >> Processo de migração para Multiflow-PRO finalizado. Voltando ao menu...${WHITE}\n"
  sleep 2
}

# Instalação em modo Alta Performance (Redis, Postgres, PgBouncer via Docker)
exec_instalador_alta_performance() {
  local script_path="$(pwd)/tools/instalador_alta_performance.sh"
  if [ ! -f "$script_path" ]; then
    printf "${RED} >> Script não encontrado: $script_path${WHITE}\n"
    sleep 2
    return
  fi
  chmod 775 "$script_path"
  bash "$script_path"
  # Se o script sair sem exec do instalador (cancelamento), volta ao menu
  printf "${GREEN} >> Voltando ao menu...${WHITE}\n"
  sleep 2
}

carregar_variaveis
menu
