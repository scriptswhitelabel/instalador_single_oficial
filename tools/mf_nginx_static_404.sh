#!/bin/bash
# Garante location ^~ /static/ com try_files =404 no Nginx do frontend.
# Evita Unexpected token '<' (HTML no lugar do JS) / loop no splash após deploy.
#
# Uso:
#   source tools/mf_nginx_static_404.sh
#   mf_nginx_garantir_static_404 "minhaempresa"

# www-data precisa atravessar /home/deploy/... e ler o build quando location ^~ /static/
# serve arquivos direto do disco (sem proxy para o Node).
# Sem o+x em /home/deploy (padrão 750 do useradd) — ou em algum pai do caminho —
# o nginx devolve 403/404 (Permission denied) e o splash entra em loop de ?_nocache=.
mf_nginx_ensure_static_readable() {
  local build_root="${1:-}"
  local d

  if [ -d /home/deploy ]; then
    # Mantém dono; só garante travessia por others (nginx/www-data).
    chmod o+x /home/deploy 2>/dev/null || chmod 755 /home/deploy 2>/dev/null || true
  fi

  if [ -n "$build_root" ] && [ -d "$build_root" ]; then
    # Cada segmento do caminho até o build precisa de o+x (ex.: empresa/, frontend/).
    d="$build_root"
    while [ -n "$d" ] && [ "$d" != "/" ]; do
      if [ -d "$d" ]; then
        chmod o+x "$d" 2>/dev/null || true
      fi
      case "$d" in
        /home/deploy) break ;;
      esac
      d=$(dirname "$d")
    done
    # Arquivos/pastas do CRA: leitura (+ execução em diretórios) para www-data.
    chmod -R a+rX "$build_root" 2>/dev/null || true
  fi
}

mf_nginx_static_404_snippet() {
  local empresa="${1:-}"
  local build_root="${2:-/home/deploy/${empresa}/frontend/build}"
  cat <<SNIP
  # Assets com hash: 404 real se o arquivo não existir (nunca proxy → HTML do SPA).
  # Evita Unexpected token '<' / loop no splash após deploy.
  location ^~ /static/ {
    root ${build_root};
    try_files \$uri =404;
    expires 1y;
    add_header Cache-Control "public, max-age=31536000, immutable";
    access_log off;
  }
SNIP
}

# Insere o bloco /static/ =404 em cada server{} do conf frontend, se ainda não existir.
mf_nginx_garantir_static_404() {
  local empresa="${1:-}"
  local conf build_root tmp

  if [ -z "$empresa" ]; then
    echo "mf_nginx_garantir_static_404: informe a empresa" >&2
    return 1
  fi

  conf="/etc/nginx/sites-available/${empresa}-frontend"
  build_root="/home/deploy/${empresa}/frontend/build"

  # Sempre: mesmo se o location já existir, permissões podem ter voltado a 750 no update.
  mf_nginx_ensure_static_readable "$build_root"

  if [ ! -f "$conf" ]; then
    printf "${YELLOW:-} >> Nginx frontend (%s): conf não encontrada (%s), pulando.${WHITE:-}\n" "$empresa" "$conf"
    return 0
  fi

  if grep -qE 'location[[:space:]]+\^~[[:space:]]+/static/' "$conf"; then
    printf "${GREEN:-} >> Nginx frontend (%s): location /static/ =404 já presente (perms /home/deploy ok).${WHITE:-}\n" "$empresa"
    return 0
  fi

  tmp=$(mktemp) || return 1
  awk -v root="$build_root" '
    BEGIN { inserted_in_server = 0 }
    /^[[:space:]]*server[[:space:]]*\{/ { inserted_in_server = 0 }
    /^[[:space:]]*location[[:space:]]+\/[[:space:]]*\{/ && !inserted_in_server {
      print "  # Assets com hash: 404 real se o arquivo nao existir (nunca proxy -> HTML do SPA)."
      print "  # Evita Unexpected token / loop no splash apos deploy."
      print "  location ^~ /static/ {"
      print "    root " root ";"
      print "    try_files $uri =404;"
      print "    expires 1y;"
      print "    add_header Cache-Control \"public, max-age=31536000, immutable\";"
      print "    access_log off;"
      print "  }"
      inserted_in_server = 1
    }
    { print }
  ' "$conf" > "$tmp" || { rm -f "$tmp"; return 1; }

  if ! grep -qE 'location[[:space:]]+\^~[[:space:]]+/static/' "$tmp"; then
    printf "${YELLOW:-} >> Nginx frontend (%s): não achou location / para inserir /static/.${WHITE:-}\n" "$empresa"
    rm -f "$tmp"
    return 1
  fi

  cp -a "$conf" "${conf}.bak-static404" || { rm -f "$tmp"; return 1; }
  mv "$tmp" "$conf" || {
    mv "${conf}.bak-static404" "$conf" 2>/dev/null || true
    return 1
  }

  if nginx -t >/dev/null 2>&1; then
    systemctl reload nginx 2>/dev/null || service nginx reload 2>/dev/null || true
    rm -f "${conf}.bak-static404"
    printf "${GREEN:-} >> Nginx frontend (%s): location /static/ =404 aplicada.${WHITE:-}\n" "$empresa"
    return 0
  fi

  mv "${conf}.bak-static404" "$conf"
  printf "${YELLOW:-} >> Nginx frontend (%s): nginx -t falhou após patch; conf restaurada.${WHITE:-}\n" "$empresa"
  return 1
}
