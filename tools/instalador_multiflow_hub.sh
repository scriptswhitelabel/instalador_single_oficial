#!/bin/bash
# tools/instalador_multiflow_hub.sh
# Prepara o clone do HUB MultiFlow (token GitHub + modo VPS) e dispara o
# install.sh oficial do repositório multiflow-hub (Central / Local / atualizar).

set -euo pipefail

GREEN='\033[1;32m'
BLUE='\033[1;34m'
WHITE='\033[1;37m'
RED='\033[1;31m'
YELLOW='\033[1;33m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALADOR_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
ARQUIVO_VARIAVEIS_HUB="${INSTALADOR_DIR}/VARIAVEIS_MULTIFLOW_HUB"
ESTADO_HUB="/etc/multiflow-hub/instalacao.conf"

HUB_ROOT_PADRAO="/home/deploy/multiflow-hub"
HUB_ROOT=""
REPO_NAME="multiflow-hub"
REPO_OWNER="scriptswhitelabel"
MODO_VPS=""   # multiflow | limpo
PAPEL_HUB=""  # central | local

if [ "${EUID}" -ne 0 ]; then
  printf "${WHITE} >> Este script precisa ser executado como root.${WHITE}\n"
  exit 1
fi

trata_erro() {
  printf "${RED}Erro na etapa: %s. Encerrando.${WHITE}\n" "$1"
  exit 1
}

banner() {
  clear
  printf "${BLUE}"
  echo "╔══════════════════════════════════════════════════════════════╗"
  echo "║                 INSTALADOR MULTIFLOW HUB                     ║"
  echo "║     Meta Connect / WhatsApp Oficial (Central ou Local)       ║"
  echo "╚══════════════════════════════════════════════════════════════╝"
  printf "${WHITE}\n"
}

# ─── Detecção de instâncias Multiflow (mesmo padrão do VOZ) ───
detectar_instancias_instaladas() {
  local instancias=()
  local nomes_empresas=()
  local temp_empresa=""

  if [ -f "${INSTALADOR_DIR}/VARIAVEIS_INSTALACAO" ]; then
    local empresa_original="${empresa:-}"
    # shellcheck source=/dev/null
    source "${INSTALADOR_DIR}/VARIAVEIS_INSTALACAO" 2>/dev/null || true
    temp_empresa="${empresa:-}"
    if [ -n "${temp_empresa}" ] && [ -d "/home/deploy/${temp_empresa}/backend" ]; then
      instancias+=("${INSTALADOR_DIR}/VARIAVEIS_INSTALACAO")
      nomes_empresas+=("${temp_empresa}")
    fi
    empresa="${empresa_original}"
  fi

  if [ -d "${INSTALADOR_DIR}" ]; then
    shopt -s nullglob
    for arquivo_instancia in "${INSTALADOR_DIR}"/VARIAVEIS_INSTALACAO_INSTANCIA_*; do
      [ -f "$arquivo_instancia" ] || continue
      local empresa_original="${empresa:-}"
      # shellcheck source=/dev/null
      source "$arquivo_instancia" 2>/dev/null || true
      temp_empresa="${empresa:-}"
      if [ -n "${temp_empresa}" ] && [ -d "/home/deploy/${temp_empresa}/backend" ]; then
        instancias+=("$arquivo_instancia")
        nomes_empresas+=("${temp_empresa}")
      fi
      empresa="${empresa_original}"
    done
    shopt -u nullglob
  fi

  declare -g INSTANCIAS_DETECTADAS=("${instancias[@]}")
  declare -g NOMES_EMPRESAS_DETECTADAS=("${nomes_empresas[@]}")
}

