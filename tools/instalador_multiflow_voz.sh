#!/bin/bash
# tools/instalador_multiflow_voz.sh
# Instala MultiFlow VOZ (API + Frontend + Engine WaCalls) em VPS com Multiflow
# já instalado (reaproveita variáveis) ou em VPS limpo (instala dependências).

set -euo pipefail

GREEN='\033[1;32m'
BLUE='\033[1;34m'
WHITE='\033[1;37m'
RED='\033[1;31m'
YELLOW='\033[1;33m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALADOR_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
ARQUIVO_VARIAVEIS_VOZ="${INSTALADOR_DIR}/VARIAVEIS_MULTIFLOW_VOZ"
PATH_NODE_DEPLOY="${SCRIPT_DIR}/path_node_deploy.sh"

VOZ_ROOT="/home/deploy/multiflow-voz"
REPO_NAME="multiflow-voz"
DEFAULT_API_PORT=4110
DEFAULT_ENGINE_PORT=8081
MODO_VPS="" # multiflow | limpo

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
  echo "║                 INSTALADOR MULTIFLOW VOZ                     ║"
  echo "║          Softphone / Ligações WhatsApp (VoIP)                ║"
  echo "╚══════════════════════════════════════════════════════════════╝"
  printf "${WHITE}\n"
}

normalizar_host() {
  local raw="$1"
  raw=$(echo "$raw" | tr -d '[:space:]')
  raw=$(echo "$raw" | sed 's|^[Hh][Tt][Tt][Pp][Ss]*://||' | cut -d '/' -f1)
  printf '%s' "$raw"
}

porta_em_listen() {
  local port="$1"
  if command -v ss >/dev/null 2>&1; then
    ss -tlnH 2>/dev/null | grep -qE ":${port}([[:space:]]|$)"
    return $?
  fi
  if command -v netstat >/dev/null 2>&1; then
    netstat -tln 2>/dev/null | grep -qE ":${port}[[:space:]]"
    return $?
  fi
  return 1
}

gerar_segredo() {
  openssl rand -hex 24 2>/dev/null || head -c 48 /dev/urandom | xxd -p | tr -d '\n' | head -c 48
}

# ─── Detecção de instâncias Multiflow (mesmo padrão do instalador) ───
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
  printf "${WHITE} >> Selecione a instância Multiflow que compartilhará este VPS com o VOZ.\n\n"
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
  printf "${WHITE} A instalação do MultiFlow VOZ está sendo feita em:${WHITE}\n"
  echo
  printf "   [${BLUE}1${WHITE}] VPS onde o Multiflow ${GREEN}já está instalado${WHITE}\n"
  printf "       (reaproveita usuário deploy, senha, Node, Nginx, Postgres/Redis se existirem)\n"
  echo
  printf "   [${BLUE}2${WHITE}] VPS ${YELLOW}limpo${WHITE}\n"
  printf "       (instala Nginx, Certbot, Node, Redis, Postgres, PM2, Go e depois o VOZ)\n"
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

