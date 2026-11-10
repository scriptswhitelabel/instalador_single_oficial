#!/usr/bin/env bash
# WhatsApp Web version: busca, cache no instalador single e aplica no .env do backend.
# Uso: . tools/mf_whatsapp_web_version.sh
#
# Arquivo canônico (lido pelo backend MultiFlow):
#   <instalador>/WHATSAPP_WEB_VERSION
# Também grava whatsapp_web_version= em VARIAVEIS_INSTALACAO*.

mf_whatsapp_web_version_instalador_dir() {
  local here
  if [ -n "${INSTALADOR_DIR:-}" ] && [ -d "${INSTALADOR_DIR}" ]; then
    printf '%s' "${INSTALADOR_DIR}"
    return 0
  fi
  here="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." 2>/dev/null && pwd)"
  if [ -n "$here" ] && [ -d "$here" ]; then
    printf '%s' "$here"
    return 0
  fi
  printf '%s' "/root/instalador_single_oficial"
}

mf_whatsapp_web_version_arquivo() {
  printf '%s/WHATSAPP_WEB_VERSION' "$(mf_whatsapp_web_version_instalador_dir)"
}

mf_whatsapp_web_version_fallback() {
  printf '%s' "2.3000.1053716622"
}

mf_whatsapp_web_version_validar() {
  local v="${1:-}"
  [[ "$v" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]
}

# Busca latest: 1) Baileys fetchLatest  2) wppconnect currentVersion  3) fallback
mf_whatsapp_web_version_buscar_remota() {
  local ver="" root nodebin=""

  for root in /home/deploy/*/backend; do
    [ -d "$root/node_modules/baileys" ] || continue
    nodebin="$(command -v node 2>/dev/null || true)"
    [ -z "$nodebin" ] && [ -x /usr/local/n/versions/node/20.19.4/bin/node ] && nodebin=/usr/local/n/versions/node/20.19.4/bin/node
    [ -z "$nodebin" ] && continue
    ver="$(
      cd "$root" 2>/dev/null || exit 0
      timeout 25 "$nodebin" -e '
        (async () => {
          try {
            const b = require("baileys");
            if (!b.fetchLatestBaileysVersion) process.exit(2);
            const r = await b.fetchLatestBaileysVersion();
            if (r && Array.isArray(r.version) && r.version.length === 3) {
              process.stdout.write(r.version.join("."));
              process.exit(0);
            }
          } catch (e) { process.exit(1); }
          process.exit(1);
        })();
      ' 2>/dev/null || true
    )"
    if mf_whatsapp_web_version_validar "$ver"; then
      printf '%s' "$ver"
      return 0
    fi
  done

  ver="$(
    curl -fsSL --max-time 12 \
      'https://raw.githubusercontent.com/wppconnect-team/wa-version/main/versions.json' 2>/dev/null \
      | tr -d '\n' \
      | sed -n 's/.*"currentVersion"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' \
      | head -1 \
      | sed 's/-alpha$//;s/-beta$//'
  )"
  if mf_whatsapp_web_version_validar "$ver"; then
    printf '%s' "$ver"
    return 0
  fi

  printf '%s' "$(mf_whatsapp_web_version_fallback)"
  return 0
}

# Lê cache do instalador (arquivo canônico ou VARIAVEIS).
mf_whatsapp_web_version_ler_cache() {
  local f v arquivo_var
  f="$(mf_whatsapp_web_version_arquivo)"
  if [ -f "$f" ]; then
    v="$(tr -d '\r\n[:space:]' < "$f" 2>/dev/null || true)"
    if mf_whatsapp_web_version_validar "$v"; then
      printf '%s' "$v"
      return 0
    fi
  fi

  for arquivo_var in \
    "$(mf_whatsapp_web_version_instalador_dir)/VARIAVEIS_INSTALACAO" \
    ${ARQUIVO_VARIAVEIS_USADO:-} \
    ${ARQUIVO_VARIAVEIS:-}
  do
    [ -n "$arquivo_var" ] && [ -f "$arquivo_var" ] || continue
    v="$(grep -m1 -E '^whatsapp_web_version[[:space:]]*=' "$arquivo_var" 2>/dev/null \
      | cut -d= -f2- | tr -d '\r' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//;s/^["'\'']//;s/["'\'']$//')"
    if mf_whatsapp_web_version_validar "$v"; then
      printf '%s' "$v"
      return 0
    fi
  done
  return 1
}

# Persiste no instalador (arquivo + VARIAVEIS*).
mf_whatsapp_web_version_salvar_instalador() {
  local ver="${1:-}" dir f
  mf_whatsapp_web_version_validar "$ver" || return 1
  dir="$(mf_whatsapp_web_version_instalador_dir)"
  mkdir -p "$dir" 2>/dev/null || true
  f="$(mf_whatsapp_web_version_arquivo)"
  printf '%s\n' "$ver" > "$f"
  chmod 644 "$f" 2>/dev/null || true

  _mf_wa_upsert_var_file() {
    local file="$1" key="whatsapp_web_version" val="$2"
    [ -f "$file" ] || return 0
    if grep -qE "^${key}[[:space:]]*=" "$file" 2>/dev/null; then
      sed -i -E "s|^${key}[[:space:]]*=.*|${key}=${val}|" "$file"
    else
      printf '\n%s=%s\n' "$key" "$val" >> "$file"
    fi
  }

  local vf
  for vf in "$dir"/VARIAVEIS_INSTALACAO "$dir"/VARIAVEIS_INSTALACAO_INSTANCIA_*; do
    [ -f "$vf" ] || continue
    _mf_wa_upsert_var_file "$vf" "$ver"
  done
  [ -n "${ARQUIVO_VARIAVEIS_USADO:-}" ] && [ -f "${ARQUIVO_VARIAVEIS_USADO}" ] && _mf_wa_upsert_var_file "${ARQUIVO_VARIAVEIS_USADO}" "$ver"
  [ -n "${ARQUIVO_VARIAVEIS:-}" ] && [ -f "${ARQUIVO_VARIAVEIS}" ] && _mf_wa_upsert_var_file "${ARQUIVO_VARIAVEIS}" "$ver"
  return 0
}

# Resolve versão: busca remota (default), salva no instalador, exporta WHATSAPP_WEB_VERSION.
# Uso em install/update: mf_whatsapp_web_version_resolver
# force=1 sempre rebusca; force=0 usa cache se válido e só rebusca se vazio.
mf_whatsapp_web_version_resolver() {
  local force="${1:-1}" ver=""
  if [ "$force" != "1" ]; then
    ver="$(mf_whatsapp_web_version_ler_cache || true)"
  fi
  if ! mf_whatsapp_web_version_validar "$ver"; then
    ver="$(mf_whatsapp_web_version_buscar_remota)"
  fi
  if ! mf_whatsapp_web_version_validar "$ver"; then
    ver="$(mf_whatsapp_web_version_fallback)"
  fi
  mf_whatsapp_web_version_salvar_instalador "$ver" || true
  WHATSAPP_WEB_VERSION="$ver"
  MF_WHATSAPP_WEB_VERSION_PADRAO="$ver"
  export WHATSAPP_WEB_VERSION MF_WHATSAPP_WEB_VERSION_PADRAO
  printf '%s' "$ver"
}

# Garante variáveis da política autônoma de versão WA no .env (só cria se ausente).
# Não sobrescreve valor já existente.
mf_whatsapp_web_version_ensure_policy_env() {
  local env_file="${1:-}"
  local added=0
  local key val pair

  [ -n "$env_file" ] && [ -f "$env_file" ] || return 1

  for pair in \
    "WHATSAPP_WEB_VERSION_REFRESH_HOUR=4" \
    "WHATSAPP_WEB_VERSION_REFRESH_MINUTE=20" \
    "WHATSAPP_WEB_VERSION_REFRESH_JITTER=1" \
    "WHATSAPP_WEB_VERSION_EXPIRE_DAYS=7" \
    "WHATSAPP_WEB_VERSION_UNKNOWN_MAX_AGE_DAYS=45" \
    "WHATSAPP_WEB_VERSION_RECOVER_STAGGER_MS=1500"
  do
    key="${pair%%=*}"
    val="${pair#*=}"
    if grep -qE "^${key}=" "$env_file" 2>/dev/null; then
      continue
    fi
    if [ "$added" -eq 0 ]; then
      {
        echo ""
        echo "# Política autônoma WA Web (Baileys): checagem diária / expire / soft-recover"
        echo "# Só adicionadas se ainda não existirem (update não duplica nem sobrescreve)."
      } >> "$env_file"
      added=1
    fi
    echo "${key}=${val}" >> "$env_file"
    if [ -n "${GREEN:-}" ] && [ -n "${WHITE:-}" ]; then
      printf "${GREEN} >> ${key}=${val} adicionada ao .env do backend.${WHITE}\n"
    else
      echo ">> ${key}=${val} adicionada ao .env do backend."
    fi
  done
  return 0
}

# Aplica/atualiza WHATSAPP_WEB_VERSION no .env do backend da empresa.
mf_whatsapp_web_version_aplicar_env() {
  local env_file="${1:-}"
  local ver="${2:-${WHATSAPP_WEB_VERSION:-${MF_WHATSAPP_WEB_VERSION_PADRAO:-}}}"
  local atual=""

  if [ -z "$ver" ] || ! mf_whatsapp_web_version_validar "$ver"; then
    ver="$(mf_whatsapp_web_version_resolver 1)"
  fi
  if [ -z "$env_file" ] || [ ! -f "$env_file" ]; then
    return 1
  fi

  if grep -q '^WHATSAPP_WEB_VERSION=' "$env_file" 2>/dev/null; then
    atual=$(grep '^WHATSAPP_WEB_VERSION=' "$env_file" | head -1 | cut -d= -f2- | tr -d '\r' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    if [ "$atual" != "$ver" ]; then
      sed -i "s|^WHATSAPP_WEB_VERSION=.*|WHATSAPP_WEB_VERSION=${ver}|" "$env_file"
    fi
  else
    echo "" >> "$env_file"
    echo "# Versão WhatsApp Web (Baileys) — preferir store do backend; instalador é fallback" >> "$env_file"
    echo "WHATSAPP_WEB_VERSION=${ver}" >> "$env_file"
  fi
  mf_whatsapp_web_version_ensure_policy_env "$env_file" || true
  return 0
}

# Instala/garante cron diário (04:20) — rede de segurança.
# A fonte da verdade é o store do backend (WHATSAPP_WEB_VERSION.meta.json).
mf_whatsapp_web_version_instalar_cron() {
  local cron_script
  cron_script="$(mf_whatsapp_web_version_instalador_dir)/tools/mf_whatsapp_web_version_cron.sh"
  [ -f "$cron_script" ] || return 1
  chmod +x "$cron_script" 2>/dev/null || true
  local line="20 4 * * * ${cron_script} >/dev/null 2>&1"
  local tmp
  tmp="$(mktemp)"
  crontab -l 2>/dev/null | grep -v 'mf_whatsapp_web_version_cron.sh' > "$tmp" || true
  echo "$line" >> "$tmp"
  crontab "$tmp"
  rm -f "$tmp"
  echo "cron instalado: $line"
}