selecionar_instancia_multiflow() {
  banner
  printf "${WHITE} >> Selecione a instância Multiflow que compartilha este VPS com o HUB.\n\n"
  detectar_instancias_instaladas
  local total=${#INSTANCIAS_DETECTADAS[@]}

  if [ "$total" -eq 0 ]; then
    printf "${RED} >> Nenhuma instância Multiflow detectada neste VPS.${WHITE}\n"
    printf "${YELLOW} >> Se o VPS está limpo, volte e escolha a opção de VPS limpo.${WHITE}\n"
    sleep 3
    exit 1
  fi

  if [ "$total" -eq 1 ]; then
    ARQUIVO_VARIAVEIS_MF="${INSTANCIAS_DETECTADAS[0]}"
    # shellcheck source=/dev/null
    source "$ARQUIVO_VARIAVEIS_MF"
    printf "${GREEN} >> Instância: ${BLUE}%s${WHITE}\n\n" "${empresa}"
    sleep 1
    return 0
  fi

  printf "${WHITE}═══════════════════════════════════════════════════════════\n"
  printf "  INSTÂNCIAS MULTIFLOW\n"
  printf "═══════════════════════════════════════════════════════════${WHITE}\n\n"
  local index=1
  for i in "${!NOMES_EMPRESAS_DETECTADAS[@]}"; do
    printf "  [${BLUE}%s${WHITE}] %s\n" "$index" "${NOMES_EMPRESAS_DETECTADAS[$i]}"
    index=$((index + 1))
  done
  echo
  printf "${YELLOW} >> Escolha (1-%s):${WHITE}\n" "$total"
  read -r escolha
  if ! [[ "$escolha" =~ ^[0-9]+$ ]] || [ "$escolha" -lt 1 ] || [ "$escolha" -gt "$total" ]; then
    printf "${RED} >> Opção inválida.${WHITE}\n"
    exit 1
  fi
  ARQUIVO_VARIAVEIS_MF="${INSTANCIAS_DETECTADAS[$((escolha - 1))]}"
  # shellcheck source=/dev/null
  source "$ARQUIVO_VARIAVEIS_MF"
  printf "${GREEN} >> Instância selecionada: ${BLUE}%s${WHITE}\n\n" "${empresa}"
  sleep 1
}

perguntar_modo_vps() {
  banner
  printf "${WHITE} A instalação do MultiFlow HUB está sendo feita em:${WHITE}\n"
  echo
  printf "   [${BLUE}1${WHITE}] VPS onde o Multiflow ${GREEN}já está instalado${WHITE}\n"
  printf "       (reaproveita Nginx, Postgres e Redis se existirem; HUB ganha banco próprio)\n"
  echo
  printf "   [${BLUE}2${WHITE}] VPS ${YELLOW}limpo${WHITE}\n"
  printf "       (o instalador do HUB sobe Node, Nginx, Certbot, Postgres, Redis e PM2)\n"
  echo
  printf "   [${BLUE}0${WHITE}] Cancelar\n"
  echo
  read -r -p "> " modo
  case "$modo" in
    1) MODO_VPS="multiflow" ;;
    2) MODO_VPS="limpo" ;;
    0)
      printf "${GREEN} >> Cancelado.${WHITE}\n"
      exit 0
      ;;
    *)
      printf "${RED} >> Opção inválida.${WHITE}\n"
      sleep 2
      perguntar_modo_vps
      ;;
  esac
}

perguntar_papel_hub() {
  banner
  printf "${WHITE} Qual papel deste HUB?${WHITE}\n"
  echo
  printf "   [${BLUE}1${WHITE}] ${GREEN}HUB Central${WHITE}\n"
  printf "       App Meta próprio, domínio próprio, recebe webhooks e hospeda /connect.\n"
  printf "       Administra tenants e HUBs Locais.\n"
  echo
  printf "   [${BLUE}2${WHITE}] ${YELLOW}HUB Local${WHITE}\n"
  printf "       Usa um Central (do mantenedor ou do white label) para conexão Meta.\n"
  printf "       Opera os próprios canais no cliente.\n"
  echo
  printf "   [${BLUE}0${WHITE}] Cancelar\n"
  echo
  read -r -p "> " papel
  case "$papel" in
    1) PAPEL_HUB="central" ;;
    2) PAPEL_HUB="local" ;;
    0)
      printf "${GREEN} >> Cancelado.${WHITE}\n"
      exit 0
      ;;
    *)
      printf "${RED} >> Opção inválida.${WHITE}\n"
      sleep 2
      perguntar_papel_hub
      ;;
  esac
}