solicitar_dados_voz() {
  banner
  printf "${WHITE} >> Informe os dados do MultiFlow VOZ${WHITE}\n"
  echo
  printf "${YELLOW} >> URL / subdomínio do FRONTEND (ex: voz.seudominio.com):${WHITE}\n"
  read -r voz_front_in
  voz_front_host=$(normalizar_host "${voz_front_in}")
  [ -n "$voz_front_host" ] || trata_erro "URL do frontend vazia"
  echo

  printf "${YELLOW} >> URL / subdomínio da API (ex: apivoz.seudominio.com):${WHITE}\n"
  read -r voz_api_in
  voz_api_host=$(normalizar_host "${voz_api_in}")
  [ -n "$voz_api_host" ] || trata_erro "URL da API vazia"
  echo

  printf "${YELLOW} >> Porta local da API VOZ [${DEFAULT_API_PORT}]:${WHITE}\n"
  read -r voz_api_port
  voz_api_port="${voz_api_port:-$DEFAULT_API_PORT}"
  if ! [[ "$voz_api_port" =~ ^[0-9]+$ ]] || [ "$voz_api_port" -lt 1 ] || [ "$voz_api_port" -gt 65535 ]; then
    trata_erro "porta da API inválida"
  fi
  if porta_em_listen "$voz_api_port"; then
    printf "${YELLOW} >> Aviso: porta %s já parece em uso. Continuando mesmo assim...${WHITE}\n" "$voz_api_port"
  fi
  echo

  printf "${YELLOW} >> Porta local do Engine VoIP (somente 127.0.0.1) [${DEFAULT_ENGINE_PORT}]:${WHITE}\n"
  read -r voz_engine_port
  voz_engine_port="${voz_engine_port:-$DEFAULT_ENGINE_PORT}"
  if ! [[ "$voz_engine_port" =~ ^[0-9]+$ ]] || [ "$voz_engine_port" -lt 1 ] || [ "$voz_engine_port" -gt 65535 ]; then
    trata_erro "porta do engine inválida"
  fi
  echo

  if [ -z "${email_deploy:-}" ]; then
    printf "${YELLOW} >> E-mail para Let's Encrypt / admin:${WHITE}\n"
    read -r email_deploy
    echo
  fi
  [ -n "${email_deploy:-}" ] || trata_erro "e-mail obrigatório"

  if [ -z "${senha_deploy:-}" ]; then
    printf "${YELLOW} >> Senha do usuário deploy (e Redis, se instalar):${WHITE}\n"
    read -r senha_deploy
    echo
  fi
  [ -n "${senha_deploy:-}" ] || trata_erro "senha_deploy obrigatória"

  if [ -z "${TOKEN_AUTH:-}" ]; then
    printf "${YELLOW} >> Token GitHub com acesso ao repositório multiflow-voz:${WHITE}\n"
    read -r TOKEN_AUTH
    echo
  fi
  [ -n "${TOKEN_AUTH:-}" ] || trata_erro "token GitHub obrigatório"

  # Bridge opcional com Multiflow
  if [ "$MODO_VPS" = "multiflow" ] && [ -n "${subdominio_backend:-}" ]; then
    multiflow_api_sugerido="https://$(normalizar_host "${subdominio_backend}")"
  else
    multiflow_api_sugerido=""
  fi
  printf "${YELLOW} >> URL da API Multiflow para bridge Oficial (opcional"
  if [ -n "$multiflow_api_sugerido" ]; then
    printf ", Enter = %s" "$multiflow_api_sugerido"
  fi
  printf "):${WHITE}\n"
  read -r multiflow_api_url
  multiflow_api_url="${multiflow_api_url:-$multiflow_api_sugerido}"
  multiflow_api_url="${multiflow_api_url%/}"
  echo

  printf "${WHITE}── Confirmação ──${WHITE}\n"
  printf "  Modo:            ${GREEN}%s${WHITE}\n" "$MODO_VPS"
  printf "  Frontend:        ${GREEN}https://%s${WHITE}\n" "$voz_front_host"
  printf "  API:             ${GREEN}https://%s${WHITE}\n" "$voz_api_host"
  printf "  Porta API:       ${GREEN}%s${WHITE}\n" "$voz_api_port"
  printf "  Porta Engine:    ${GREEN}%s (127.0.0.1)${WHITE}\n" "$voz_engine_port"
  printf "  Pasta:           ${GREEN}%s${WHITE}\n" "$VOZ_ROOT"
  [ -n "$multiflow_api_url" ] && printf "  Multiflow API:   ${GREEN}%s${WHITE}\n" "$multiflow_api_url"
  echo
  printf "${YELLOW} >> Confirmar instalação? (S/N):${WHITE}\n"
  read -r conf
  conf=$(echo "$conf" | tr '[:lower:]' '[:upper:]')
  [ "$conf" = "S" ] || {
    printf "${GREEN} >> Cancelado.${WHITE}\n"
    exit 0
  }
}

salvar_variaveis_voz() {
  cat >"$ARQUIVO_VARIAVEIS_VOZ" <<EOF
# Gerado por instalador_multiflow_voz.sh em $(date -Iseconds)
modo_vps=${MODO_VPS}
empresa=${empresa:-}
senha_deploy=${senha_deploy}
email_deploy=${email_deploy}
voz_front_host=${voz_front_host}
voz_api_host=${voz_api_host}
voz_api_port=${voz_api_port}
voz_engine_port=${voz_engine_port}
voz_root=${VOZ_ROOT}
multiflow_api_url=${multiflow_api_url}
EOF
  chmod 600 "$ARQUIVO_VARIAVEIS_VOZ"
  printf "${GREEN} >> Variáveis salvas em %s${WHITE}\n" "$ARQUIVO_VARIAVEIS_VOZ"
}

