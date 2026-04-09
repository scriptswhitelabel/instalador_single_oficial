#!/bin/bash
# Troca URLs (domínios) da instância: Nginx/SSL, .env, build do frontend, PM2.
# Opcional: API Oficial e WhatsMeow (WuzAPI).

GREEN='\033[1;32m'
BLUE='\033[1;34m'
WHITE='\033[1;37m'
RED='\033[1;31m'
YELLOW='\033[1;33m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALADOR_DIR="${SCRIPT_DIR}/.."
ARQUIVO_VARIAVEIS="${INSTALADOR_DIR}/VARIAVEIS_INSTALACAO"
DEFAULT_API_OFICIAL_PORT=6000
DEFAULT_WUZAPI_PORT=8090

if [ "${EUID}" -ne 0 ]; then
  printf "${WHITE} >> Execute como root (sudo).${WHITE}\n"
  exit 1
fi

banner() {
  clear
  printf "${BLUE}"
  echo "╔══════════════════════════════════════════════════════════════╗"
  echo "║              TROCAR DOMÍNIOS (BACKEND / FRONTEND)             ║"
  echo "╚══════════════════════════════════════════════════════════════╝"
  printf "${WHITE}\n"
}

# --- Instâncias (mesma lógica do instalador_single.sh) ---
detectar_instancias_instaladas() {
  local instancias=()
  local nomes_empresas=()
  local temp_empresa=""

  if [ -f "${INSTALADOR_DIR}/${ARQUIVO_VARIAVEIS##*/}" ]; then
    local empresa_original="${empresa:-}"
    local subdominio_backend_original="${subdominio_backend:-}"
    local subdominio_frontend_original="${subdominio_frontend:-}"
    source "${INSTALADOR_DIR}/${ARQUIVO_VARIAVEIS##*/}" 2>/dev/null
    temp_empresa="${empresa:-}"
    if [ -n "${temp_empresa}" ] && [ -d "/home/deploy/${temp_empresa}" ] && [ -d "/home/deploy/${temp_empresa}/backend" ]; then
      instancias+=("${INSTALADOR_DIR}/${ARQUIVO_VARIAVEIS##*/}")
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
        source "$arquivo_instancia" 2>/dev/null
        temp_empresa="${empresa:-}"
        if [ -n "${temp_empresa}" ] && [ -d "/home/deploy/${temp_empresa}" ] && [ -d "/home/deploy/${temp_empresa}/backend" ]; then
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

selecionar_instancia() {
  banner
  printf "${WHITE} >> Detectando instâncias instaladas...\n\n"
  detectar_instancias_instaladas
  local total_instancias=${#INSTANCIAS_DETECTADAS[@]}

  if [ "$total_instancias" -eq 0 ]; then
    printf "${RED} >> Nenhuma instância encontrada.${WHITE}\n"
    exit 1
  elif [ "$total_instancias" -eq 1 ]; then
    printf "${GREEN} >> Instância: ${BLUE}${NOMES_EMPRESAS_DETECTADAS[0]}${WHITE}\n\n"
    source "${INSTANCIAS_DETECTADAS[0]}"
    declare -g ARQUIVO_VARIAVEIS_USADO="${INSTANCIAS_DETECTADAS[0]}"
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
  printf "${YELLOW} >> Qual instância? (1-%s):${WHITE}\n" "$total_instancias"
  read -r escolha_instancia
  if ! [[ "$escolha_instancia" =~ ^[0-9]+$ ]] || [ "$escolha_instancia" -lt 1 ] || [ "$escolha_instancia" -gt "$total_instancias" ]; then
    printf "${RED} >> Opção inválida.${WHITE}\n"
    exit 1
  fi
  local indice_selecionado=$((escolha_instancia - 1))
  source "${INSTANCIAS_DETECTADAS[$indice_selecionado]}"
  declare -g ARQUIVO_VARIAVEIS_USADO="${INSTANCIAS_DETECTADAS[$indice_selecionado]}"
  printf "${GREEN} >> Selecionada: ${BLUE}${empresa}${WHITE}\n\n"
  sleep 1
}

# Normaliza para https://host (sem path)
normalize_https_url() {
  local raw="$1"
  raw=$(echo "$raw" | tr -d '\r' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
  raw="${raw#https://}"
  raw="${raw#http://}"
  raw="${raw%%/*}"
  raw="${raw%%:*}"
  echo "https://${raw}"
}

host_sem_https() {
  local u="$1"
  echo "$u" | sed 's|https\?://||' | sed 's|/.*||'
}

# Atualiza ou acrescenta chave no arquivo VARIAVEIS (evita problemas de sed com caracteres especiais)
set_variaveis_key() {
  local file="$1"
  local key="$2"
  local val="$3"
  if [ ! -f "$file" ]; then
    printf "${RED} >> Arquivo não encontrado: %s${WHITE}\n" "$file"
    return 1
  fi
  local tmp="${file}.tmp.$$"
  grep -v "^${key}=" "$file" > "$tmp" 2>/dev/null || true
  echo "${key}=${val}" >> "$tmp"
  mv "$tmp" "$file"
}

# Atualiza uma linha KEY= no .env (remove linha antiga e adiciona ao final se existir)
set_env_key() {
  local file="$1"
  local key="$2"
  local val="$3"
  if [ ! -f "$file" ]; then
    return 1
  fi
  local tmp="${file}.tmp.$$"
  grep -v "^${key}=" "$file" > "$tmp" 2>/dev/null || true
  echo "${key}=${val}" >> "$tmp"
  mv "$tmp" "$file"
}

detectar_proxy() {
  if [ -f "/etc/nginx/sites-available/${empresa}-backend" ] || [ -f "/etc/nginx/sites-available/${empresa}-frontend" ]; then
    echo "nginx"
    return
  fi
  if [ -d /etc/traefik/conf.d ] && systemctl is-active --quiet traefik 2>/dev/null; then
    echo "traefik"
    return
  fi
  echo "nginx"
}

aplicar_nginx_principal() {
  local fe_hostname="$1"
  local be_hostname="$2"
  local fe_port="${frontend_port:-3000}"
  local be_port="${backend_port:-8080}"

  cat > "/etc/nginx/sites-available/${empresa}-frontend" << EOF
server {
  server_name ${fe_hostname};
  location / {
    proxy_pass http://127.0.0.1:${fe_port};
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
EOF

  cat > "/etc/nginx/sites-available/${empresa}-backend" << EOF
upstream backend {
        server 127.0.0.1:${be_port};
        keepalive 32;
    }
server {
  server_name ${be_hostname};
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
EOF

  [ ! -L "/etc/nginx/sites-enabled/${empresa}-frontend" ] && ln -sf "/etc/nginx/sites-available/${empresa}-frontend" "/etc/nginx/sites-enabled/${empresa}-frontend"
  [ ! -L "/etc/nginx/sites-enabled/${empresa}-backend" ] && ln -sf "/etc/nginx/sites-available/${empresa}-backend" "/etc/nginx/sites-enabled/${empresa}-backend"

  nginx -t && systemctl reload nginx
}

certbot_dominio() {
  local dom="$1"
  local em="${email_deploy:?email_deploy não definido no arquivo de variáveis}"
  certbot -m "$em" --nginx --agree-tos -n -d "$dom" --redirect 2>&1 || {
    printf "${YELLOW} >> Aviso: certbot pode ter falhado para %s. Verifique manualmente.${WHITE}\n" "$dom"
  }
}

remover_routers_traefik_antigos() {
  local ob="$1"
  local of="$2"
  [ -n "$ob" ] && [ -f "/etc/traefik/conf.d/routers-${ob}.toml" ] && rm -f "/etc/traefik/conf.d/routers-${ob}.toml"
  [ -n "$of" ] && [ -f "/etc/traefik/conf.d/routers-${of}.toml" ] && rm -f "/etc/traefik/conf.d/routers-${of}.toml"
}

aplicar_traefik_principal() {
  local host_be="$1"
  local host_fe="$2"
  local be_port="${backend_port:-8080}"
  local fe_port="${frontend_port:-3000}"

  remover_routers_traefik_antigos "$3" "$4"

  cat > "/etc/traefik/conf.d/routers-${host_be}.toml" << END
[http.routers]
  [http.routers.backend]
    rule = "Host(\`${host_be}\`)"
    service = "backend"
    entryPoints = ["web"]
    middlewares = ["https-redirect"]

  [http.routers.backend-secure]
    rule = "Host(\`${host_be}\`)"
    service = "backend"
    entryPoints = ["websecure"]
    [http.routers.backend-secure.tls]
      certResolver = "letsencryptresolver"

[http.services]
  [http.services.backend]
    [http.services.backend.loadBalancer]
      [[http.services.backend.loadBalancer.servers]]
        url = "http://127.0.0.1:${be_port}"

[http.middlewares]
  [http.middlewares.https-redirect.redirectScheme]
    scheme = "https"
    permanent = true
END

  cat > "/etc/traefik/conf.d/routers-${host_fe}.toml" << END
[http.routers]
  [http.routers.frontend]
    rule = "Host(\`${host_fe}\`)"
    service = "frontend"
    entryPoints = ["web"]
    middlewares = ["https-redirect"]

  [http.routers.frontend-secure]
    rule = "Host(\`${host_fe}\`)"
    service = "frontend"
    entryPoints = ["websecure"]
    [http.routers.frontend-secure.tls]
      certResolver = "letsencryptresolver"

[http.services]
  [http.services.frontend]
    [http.services.frontend.loadBalancer]
      [[http.services.frontend.loadBalancer.servers]]
        url = "http://127.0.0.1:${fe_port}"

[http.middlewares]
  [http.middlewares.https-redirect.redirectScheme]
    scheme = "https"
    permanent = true
END

  systemctl restart traefik.service 2>/dev/null || true
}

rebuild_frontend_pm2() {
  sudo su - deploy <<REBUILD
if [ -f /root/instalador_single_oficial/tools/path_node_deploy.sh ]; then
  . /root/instalador_single_oficial/tools/path_node_deploy.sh
else
  export PATH="/usr/local/bin:/usr/bin:\${PATH:-}"
  if [ -d /usr/local/n/versions/node/20.19.4/bin ]; then
    export PATH="/usr/local/n/versions/node/20.19.4/bin:\$PATH"
  elif [ -d /usr/local/n/versions/node ]; then
    _mf_nv=\$(ls -1 /usr/local/n/versions/node 2>/dev/null | sort -V | tail -1)
    if [ -n "\$_mf_nv" ] && [ -d "/usr/local/n/versions/node/\$_mf_nv/bin" ]; then
      export PATH="/usr/local/n/versions/node/\$_mf_nv/bin:\$PATH"
    fi
  fi
fi
FRDIR="/home/deploy/${empresa}/frontend"
cd "\$FRDIR" || exit 1
if [ -f server.js ]; then
  sed -i 's/3000/'"${frontend_port:-3000}"'/g' server.js 2>/dev/null || true
fi
export NODE_OPTIONS="--max-old-space-size=4096 --openssl-legacy-provider"
npm run build
REBUILD

  sudo su - deploy <<PM2R
if [ -f /root/instalador_single_oficial/tools/path_node_deploy.sh ]; then
  . /root/instalador_single_oficial/tools/path_node_deploy.sh
else
  export PATH=/usr/local/n/versions/node/20.19.4/bin:/usr/bin:/usr/local/bin:\$PATH 2>/dev/null
  export PATH=/usr/bin:/usr/local/bin:\$PATH
fi
pm2 restart ${empresa}-backend ${empresa}-frontend 2>/dev/null || true
pm2 save
PM2R
}

nginx_apioficial() {
  local host_of="$1"
  local port_of="${2:-$DEFAULT_API_OFICIAL_PORT}"
  cat > "/etc/nginx/sites-available/${empresa}-oficial" << EOF
upstream oficial {
        server 127.0.0.1:${port_of};
        keepalive 32;
    }
server {
  server_name ${host_of};
  location / {
    proxy_pass http://oficial;
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
EOF
  [ ! -L "/etc/nginx/sites-enabled/${empresa}-oficial" ] && ln -sf "/etc/nginx/sites-available/${empresa}-oficial" "/etc/nginx/sites-enabled/${empresa}-oficial"
  nginx -t && systemctl reload nginx
}

nginx_whatsmeow() {
  local host_wm="$1"
  local port_wm="${2:-$DEFAULT_WUZAPI_PORT}"
  cat > "/etc/nginx/sites-available/${empresa}-whatsmeow" << EOF
upstream api_whatsmeow {
        server 127.0.0.1:${port_wm};
        keepalive 32;
    }
server {
  server_name ${host_wm};
  location / {
    proxy_pass http://api_whatsmeow;
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
EOF
  [ ! -L "/etc/nginx/sites-enabled/${empresa}-whatsmeow" ] && ln -sf "/etc/nginx/sites-available/${empresa}-whatsmeow" "/etc/nginx/sites-enabled/${empresa}-whatsmeow"
  nginx -t && systemctl reload nginx
}

# --- fluxo principal ---
selecionar_instancia

BACK_ENV="/home/deploy/${empresa}/backend/.env"
FRONT_ENV="/home/deploy/${empresa}/frontend/.env"

if [ ! -f "$BACK_ENV" ]; then
  printf "${RED} >> %s não encontrado.${WHITE}\n" "$BACK_ENV"
  exit 1
fi

# Carregar portas e email se faltar
[ -z "${backend_port}" ] && backend_port=8080
[ -z "${frontend_port}" ] && frontend_port=3000
# shellcheck source=/dev/null
source "$ARQUIVO_VARIAVEIS_USADO" 2>/dev/null

old_be_url=""
old_fe_url=""
if grep -q '^BACKEND_URL=' "$BACK_ENV" 2>/dev/null; then
  old_be_url=$(grep '^BACKEND_URL=' "$BACK_ENV" | head -1 | cut -d '=' -f2-)
fi
if grep -q '^FRONTEND_URL=' "$BACK_ENV" 2>/dev/null; then
  old_fe_url=$(grep '^FRONTEND_URL=' "$BACK_ENV" | head -1 | cut -d '=' -f2-)
fi

banner
printf "${WHITE} >> Instância ${BLUE}%s${WHITE}\n" "$empresa"
printf "    Backend atual:  ${YELLOW}%s${WHITE}\n" "${old_be_url:-?}"
printf "    Frontend atual: ${YELLOW}%s${WHITE}\n" "${old_fe_url:-?}"
echo
printf "${YELLOW} >> Nova URL do backend (ex: https://api.seudominio.com):${WHITE}\n"
read -r novo_backend_in
printf "${YELLOW} >> Nova URL do frontend (ex: https://app.seudominio.com):${WHITE}\n"
read -r novo_frontend_in

novo_backend=$(normalize_https_url "$novo_backend_in")
novo_frontend=$(normalize_https_url "$novo_frontend_in")

if [ -z "${email_deploy}" ]; then
  printf "${RED} >> email_deploy não está no arquivo de variáveis. Necessário para SSL.${WHITE}\n"
  exit 1
fi

be_host=$(host_sem_https "$novo_backend")
fe_host=$(host_sem_https "$novo_frontend")
old_be_host=""
old_fe_host=""
[ -n "$old_be_url" ] && old_be_host=$(host_sem_https "$old_be_url")
[ -n "$old_fe_url" ] && old_fe_host=$(host_sem_https "$old_fe_url")

printf "\n${WHITE} >> Confirmar troca?\n"
printf "    Backend:  ${GREEN}%s${WHITE}\n" "$novo_backend"
printf "    Frontend: ${GREEN}%s${WHITE}\n" "$novo_frontend"
printf "${YELLOW} (s/N):${WHITE} "
read -r conf
conf=$(echo "$conf" | tr '[:lower:]' '[:upper:]')
if [ "$conf" != "S" ]; then
  printf "${GREEN} >> Cancelado.${WHITE}\n"
  exit 0
fi

# 1) Arquivo de variáveis da instância
set_variaveis_key "$ARQUIVO_VARIAVEIS_USADO" "subdominio_backend" "$novo_backend"
set_variaveis_key "$ARQUIVO_VARIAVEIS_USADO" "subdominio_frontend" "$novo_frontend"
subdominio_backend="$novo_backend"
subdominio_frontend="$novo_frontend"

# 2) Proxy + SSL
PROXY=$(detectar_proxy)
printf "\n${WHITE} >> Proxy detectado: ${BLUE}%s${WHITE}\n" "$PROXY"

if [ "$PROXY" = "nginx" ]; then
  aplicar_nginx_principal "$fe_host" "$be_host"
  printf "\n${WHITE} >> Certbot (backend)...\n"
  certbot_dominio "$be_host"
  printf "\n${WHITE} >> Certbot (frontend)...\n"
  certbot_dominio "$fe_host"
  systemctl reload nginx 2>/dev/null || true
elif [ "$PROXY" = "traefik" ]; then
  aplicar_traefik_principal "$be_host" "$fe_host" "$old_be_host" "$old_fe_host"
fi

# 3) .env backend e frontend
set_env_key "$BACK_ENV" "BACKEND_URL" "$novo_backend"
set_env_key "$BACK_ENV" "FRONTEND_URL" "$novo_frontend"

if [ -f "$FRONT_ENV" ]; then
  set_env_key "$FRONT_ENV" "REACT_APP_BACKEND_URL" "$novo_backend"
fi

# 4) Build frontend + PM2
printf "\n${WHITE} >> Build do frontend e reinício PM2...\n"
rebuild_frontend_pm2

printf "\n${GREEN} >> URLs principais atualizadas.${WHITE}\n"

# --- API Oficial (opcional) ---
if [ -f "/home/deploy/${empresa}/api_oficial/.env" ]; then
  echo
  printf "${YELLOW} >> Deseja trocar também a URL da API Oficial? (s/N):${WHITE} "
  read -r op_of
  op_of=$(echo "$op_of" | tr '[:lower:]' '[:upper:]')
  if [ "$op_of" = "S" ]; then
    printf "${YELLOW} >> Nova URL da API Oficial (ex: https://oficial.seudominio.com):${WHITE}\n"
    read -r novo_of_in
    novo_of_url=$(normalize_https_url "$novo_of_in")
    of_host=$(host_sem_https "$novo_of_url")

    set_variaveis_key "$ARQUIVO_VARIAVEIS_USADO" "subdominio_oficial" "$of_host"

    port_of="${DEFAULT_API_OFICIAL_PORT}"
    if grep -q '^PORT=' "/home/deploy/${empresa}/api_oficial/.env" 2>/dev/null; then
      port_of=$(grep '^PORT=' "/home/deploy/${empresa}/api_oficial/.env" | head -1 | cut -d '=' -f2- | tr -d '\r')
    fi

    if [ "$PROXY" = "nginx" ]; then
      nginx_apioficial "$of_host" "$port_of"
      certbot_dominio "$of_host"
      systemctl reload nginx 2>/dev/null || true
    else
      printf "${YELLOW} >> Traefik ativo: configure o host da API Oficial no Traefik se usar HTTPS automático.${WHITE}\n"
    fi

    set_env_key "/home/deploy/${empresa}/api_oficial/.env" "URL_API_OFICIAL" "$novo_of_url"
    set_env_key "/home/deploy/${empresa}/api_oficial/.env" "URL_BACKEND_MULT100" "$novo_backend"
    set_env_key "$BACK_ENV" "URL_API_OFICIAL" "$novo_of_url"

    sudo su - deploy <<EOF
if [ -f /root/instalador_single_oficial/tools/path_node_deploy.sh ]; then
  . /root/instalador_single_oficial/tools/path_node_deploy.sh
fi
cd /home/deploy/${empresa}/api_oficial && (pm2 restart api_oficial_${empresa} 2>/dev/null || pm2 restart api_oficial 2>/dev/null || pm2 start dist/main.js --name api_oficial_${empresa}) && pm2 save
EOF
    printf "${GREEN} >> API Oficial atualizada.${WHITE}\n"
  fi
fi

# --- WhatsMeow / WuzAPI (opcional) ---
if [ -d "/home/deploy/${empresa}/wuzapi" ]; then
  echo
  printf "${YELLOW} >> Deseja trocar também a URL do WhatsMeow (WuzAPI)? (s/N):${WHITE} "
  read -r op_wm
  op_wm=$(echo "$op_wm" | tr '[:lower:]' '[:upper:]')
  if [ "$op_wm" = "S" ]; then
    printf "${YELLOW} >> Nova URL do WhatsMeow (ex: https://wuzapi.seudominio.com):${WHITE}\n"
    read -r novo_wm_in
    novo_wm_url=$(normalize_https_url "$novo_wm_in")
    wm_host=$(host_sem_https "$novo_wm_url")
    wz_port="${wuzapi_port:-$DEFAULT_WUZAPI_PORT}"
    if grep -q '^wuzapi_port=' "$ARQUIVO_VARIAVEIS_USADO" 2>/dev/null; then
      wz_port=$(grep '^wuzapi_port=' "$ARQUIVO_VARIAVEIS_USADO" | head -1 | cut -d '=' -f2- | tr -d '\r')
    fi
    wz_port="${wz_port:-$DEFAULT_WUZAPI_PORT}"

    set_variaveis_key "$ARQUIVO_VARIAVEIS_USADO" "subdominio_whatsmeow" "$wm_host"

    if [ "$PROXY" = "nginx" ]; then
      nginx_whatsmeow "$wm_host" "$wz_port"
      certbot_dominio "$wm_host"
      systemctl reload nginx 2>/dev/null || true
    else
      printf "${YELLOW} >> Traefik ativo: configure o host do WhatsMeow no Traefik se usar HTTPS automático.${WHITE}\n"
    fi

    if [ -f "/home/deploy/${empresa}/wuzapi/.env" ]; then
      set_env_key "/home/deploy/${empresa}/wuzapi/.env" "WUZAPI_GLOBAL_WEBHOOK" "${novo_wm_url}/webhook"
    fi
    set_env_key "$BACK_ENV" "WUZAPI_URL" "$novo_wm_url"

    if [ -f "/home/deploy/${empresa}/wuzapi/docker-compose.yml" ]; then
      sudo su - deploy <<WMDOCK
cd /home/deploy/${empresa}/wuzapi && docker compose up -d --force-recreate 2>/dev/null || docker-compose up -d --force-recreate 2>/dev/null || true
WMDOCK
    fi
    printf "${GREEN} >> WhatsMeow / WuzAPI atualizado.${WHITE}\n"
  fi
fi

echo
printf "${GREEN} >> Concluído.${WHITE}\n"
exit 0