exigir_token() {
  if [ -z "${TOKEN_AUTH:-}" ]; then
    printf "${YELLOW} >> Token GitHub com acesso ao repositório %s:${WHITE}\n" "$REPO_NAME"
    read -r TOKEN_AUTH
    echo
  fi
  [ -n "${TOKEN_AUTH:-}" ] || trata_erro "token GitHub obrigatório"
}

repo_url_com_token() {
  printf 'https://%s@github.com/%s/%s.git' "$TOKEN_AUTH" "$REPO_OWNER" "$REPO_NAME"
}

repo_url_publica() {
  printf 'https://github.com/%s/%s.git' "$REPO_OWNER" "$REPO_NAME"
}

garantir_git_safe() {
  local raiz="$1"
  git config --global --add safe.directory "$raiz" 2>/dev/null || true
}

git_hub() {
  git -c "safe.directory=${HUB_ROOT}" -C "${HUB_ROOT}" "$@"
}

detectar_hub_root() {
  if [ -f "$ESTADO_HUB" ]; then
    local raiz_estado
    raiz_estado="$(grep -m1 -E '^RAIZ=' "$ESTADO_HUB" 2>/dev/null | cut -d= -f2- || true)"
    if [ -n "$raiz_estado" ] && [ -f "${raiz_estado}/install.sh" ]; then
      HUB_ROOT="$raiz_estado"
      return 0
    fi
  fi

  for candidato in "$HUB_ROOT_PADRAO" "/opt/multiflow-hub"; do
    if [ -f "${candidato}/install.sh" ] && [ -d "${candidato}/.git" ]; then
      HUB_ROOT="$candidato"
      return 0
    fi
  done

  return 1
}

salvar_variaveis_hub() {
  cat >"$ARQUIVO_VARIAVEIS_HUB" <<EOF
# Gerado por instalador_multiflow_hub.sh em $(date -Iseconds)
modo_vps=${MODO_VPS}
papel_hub=${PAPEL_HUB}
empresa=${empresa:-}
hub_root=${HUB_ROOT}
email_deploy=${email_deploy:-}
EOF
  chmod 600 "$ARQUIVO_VARIAVEIS_HUB"
  printf "${GREEN} >> Variáveis salvas em %s${WHITE}\n" "$ARQUIVO_VARIAVEIS_HUB"
}

mostrar_dicas_modo() {
  echo
  if [ "$MODO_VPS" = "multiflow" ]; then
    printf "${YELLOW}── VPS com Multiflow ──${WHITE}\n"
    printf "  • Nginx / Postgres / Redis existentes serão reaproveitados quando possível.\n"
    printf "  • O HUB cria o banco próprio %s (não mexe nos bancos do Multiflow).\n" "multiflow_hub"
    if [ -n "${empresa:-}" ]; then
      printf "  • Instância Multiflow de referência: ${BLUE}%s${WHITE}\n" "$empresa"
      printf "  • Depois: em Empresas, preencha hubUrl + chave administrativa (tenant isCentral).\n"
    fi
  else
    printf "${YELLOW}── VPS limpo ──${WHITE}\n"
    printf "  • O install.sh do HUB instala a base (Node, Nginx, Certbot, Postgres, Redis, PM2).\n"
    printf "  • Aponte o DNS do domínio do HUB para este VPS antes do SSL.\n"
  fi
  echo
  printf "${WHITE}  Em seguida o instalador oficial do HUB fará as perguntas (domínio, e-mail, porta…).${WHITE}\n"
  echo
  sleep 2
}