# ─── VPS limpo: dependências ───
instalar_base_vps_limpo() {
  banner
  printf "${WHITE} >> Preparando VPS limpo (pacotes base)...${WHITE}\n"

  export DEBIAN_FRONTEND=noninteractive
  apt-get update -y || {
    echo "nameserver 8.8.8.8" >>/etc/resolv.conf
    apt-get update -y
  }

  apt-get install -y \
    curl wget git build-essential openssl \
    nginx redis-server postgresql postgresql-contrib \
    ufw snapd ca-certificates gnupg || trata_erro "apt packages"

  timedatectl set-timezone America/Sao_Paulo 2>/dev/null || true
  ufw allow 22/tcp >/dev/null 2>&1 || true
  ufw allow 80/tcp >/dev/null 2>&1 || true
  ufw allow 443/tcp >/dev/null 2>&1 || true

  # Redis com senha
  if [ -f /etc/redis/redis.conf ]; then
    if grep -q '^# requirepass' /etc/redis/redis.conf; then
      sed -i "s/^# requirepass.*/requirepass ${senha_deploy}/" /etc/redis/redis.conf
    elif grep -q '^requirepass' /etc/redis/redis.conf; then
      sed -i "s/^requirepass.*/requirepass ${senha_deploy}/" /etc/redis/redis.conf
    else
      echo "requirepass ${senha_deploy}" >>/etc/redis/redis.conf
    fi
    systemctl enable redis-server >/dev/null 2>&1 || true
    systemctl restart redis-server || true
  fi

  systemctl enable postgresql >/dev/null 2>&1 || true
  systemctl start postgresql || true

  # Usuário deploy
  if ! id deploy >/dev/null 2>&1; then
    useradd -m -p "$(openssl passwd -1 "${senha_deploy}")" -s /bin/bash -G sudo deploy
    usermod -aG sudo deploy
  fi

  # Nginx default off
  rm -f /etc/nginx/sites-enabled/default 2>/dev/null || true
  systemctl enable nginx >/dev/null 2>&1 || true
  systemctl restart nginx || true

  # Certbot
  if ! command -v certbot >/dev/null 2>&1; then
    snap install core >/dev/null 2>&1 || true
    snap refresh core >/dev/null 2>&1 || true
    snap install --classic certbot || apt-get install -y certbot python3-certbot-nginx
    [ -f /usr/bin/certbot ] || ln -sf /snap/bin/certbot /usr/bin/certbot
  fi

  instalar_node_pm2
  instalar_golang

  printf "${GREEN} >> Base do VPS limpo pronta.${WHITE}\n"
  sleep 1
}

instalar_node_pm2() {
  export PATH="/usr/local/n/versions/node/20.19.4/bin:/usr/local/bin:/usr/bin:$PATH"
  if ! command -v node >/dev/null 2>&1; then
    printf "${WHITE} >> Instalando Node.js...${WHITE}\n"
    curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
    apt-get install -y nodejs
  fi
  npm install -g n 2>/dev/null || true
  if command -v n >/dev/null 2>&1; then
    n 20.19.4 || true
  fi
  export PATH="/usr/local/n/versions/node/20.19.4/bin:/usr/local/bin:/usr/bin:$PATH"
  npm install -g pm2 || trata_erro "pm2"
  # PATH no bashrc do deploy
  if [ -d /home/deploy ] && ! grep -q '/usr/local/n/versions/node' /home/deploy/.bashrc 2>/dev/null; then
    echo 'export PATH=/usr/local/n/versions/node/20.19.4/bin:/usr/bin:$PATH' >>/home/deploy/.bashrc
  fi
}

