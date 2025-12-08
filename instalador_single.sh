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

banner() {
  printf " ${BLUE}"
  printf "\n\n"
  printf "██╗███╗   ██╗███████╗████████╗ █████╗ ██╗     ██╗     ███████╗██╗    ██╗██╗\n"
  printf "██║████╗  ██║██╔════╝╚══██╔══╝██╔══██╗██║     ██║     ██╔════╝██║    ██║██║\n"
  printf "██║██╔██╗ ██║███████    ██║   ███████║██║     ██║     ███████╗██║ █╗ ██║██║\n"
  printf "██║██║╚██╗██║╚════██║   ██║   ██╔══██║██║     ██║     ╚════██║██║███╗██║██║\n"
  printf "██║██║ ╚████║███████╗   ██║   ██║  ██║███████╗███████╗███████╗╚███╔███╔╝███████╗\n"
  printf "╚═╝╚═╝  ╚═══╝╚══════╝   ╚═╝   ╚═╝  ╚═╝╚══════╝╚══════╝╚══════╝ ╚══╝╚══╝ ╚══════╝\n"
  printf "                                INSTALADOR 6.0\n"
  printf "\n\n"
}

# Função para manipular erros e encerrar o script
trata_erro() {
  printf "${RED}Erro encontrado na etapa $1. Encerrando o script.${WHITE}\n"
  salvar_etapa "$1"
  exit 1
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
    instala_postgres_base || trata_erro "instala_postgres_base"
    salvar_etapa 8
  fi
  if [ "$etapa" -le "8" ]; then
    instala_node_base || trata_erro "instala_node_base"
    salvar_etapa 9
  fi
  if [ "$etapa" -le "9" ]; then
    instala_redis_base || trata_erro "instala_redis_base"
    salvar_etapa 10
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
    cria_banco_base || trata_erro "cria_banco_base"
    salvar_etapa 13
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

# Etapa de instalação
atualizar_base() {
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
    echo "Verifique os apontamentos de DNS dos seguintes subdomínios: ${subdominios_incorretos}"
    sleep 2
    menu
    return 0
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
  printf "${WHITE} >> Digite a URL do repositório privado no GitHub: \n"
  echo
  read -p "> " repo_url
  echo
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
  UPDATE_FILE="$(pwd)/update.x"
  {
    sudo DEBIAN_FRONTEND=noninteractive apt update -y && sudo DEBIAN_FRONTEND=noninteractive apt upgrade -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" && sudo DEBIAN_FRONTEND=noninteractive apt-get install build-essential -y && sudo DEBIAN_FRONTEND=noninteractive apt-get install -y apparmor-utils
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

Instala NodeJS
instala_node_base() {
  banner
 printf "${WHITE} >> Instalando nodejs...\n"
 echo
  {
    sudo su - root <<EOF
  curl -s https://deb.nodesource.com/gpgkey/nodesource.gpg.key | apt-key add -
  sudo sh -c "echo deb https://deb.nodesource.com/node_20.x focal main \ > /etc/apt/sources.list.d/nodesource.list"
  sudo apt-get update && apt-get install nodejs -y
  sudo npm install -g n
  sudo n 20.19.4
  sudo ln -sf /usr/local/n/versions/node/20.19.4/bin/node /usr/bin/node
  sudo ln -sf /usr/local/n/versions/node/20.19.4/bin/npm /usr/bin/npm
EOF
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
    sudo su - root <<EOF
  npm install -g pm2
  pm2 startup ubuntu -u deploy
  env PATH=\${PATH}:/usr/bin pm2 startup ubuntu -u deploy --hp /home/deploy
EOF
    sleep 2
  } || trata_erro "instala_pm2_base"
}

# Instala Nginx e dependências
instala_nginx_base() {
  banner
  printf "${WHITE} >> Instalando Nginx...\n"
  echo
  {
    sudo su - root <<EOF
    apt install -y nginx
    rm /etc/nginx/sites-enabled/default
EOF

    sleep 2

    sudo su - root <<EOF
echo 'client_max_body_size 100M;' > /etc/nginx/conf.d/${empresa}.conf
EOF

    sleep 2

    sudo su - root <<EOF
  service nginx restart
EOF

    sleep 2

    sudo su - root <<EOF
  apt install -y snapd
  snap install core
  snap refresh core
EOF

    sleep 2

    sudo su - root <<EOF
  apt-get remove certbot
  snap install --classic certbot
  ln -s /snap/bin/certbot /usr/bin/certbot
EOF

    sleep 2
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
    sudo su - deploy <<EOF
  cat <<[-]EOF > /home/deploy/${empresa}/backend/.env
# Scripts WhiteLabel - All Rights Reserved - (18) 9 8802-9627
NODE_ENV=
BACKEND_URL=${subdominio_backend}
FRONTEND_URL=${subdominio_frontend}
PROXY_PORT=443
PORT=${backend_port}

# CREDENCIAIS BD
DB_HOST=localhost
DB_DIALECT=postgres
DB_PORT=5432
DB_USER=${empresa}
DB_PASS=${senha_deploy}
DB_NAME=${empresa}

# DADOS REDIS
REDIS_URI=redis://:${senha_deploy}@127.0.0.1:6379
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

# WhatsApp Oficial
USE_WHATSAPP_OFICIAL=true
# URL_API_OFICIAL=https://SubDominioDaOficial.SEUDOMINIO.com.br
TOKEN_API_OFICIAL="adminpro"
OFFICIAL_CAMPAIGN_CONCURRENCY=10  # Processa até 10 campanhas ao mesmo tempo

# API de Transcrição de Audio
TRANSCRIBE_URL=http://localhost:4002
[-]EOF
EOF

    sleep 2

    banner
    printf "${WHITE} >> Instalando dependências do ${BLUE}backend${WHITE}...\n"
    echo
    sudo su - deploy <<EOF
  cd /home/deploy/${empresa}/backend
  export PUPPETEER_SKIP_DOWNLOAD=true
  rm -r node_modules
  rm package-lock.json
  npm install --force
  npm install puppeteer-core --force
  # npm install --save-dev @types/glob --legacy-peer-deps
  npm i glob
  # npm install jimp@^1.6.0
  npm run build
EOF

    sleep 2

    sudo su - deploy <<EOF
  sed -i 's|npm3Binary = .*|npm3Binary = "/usr/bin/ffmpeg";|' ${empresa}/backend/node_modules/@ffmpeg-installer/ffmpeg/index.js
  mkdir -p /home/deploy/${empresa}/backend/node_modules/@ffmpeg-installer/linux-x64/ && \
  echo '{ "version": "1.1.0", "name": "@ffmpeg-installer/linux-x64" }' > ${empresa}/backend/node_modules/@ffmpeg-installer/linux-x64/package.json
EOF

    sleep 2

    banner
    printf "${WHITE} >> Executando db:migrate...\n"
    echo
    sudo su - deploy <<EOF
  cd /home/deploy/${empresa}/backend
  npx sequelize db:migrate
EOF

    sleep 2

    banner
    printf "${WHITE} >> Executando db:seed...\n"
    echo
    sudo su - deploy <<EOF
  cd /home/deploy/${empresa}/backend
  npx sequelize db:seed:all
EOF

    sleep 2

    banner
    printf "${WHITE} >> Iniciando pm2 ${BLUE}backend${WHITE}...\n"
    echo
    sudo su - deploy <<EOF
  cd /home/deploy/${empresa}/backend
  pm2 start dist/server.js --name ${empresa}-backend
EOF

    sleep 2
  } || trata_erro "instala_backend_base"
}

# Instala e configura frontend
instala_frontend_base() {
  banner
  printf "${WHITE} >> Instalando dependências do ${BLUE}frontend${WHITE}...\n"
  echo
  {
    sudo su - deploy <<EOF
  cd /home/deploy/${empresa}/frontend
  npm install --force
  npx browserslist@latest --update-db
EOF

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
    sudo su - deploy <<EOF
    cd /home/deploy/${empresa}/frontend
    sed -i 's/3000/'"${frontend_port}"'/g' server.js
    NODE_OPTIONS="--max-old-space-size=4096 --openssl-legacy-provider" npm run build
EOF

    sleep 2

    banner
    printf "${WHITE} >> Iniciando pm2 ${BLUE}frontend${WHITE}...\n"
    echo
    sudo su - deploy <<EOF
    cd /home/deploy/${empresa}/frontend
    pm2 start server.js --name ${empresa}-frontend
    pm2 save
EOF

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

    sudo su - deploy <<EOF
  pm2 restart all
EOF

    sleep 2
  } || trata_erro "config_latencia_base"
}

# Finaliza a instalação e mostra dados de acesso
fim_instalacao_base() {
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
  carregar_variaveis
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
  printf "${WHITE} >> Parando Instancias... \n"
  echo
  sleep 2
  sudo su - deploy <<EOF
  pm2 stop all
EOF

  sleep 2

  otimiza_banco_atualizar

  banner
  printf "${WHITE} >> Atualizando a Aplicação... \n"
  echo
  sleep 2

  source /home/deploy/${empresa}/frontend/.env
  frontend_port=${SERVER_PORT:-3000}
  sudo su - deploy <<EOF
printf "${WHITE} >> Atualizando Backend...\n"
echo
cd /home/deploy/${empresa}
# git reset --hard
# git pull
git fetch origin
git checkout MULTI100-OFICIAL-u21
git reset --hard origin/MULTI100-OFICIAL-u21
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
  menu
}

otimiza_banco_atualizar() {
  banner
  printf "${WHITE} >> Realizando Manutenção do Banco de Dados... \n"
  echo
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

# Adicionar função para instalar transcrição de áudio nativa
instalar_transcricao_audio_nativa() {
  banner
  printf "${WHITE} >> Instalando Transcrição de Áudio Nativa...\n"
  echo
  local script_path="/home/deploy/${empresa}/api_transcricao/install-python-app.sh"
  if [ -f "$script_path" ]; then
    chmod 775 "$script_path"
    bash "$script_path"
  else
    printf "${RED} >> Script não encontrado em: $script_path${WHITE}\n"
    sleep 2
  fi
  printf "${GREEN} >> Processo de instalação da transcrição finalizado. Voltando ao menu...${WHITE}\n"
  sleep 2
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

carregar_variaveis
menu