garantir_clone_hub() {
  exigir_token
  HUB_ROOT="${HUB_ROOT:-$HUB_ROOT_PADRAO}"
  local url
  url="$(repo_url_com_token)"

  if [ -d "${HUB_ROOT}/.git" ]; then
    printf "${WHITE} >> Clone já existe em %s — atualizando remote e fetch...${WHITE}\n" "$HUB_ROOT"
    garantir_git_safe "$HUB_ROOT"
    git_hub remote set-url origin "$url" 2>/dev/null || true
    git_hub fetch origin || trata_erro "git fetch do HUB"
    # Mantém a árvore local; o install.sh (atualizar) cuida do checkout.
    # Em instalação nova sobre clone existente, alinhamos à main.
    if [ ! -f "$ESTADO_HUB" ]; then
      git_hub checkout main 2>/dev/null || git_hub checkout master 2>/dev/null || true
      git_hub reset --hard origin/main 2>/dev/null || git_hub reset --hard origin/master || true
    fi
  else
    if [ -e "$HUB_ROOT" ] && [ ! -d "${HUB_ROOT}/.git" ]; then
      printf "${RED} >> %s existe mas não é um clone git.${WHITE}\n" "$HUB_ROOT"
      trata_erro "pasta HUB inválida"
    fi
    printf "${WHITE} >> Clonando %s/%s em %s...${WHITE}\n" "$REPO_OWNER" "$REPO_NAME" "$HUB_ROOT"
    mkdir -p "$(dirname "$HUB_ROOT")"
    git clone "$url" "$HUB_ROOT" || trata_erro "git clone do HUB"
    garantir_git_safe "$HUB_ROOT"
  fi

  # Remove token da URL remota (fica só no credential helper se o usuário configurar)
  git_hub remote set-url origin "$(repo_url_publica)" 2>/dev/null || true

  # Garante remote autenticado só para a sessão do install (via helper temporário)
  # O install.sh usa gitr fetch; para atualizar precisamos credencial.
  # Reaplica URL com token enquanto rodamos o install; limpa depois.
  git_hub remote set-url origin "$url" 2>/dev/null || true

  [ -f "${HUB_ROOT}/install.sh" ] || trata_erro "install.sh não encontrado no clone"
  chmod 775 "${HUB_ROOT}/install.sh"

  # Clone feito como root: pasta precisa ser do deploy (mesmo padrao Multiflow/VOZ).
  if id deploy >/dev/null 2>&1; then
    chown -R deploy:deploy "$HUB_ROOT" || trata_erro "chown deploy em $HUB_ROOT"
    printf "${GREEN} >> Dono de %s: deploy:deploy${WHITE}\n" "$HUB_ROOT"
  fi
}

limpar_token_do_remote() {
  if [ -n "${HUB_ROOT:-}" ] && [ -d "${HUB_ROOT}/.git" ]; then
    garantir_git_safe "$HUB_ROOT"
    git_hub remote set-url origin "$(repo_url_publica)" 2>/dev/null || true
  fi
}

instalar_hub() {
  perguntar_modo_vps

  if [ "$MODO_VPS" = "multiflow" ]; then
    selecionar_instancia_multiflow
  else
    empresa="${empresa:-}"
  fi

  perguntar_papel_hub
  HUB_ROOT="$HUB_ROOT_PADRAO"

  if [ -f "$ESTADO_HUB" ]; then
    banner
    printf "${YELLOW} >> Já existe instalação registrada em %s.${WHITE}\n" "$ESTADO_HUB"
    printf "${WHITE} >> Use a opção 27 (Atualizar HUB MultiFlow) ou remova antes com o install.sh.${WHITE}\n"
    local raiz_existente
    raiz_existente="$(grep -m1 -E '^RAIZ=' "$ESTADO_HUB" 2>/dev/null | cut -d= -f2- || true)"
    [ -n "$raiz_existente" ] && printf "${WHITE} >> RAIZ atual: %s${WHITE}\n" "$raiz_existente"
    echo
    printf "${YELLOW} >> Continuar mesmo assim e abrir o instalador do HUB? (S/N):${WHITE}\n"
    read -r conf_existente
    conf_existente=$(echo "$conf_existente" | tr '[:lower:]' '[:upper:]')
    [ "$conf_existente" = "S" ] || {
      printf "${GREEN} >> Cancelado.${WHITE}\n"
      exit 0
    }
    detectar_hub_root || HUB_ROOT="$HUB_ROOT_PADRAO"
  fi

  garantir_clone_hub
  salvar_variaveis_hub
  mostrar_dicas_modo

  local cmd="instalar-central"
  [ "$PAPEL_HUB" = "local" ] && cmd="instalar-local"

  printf "${GREEN} >> Iniciando install.sh (%s)...${WHITE}\n\n" "$cmd"
  trap limpar_token_do_remote EXIT
  (cd "$HUB_ROOT" && bash install.sh "$cmd")
  limpar_token_do_remote
  trap - EXIT

  banner
  printf "${GREEN}══════════════════════════════════════════════════════════${WHITE}\n"
  printf "${GREEN}  Fluxo do instalador HUB finalizado.${WHITE}\n"
  printf "${GREEN}══════════════════════════════════════════════════════════${WHITE}\n"
  echo
  printf "  Pasta:     ${BLUE}%s${WHITE}\n" "$HUB_ROOT"
  printf "  Papel:     ${BLUE}%s${WHITE}\n" "$PAPEL_HUB"
  printf "  Modo VPS:  ${BLUE}%s${WHITE}\n" "$MODO_VPS"
  printf "  Estado:    ${BLUE}%s${WHITE}\n" "$ESTADO_HUB"
  printf "  Variáveis: ${BLUE}%s${WHITE}\n" "$ARQUIVO_VARIAVEIS_HUB"
  echo
  if [ "$MODO_VPS" = "multiflow" ] && [ -n "${empresa:-}" ]; then
    printf "${YELLOW} >> Próximo passo no Multiflow (%s):${WHITE}\n" "$empresa"
    printf "     Configure hubUrl = https://<dominio-do-hub> e a chave administrativa\n"
    printf "     (tenant isCentral / Admin Key do painel do HUB — não é a access key de canal).\n"
    echo
  fi
}