instalar_golang() {
  local GO_VER="1.26.4"
  export PATH="/usr/local/go/bin:$PATH"
  if command -v go >/dev/null 2>&1; then
    local ver
    ver=$(go version 2>/dev/null || true)
    # Aceita 1.26+; se mais antigo, reinstala (go.mod exige 1.26.4)
    if echo "$ver" | grep -qE 'go1\.(2[6-9]|[3-9][0-9])'; then
      printf "${GREEN} >> Go já instalado: %s${WHITE}\n" "$ver"
      return 0
    fi
    printf "${YELLOW} >> Go antigo detectado (%s) — atualizando para %s...${WHITE}\n" "$ver" "$GO_VER"
  else
    printf "${WHITE} >> Instalando Go %s (exigido pelo engine)...${WHITE}\n" "$GO_VER"
  fi
  local arch goarch
  arch=$(uname -m)
  case "$arch" in
    x86_64) goarch=amd64 ;;
    aarch64|arm64) goarch=arm64 ;;
    *) trata_erro "arquitetura não suportada para Go: $arch" ;;
  esac
  local tar="go${GO_VER}.linux-${goarch}.tar.gz"
  cd /tmp
  curl -fsSL -o "$tar" "https://go.dev/dl/${tar}" || trata_erro "download Go"
  rm -rf /usr/local/go
  tar -C /usr/local -xzf "$tar"
  ln -sf /usr/local/go/bin/go /usr/local/bin/go
  ln -sf /usr/local/go/bin/gofmt /usr/local/bin/gofmt
  if ! grep -q '/usr/local/go/bin' /etc/profile 2>/dev/null; then
    echo 'export PATH=/usr/local/go/bin:$PATH' >>/etc/profile
  fi
  export PATH="/usr/local/go/bin:$PATH"
  go version || trata_erro "go version"
}

garantir_deps_vps_multiflow() {
  banner
  printf "${WHITE} >> VPS com Multiflow: reaproveitando ambiente existente...${WHITE}\n"
  id deploy >/dev/null 2>&1 || trata_erro "usuário deploy não existe — instale o Multiflow antes"
  command -v nginx >/dev/null 2>&1 || trata_erro "nginx não encontrado"
  command -v certbot >/dev/null 2>&1 || {
    printf "${YELLOW} >> Certbot ausente — instalando...${WHITE}\n"
    snap install --classic certbot 2>/dev/null || apt-get install -y certbot python3-certbot-nginx
    [ -f /usr/bin/certbot ] || ln -sf /snap/bin/certbot /usr/bin/certbot
  }
  export PATH="/usr/local/n/versions/node/20.19.4/bin:/usr/local/go/bin:/usr/local/bin:/usr/bin:$PATH"
  if ! command -v node >/dev/null 2>&1; then
    instalar_node_pm2
  fi
  if ! command -v pm2 >/dev/null 2>&1; then
    npm install -g pm2 || trata_erro "pm2"
  fi
  if ! command -v go >/dev/null 2>&1; then
    instalar_golang
  fi
  printf "${GREEN} >> Dependências OK (reaproveitando Postgres/Redis/Nginx do Multiflow).${WHITE}\n"
  printf "${WHITE} >> Obs: o MultiFlow VOZ usa SQLite próprio; Postgres/Redis do Multiflow ficam intactos.${WHITE}\n"
  sleep 2
}

clonar_repositorio() {
  banner
  printf "${WHITE} >> Clonando repositório multiflow-voz...${WHITE}\n"
  local repo_url="https://${TOKEN_AUTH}@github.com/scriptswhitelabel/${REPO_NAME}.git"

  if [ -d "${VOZ_ROOT}/.git" ]; then
    printf "${YELLOW} >> Pasta já existe — atualizando (git fetch/reset)...${WHITE}\n"
    cd "$VOZ_ROOT"
    git remote set-url origin "$repo_url" 2>/dev/null || true
    git fetch origin
    git checkout main 2>/dev/null || git checkout master 2>/dev/null || true
    git reset --hard origin/main 2>/dev/null || git reset --hard origin/master || true
  else
    rm -rf "$VOZ_ROOT"
    git clone "$repo_url" "$VOZ_ROOT" || trata_erro "git clone multiflow-voz"
  fi

  # Remove token da URL remota
  cd "$VOZ_ROOT"
  git remote set-url origin "https://github.com/scriptswhitelabel/${REPO_NAME}.git" 2>/dev/null || true
  chown -R deploy:deploy "$VOZ_ROOT"
  mkdir -p "$VOZ_ROOT/logs" "$VOZ_ROOT/storage/recordings" \
    "$VOZ_ROOT/backend/data" "$VOZ_ROOT/engine/data"
  chown -R deploy:deploy "$VOZ_ROOT"
}

