#!/bin/bash
# Ferramentas: novo server_name no Nginx (proxy reverso localhost:porta) + Let's Encrypt via Certbot.
# Fluxo espelha config_nginx_base / nginx_apioficial do projeto (upstream + certbot não interativo).

GREEN='\033[1;32m'
BLUE='\033[1;34m'
WHITE='\033[1;37m'
RED='\033[1;31m'
YELLOW='\033[1;33m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALADOR_ROOT="$(dirname "$SCRIPT_DIR")"
ARQUIVO_VARIAVEIS="${INSTALADOR_ROOT}/VARIAVEIS_INSTALACAO"

if [ "${EUID}" -ne 0 ]; then
  printf "${WHITE} >> Este script precisa ser executado como root.${WHITE}\n"
  exit 1
fi

banner() {
  clear
  printf "${BLUE}"
  echo "══════════════════════════════════════════════════════════════"
  echo "   Nginx: domínio + porta local + SSL (Certbot)"
  echo "══════════════════════════════════════════════════════════════"
  printf "${WHITE}\n"
}

validar_ambiente() {
  if ! command -v nginx >/dev/null 2>&1; then
    printf "${RED} >> Nginx não encontrado. Instale o Nginx primeiro.${WHITE}\n"
    return 1
  fi
  if ! command -v certbot >/dev/null 2>&1; then
    printf "${RED} >> Certbot não encontrado. Instale o Certbot antes de continuar.${WHITE}\n"
    return 1
  fi
  if ! systemctl is-active --quiet nginx 2>/dev/null; then
    printf "${YELLOW} >> Nginx não está ativo. Tentando iniciar...${WHITE}\n"
    if ! systemctl start nginx 2>/dev/null && ! service nginx start 2>/dev/null; then
      printf "${RED} >> Não foi possível iniciar o Nginx.${WHITE}\n"
      return 1
    fi
  fi
  return 0
}

nome_upstream_do_host() {
  local host="$1"
  local ns
  ns=$(printf '%s' "$host" | tr '.-' '_' | sed 's/[^a-zA-Z0-9_]/_/g' | sed 's/__*/_/g' | sed 's/^_\|_$//g')
  [ -z "$ns" ] && ns="srv"
  printf 'ucsrv_%s' "$ns"
}

main() {
  banner
  printf "${WHITE} >> Cria um virtual host no Nginx apontando para um serviço em 127.0.0.1:PORTA e emite SSL com Certbot (mesmo padrão da instalação principal).${WHITE}\n"
  echo

  if ! validar_ambiente; then
    sleep 3
    return 1
  fi

  if [ -f "$ARQUIVO_VARIAVEIS" ]; then
    # shellcheck source=/dev/null
    source "$ARQUIVO_VARIAVEIS" 2>/dev/null
  fi

  printf "${YELLOW} >> Domínio (ex: painel.seudominio.com ou https://painel.seudominio.com):${WHITE}\n"
  read -r dominio_in
  echo
  dominio_in=$(echo "$dominio_in" | tr -d '[:space:]')
  if [ -z "$dominio_in" ]; then
    printf "${RED} >> Domínio vazio.${WHITE}\n"
    sleep 2
    return 1
  fi
  local dominio_host
  dominio_host=$(echo "$dominio_in" | sed 's|^[Hh][Tt][Tt][Pp][Ss]*://||' | cut -d '/' -f1 | tr -d '[:space:]')
  if [ -z "$dominio_host" ]; then
    printf "${RED} >> Domínio inválido.${WHITE}\n"
    sleep 2
    return 1
  fi

  printf "${YELLOW} >> Porta local do serviço (ex: 8080, 3000, 9443):${WHITE}\n"
  read -r porta_in
  echo
  porta_in=$(echo "$porta_in" | tr -d '[:space:]')
  if ! [[ "$porta_in" =~ ^[0-9]+$ ]] || [ "$porta_in" -lt 1 ] || [ "$porta_in" -gt 65535 ]; then
    printf "${RED} >> Porta inválida. Use um número entre 1 e 65535.${WHITE}\n"
    sleep 2
    return 1
  fi

  local email_certbot="${email_deploy}"
  if [ -z "$email_certbot" ]; then
    printf "${YELLOW} >> E-mail para o Let's Encrypt (não encontrado em VARIAVEIS_INSTALACAO):${WHITE}\n"
    read -r email_certbot
    echo
  fi
  if [ -z "$email_certbot" ]; then
    printf "${RED} >> E-mail obrigatório para o Certbot.${WHITE}\n"
    sleep 2
    return 1
  fi

  local conf_slug
  conf_slug=$(printf '%s' "$dominio_host" | tr '.' '-')
  local conf_name="custom-srv-${conf_slug}"
  local upstream_name
  upstream_name=$(nome_upstream_do_host "$dominio_host")

  printf "\n${WHITE} >> Confirma criar / atualizar o site Nginx e emitir SSL?${WHITE}\n"
  printf "    Domínio:         ${GREEN}%s${WHITE}\n" "$dominio_host"
  printf "    Proxy para:      ${GREEN}127.0.0.1:%s${WHITE}\n" "$porta_in"
  printf "    Arquivo Nginx:   ${GREEN}/etc/nginx/sites-available/%s${WHITE}\n" "$conf_name"
  printf "    E-mail Certbot:  ${GREEN}%s${WHITE}\n" "$email_certbot"
  printf "${YELLOW} (s/N):${WHITE} "
  read -r conf
  conf=$(echo "$conf" | tr '[:lower:]' '[:upper:]')
  if [ "$conf" != "S" ]; then
    printf "${GREEN} >> Cancelado.${WHITE}\n"
    sleep 1
    return 0
  fi
  echo

  cat > "/etc/nginx/sites-available/${conf_name}" << EOF
upstream ${upstream_name} {
        server 127.0.0.1:${porta_in};
        keepalive 32;
    }
server {
  server_name ${dominio_host};
  location / {
    proxy_pass http://${upstream_name};
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

  ln -sf "/etc/nginx/sites-available/${conf_name}" "/etc/nginx/sites-enabled/${conf_name}"

  if ! nginx -t; then
    printf "${RED} >> Erro na sintaxe do Nginx. O arquivo em /etc/nginx/sites-available/${conf_name} foi escrito; corrija e rode nginx -t.${WHITE}\n"
    sleep 3
    return 1
  fi
  systemctl reload nginx

  printf "${GREEN} >> Nginx recarregado. Emitindo certificado SSL...${WHITE}\n"
  echo
  if ! certbot -m "$email_certbot" \
        --nginx \
        --agree-tos \
        -n \
        -d "$dominio_host" \
        --redirect; then
    printf "${YELLOW} >> Certbot pode ter falhado (DNS, firewall 80/443 ou limite Let's Encrypt). Verifique: certbot certificates${WHITE}\n"
    sleep 2
    return 1
  fi

  systemctl reload nginx 2>/dev/null || true
  echo
  printf "${GREEN} >> Concluído.${WHITE}\n"
  printf "${WHITE} >> Acesso HTTPS: ${BLUE}https://${dominio_host}${WHITE}\n"
  echo
  sleep 2
  return 0
}

main "$@"