atualizar_hub() {
  banner
  printf "${WHITE} >> Atualizando MultiFlow HUB (git + rebuild via install.sh)...${WHITE}\n"
  echo

  if ! detectar_hub_root; then
    printf "${RED} >> HUB não encontrado neste VPS.${WHITE}\n"
    printf "${YELLOW} >> Locais verificados: %s, /opt/multiflow-hub e %s${WHITE}\n" \
      "$HUB_ROOT_PADRAO" "$ESTADO_HUB"
    printf "${YELLOW} >> Use a opção 26 (Instalar HUB MultiFlow) primeiro.${WHITE}\n"
    exit 1
  fi

  if [ ! -f "${HUB_ROOT}/backend/.env" ]; then
    printf "${RED} >> backend/.env não encontrado em %s — instalação incompleta.${WHITE}\n" "$HUB_ROOT"
    exit 1
  fi

  printf "${GREEN} >> HUB detectado em: ${BLUE}%s${WHITE}\n" "$HUB_ROOT"
  if [ -f "$ESTADO_HUB" ]; then
    local papel_atual dominio_atual
    papel_atual="$(grep -m1 -E '^PAPEL=' "$ESTADO_HUB" 2>/dev/null | cut -d= -f2- || true)"
    dominio_atual="$(grep -m1 -E '^DOMINIO=' "$ESTADO_HUB" 2>/dev/null | cut -d= -f2- || true)"
    [ -n "$papel_atual" ] && printf "${WHITE} >> Papel: ${BLUE}%s${WHITE}\n" "$papel_atual"
    [ -n "$dominio_atual" ] && printf "${WHITE} >> Domínio: ${BLUE}%s${WHITE}\n" "$dominio_atual"
  fi
  echo

  garantir_clone_hub

  printf "${GREEN} >> Iniciando install.sh atualizar...${WHITE}\n\n"
  trap limpar_token_do_remote EXIT
  (cd "$HUB_ROOT" && bash install.sh atualizar)
  limpar_token_do_remote
  trap - EXIT

  banner
  printf "${GREEN} >> Atualização do HUB concluída (ou cancelada no próprio instalador).${WHITE}\n"
  printf "${WHITE} >> Pasta: %s${WHITE}\n" "$HUB_ROOT"
  echo
}

main() {
  if [ "${1:-}" = "--atualizar" ] || [ "${1:-}" = "atualizar" ]; then
    atualizar_hub
    return 0
  fi
  instalar_hub
}

main "$@"