escrever_env_backend() {
  local jwt token_key engine_key bridge
  jwt=$(gerar_segredo)
  token_key=$(gerar_segredo | head -c 32)
  engine_key=$(gerar_segredo)
  bridge=$(gerar_segredo)

  cat >"${VOZ_ROOT}/backend/.env" <<EOF
PORT=${voz_api_port}
NODE_ENV=production
JWT_SECRET=${jwt}
JWT_EXPIRES_IN=7d
TOKEN_CIPHER_KEY=${token_key}
DATABASE_STORAGE=${VOZ_ROOT}/backend/data/multiflow-voz.sqlite
RECORDINGS_PATH=${VOZ_ROOT}/storage/recordings
CORS_ORIGIN=https://${voz_front_host}
SUPER_EMAIL=${email_deploy}
SUPER_PASSWORD=${senha_deploy}
SUPER_NAME=Super Admin
ENGINE_URL=http://127.0.0.1:${voz_engine_port}
ENGINE_API_KEY=${engine_key}
PUBLIC_API_URL=https://${voz_api_host}
PUBLIC_APP_URL=https://${voz_front_host}
MULTIFLOW_API_URL=${multiflow_api_url}
VOZ_BRIDGE_SECRET=${bridge}
EOF
  chmod 600 "${VOZ_ROOT}/backend/.env"
  chown deploy:deploy "${VOZ_ROOT}/backend/.env"

  # Ajusta ecosystem com porta do engine
  if [ -f "${VOZ_ROOT}/ecosystem.config.js" ]; then
    sed -i "s|-addr 127.0.0.1:[0-9]*|-addr 127.0.0.1:${voz_engine_port}|g" \
      "${VOZ_ROOT}/ecosystem.config.js"
  fi
}


preparar_rollup_frontend() {
  local frontend="${VOZ_ROOT}/frontend"
  local arch glibc_ver usar_wasm="false"

  arch="$(uname -m)"
  glibc_ver="$(ldd --version 2>/dev/null | head -n1 | grep -oE '[0-9]+\.[0-9]+' | tail -n1 || true)"

  printf "${WHITE} >> Arquitetura detectada: %s | GLIBC: %s${WHITE}\n" \
    "$arch" "${glibc_ver:-desconhecida}"

  # Em ARM64 com GLIBC antiga, o binário nativo do Rollup não carrega.
  # Substituímos o pacote "rollup" pelo build oficial WebAssembly.
  if [ "$arch" = "aarch64" ] || [ "$arch" = "arm64" ]; then
    if [ -z "$glibc_ver" ]; then
      usar_wasm="true"
    elif ! printf '%s\n%s\n' "2.34" "$glibc_ver" | sort -V -C; then
      usar_wasm="true"
    fi
  fi

  if [ "$usar_wasm" = "true" ]; then
    printf "${YELLOW} >> ARM64/GLIBC incompatível com Rollup nativo.${WHITE}\n"
    printf "${WHITE} >> Configurando @rollup/wasm-node para o build do frontend...${WHITE}\n"

    FRONTEND_DIR="$frontend" node <<'NODE'
const fs = require("fs");
const path = require("path");

const frontend = process.env.FRONTEND_DIR;
const packagePath = path.join(frontend, "package.json");
const pkg = JSON.parse(fs.readFileSync(packagePath, "utf8"));
const wasmAlias = "npm:@rollup/wasm-node@^4.0.0";

pkg.dependencies = pkg.dependencies || {};
pkg.devDependencies = pkg.devDependencies || {};
pkg.overrides = pkg.overrides || {};

// Se Rollup estiver declarado diretamente, troca pela implementação WASM.
if (Object.prototype.hasOwnProperty.call(pkg.dependencies, "rollup")) {
  pkg.dependencies.rollup = wasmAlias;
}
if (Object.prototype.hasOwnProperty.call(pkg.devDependencies, "rollup")) {
  pkg.devDependencies.rollup = wasmAlias;
}

// Se for dependência transitiva do Vite, força o alias pelo override.
pkg.overrides.rollup = wasmAlias;

fs.writeFileSync(packagePath, JSON.stringify(pkg, null, 2) + "\n");
NODE

    rm -rf "${frontend}/node_modules" "${frontend}/package-lock.json"
  else
    printf "${GREEN} >> Rollup nativo compatível; mantendo instalação padrão.${WHITE}\n"
  fi
}

build_e_seed() {
  banner
  printf "${WHITE} >> Build do Engine (Go), Backend e Frontend...${WHITE}\n"
  export PATH="/usr/local/n/versions/node/20.19.4/bin:/usr/local/go/bin:/usr/local/bin:/usr/bin:$PATH"

  preparar_rollup_frontend
  chown -R deploy:deploy "${VOZ_ROOT}/frontend"

  sudo -u deploy bash -lc "
    set -e
    export PATH=/usr/local/n/versions/node/20.19.4/bin:/usr/local/go/bin:/usr/bin:\$PATH
    export GOTOOLCHAIN=auto
    if [ -f '${PATH_NODE_DEPLOY}' ]; then . '${PATH_NODE_DEPLOY}'; fi
    cd '${VOZ_ROOT}/engine'
    go build -o wacalls-server ./cmd/server
    cd '${VOZ_ROOT}'
    npm install dotenv --no-save 2>/dev/null || npm install dotenv
    cd '${VOZ_ROOT}/backend'
    npm install
    npm run build
    npm run seed || true
    cd '${VOZ_ROOT}/frontend'
    npm install --include=optional
    npm run build
  " || trata_erro "build multiflow-voz"

  chown -R deploy:deploy "$VOZ_ROOT"
}

iniciar_pm2() {
  banner
  printf "${WHITE} >> Iniciando processos PM2 (engine + api)...${WHITE}\n"
  export PATH="/usr/local/n/versions/node/20.19.4/bin:/usr/local/bin:/usr/bin:$PATH"

  sudo -u deploy bash -lc "
    set -e
    export PATH=/usr/local/n/versions/node/20.19.4/bin:/usr/bin:\$PATH
    if [ -f '${PATH_NODE_DEPLOY}' ]; then . '${PATH_NODE_DEPLOY}'; fi
    cd '${VOZ_ROOT}'
    pm2 delete multiflow-voz-engine 2>/dev/null || true
    pm2 delete multiflow-voz-api 2>/dev/null || true
    pm2 start ecosystem.config.js
    pm2 save
  " || trata_erro "pm2 start"

  # Startup systemd
  env PATH="$PATH" pm2 startup systemd -u deploy --hp /home/deploy >/tmp/pm2-startup-voz.txt 2>&1 || true
  if grep -q 'sudo' /tmp/pm2-startup-voz.txt 2>/dev/null; then
    # shellcheck disable=SC2046
    eval $(grep -o 'sudo .*' /tmp/pm2-startup-voz.txt | head -1) || true
  fi
}

configurar_nginx_ssl() {
  banner
  printf "${WHITE} >> Configurando Nginx + SSL...${WHITE}\n"

  local front_conf="multiflow-voz-front"
  local api_conf="multiflow-voz-api"
  local up_front="uc_voz_front"
  local up_api="uc_voz_api"

  cat >"/etc/nginx/sites-available/${front_conf}" <<EOF
upstream ${up_api}_via_front {
  server 127.0.0.1:${voz_api_port};
  keepalive 32;
}
server {
  listen 80;
  server_name ${voz_front_host};

  root ${VOZ_ROOT}/frontend/dist;
  index index.html;

  client_max_body_size 100M;

  location /api/ {
    proxy_pass http://${up_api}_via_front;
    proxy_http_version 1.1;
    proxy_set_header Host \$host;
    proxy_set_header X-Real-IP \$remote_addr;
    proxy_set_header X-Forwarded-Proto \$scheme;
    proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    proxy_set_header Upgrade \$http_upgrade;
    proxy_set_header Connection 'upgrade';
  }

  location /health {
    proxy_pass http://${up_api}_via_front;
    proxy_http_version 1.1;
    proxy_set_header Host \$host;
  }

  location / {
    try_files \$uri \$uri/ /index.html;
  }
}
EOF

  cat >"/etc/nginx/sites-available/${api_conf}" <<EOF
upstream ${up_api} {
  server 127.0.0.1:${voz_api_port};
  keepalive 32;
}
server {
  listen 80;
  server_name ${voz_api_host};

  client_max_body_size 100M;

  location / {
    proxy_pass http://${up_api};
    proxy_http_version 1.1;
    proxy_set_header Host \$host;
    proxy_set_header X-Real-IP \$remote_addr;
    proxy_set_header X-Forwarded-Proto \$scheme;
    proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    proxy_set_header Upgrade \$http_upgrade;
    proxy_set_header Connection 'upgrade';
    proxy_buffering on;
  }
}
EOF

  ln -sfn "/etc/nginx/sites-available/${front_conf}" "/etc/nginx/sites-enabled/${front_conf}"
  ln -sfn "/etc/nginx/sites-available/${api_conf}" "/etc/nginx/sites-enabled/${api_conf}"
  nginx -t || trata_erro "nginx -t"
  systemctl reload nginx || service nginx reload || true

  printf "${WHITE} >> Emitindo certificados Let's Encrypt...${WHITE}\n"
  certbot --nginx -d "${voz_front_host}" --non-interactive --agree-tos -m "${email_deploy}" --redirect \
    || printf "${YELLOW} >> Falha SSL frontend — verifique DNS de %s${WHITE}\n" "$voz_front_host"
  certbot --nginx -d "${voz_api_host}" --non-interactive --agree-tos -m "${email_deploy}" --redirect \
    || printf "${YELLOW} >> Falha SSL API — verifique DNS de %s${WHITE}\n" "$voz_api_host"

  systemctl reload nginx || true
}

resumo_final() {
  banner
  printf "${GREEN}══════════════════════════════════════════════════════════${WHITE}\n"
  printf "${GREEN}  MultiFlow VOZ instalado com sucesso!${WHITE}\n"
  printf "${GREEN}══════════════════════════════════════════════════════════${WHITE}\n"
  echo
  printf "  Frontend:   ${BLUE}https://%s${WHITE}\n" "$voz_front_host"
  printf "  API:        ${BLUE}https://%s${WHITE}\n" "$voz_api_host"
  printf "  Health:     ${BLUE}https://%s/health${WHITE}\n" "$voz_api_host"
  printf "  Pasta:      ${BLUE}%s${WHITE}\n" "$VOZ_ROOT"
  printf "  PM2:        ${BLUE}multiflow-voz-api / multiflow-voz-engine${WHITE}\n"
  echo
  printf "  Admin:      ${YELLOW}%s${WHITE}\n" "$email_deploy"
  printf "  Senha:      ${YELLOW}%s${WHITE} (SUPER_PASSWORD / senha_deploy)\n" "$senha_deploy"
  echo
  printf "  Webhook Asaas:        ${BLUE}https://%s/api/webhooks/asaas${WHITE}\n" "$voz_api_host"
  printf "  Webhook Mercado Pago: ${BLUE}https://%s/api/webhooks/mercadopago${WHITE}\n" "$voz_api_host"
  echo
  printf "${YELLOW} >> Aponte o DNS dos subdomínios para este VPS antes do SSL.${WHITE}\n"
  printf "${WHITE} >> Variáveis em: %s${WHITE}\n" "$ARQUIVO_VARIAVEIS_VOZ"
  echo
}

# ─── Main ───
main() {
  perguntar_modo_vps

  if [ "$MODO_VPS" = "multiflow" ]; then
    selecionar_instancia_multiflow
  else
    empresa="${empresa:-multiflow}"
  fi

  solicitar_dados_voz
  salvar_variaveis_voz

  if [ "$MODO_VPS" = "limpo" ]; then
    instalar_base_vps_limpo
  else
    garantir_deps_vps_multiflow
  fi

  clonar_repositorio
  escrever_env_backend
  build_e_seed
  iniciar_pm2
  configurar_nginx_ssl
  resumo_final
}

main "$@"
