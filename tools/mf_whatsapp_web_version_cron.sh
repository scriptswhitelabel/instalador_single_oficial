#!/usr/bin/env bash
# Rede de segurança (NÃO é fonte da verdade).
# O backend MultiFlow gerencia WHATSAPP_WEB_VERSION.meta.json no próprio cwd.
# Este cron só age se nenhum backend tiver pin válido / perto de expirar,
# ou para sincronizar .env a partir do store do sistema.
set -euo pipefail

INSTALADOR_DIR="${INSTALADOR_DIR:-/root/instalador_single_oficial}"
LOG_FILE="${MF_WA_VERSION_LOG:-/var/log/mf-whatsapp-web-version.log}"
HELPER="${INSTALADOR_DIR}/tools/mf_whatsapp_web_version.sh"
EXPIRE_DAYS="${WHATSAPP_WEB_VERSION_EXPIRE_DAYS:-7}"
UNKNOWN_MAX_AGE="${WHATSAPP_WEB_VERSION_UNKNOWN_MAX_AGE_DAYS:-45}"
CATALOG_URL="https://raw.githubusercontent.com/wppconnect-team/wa-version/main/versions.json"
WA_FILE="${INSTALADOR_DIR}/WHATSAPP_WEB_VERSION"

mkdir -p "$(dirname "$LOG_FILE")" 2>/dev/null || true
exec >>"$LOG_FILE" 2>&1
echo "===== $(date '+%Y-%m-%d %H:%M:%S') mf_whatsapp_web_version_cron (safety-net) ====="

if [ ! -f "$HELPER" ]; then
  echo "ERRO: helper ausente: $HELPER"
  exit 1
fi
# shellcheck source=/dev/null
. "$HELPER"

# 1) Preferir store do backend (fonte do sistema)
BEST_VER=""
BEST_EXPIRE=""
BEST_PINNED=""
BEST_META=""
for meta in /home/deploy/*/backend/WHATSAPP_WEB_VERSION.meta.json; do
  [ -f "$meta" ] || continue
  parsed="$(python3 -c '
import json,sys
try:
  m=json.load(open(sys.argv[1], encoding="utf-8"))
except Exception:
  sys.exit(0)
ver=str(m.get("version") or "").strip()
print(ver)
print(m.get("expireAt") or "")
print(m.get("pinnedAt") or m.get("updatedAt") or "")
' "$meta" 2>/dev/null || true)"
  ver="$(printf '%s\n' "$parsed" | sed -n '1p')"
  exp="$(printf '%s\n' "$parsed" | sed -n '2p')"
  pin="$(printf '%s\n' "$parsed" | sed -n '3p')"
  if mf_whatsapp_web_version_validar "$ver"; then
    BEST_VER="$ver"
    BEST_EXPIRE="$exp"
    BEST_PINNED="$pin"
    BEST_META="$meta"
    echo "backend_store=${meta} version=${ver} expire=${exp:-?} pinned=${pin:-?}"
    break
  fi
done

decide_near_expire() {
  local ver="$1" expire_iso="$2" pinned_iso="$3"
  if [ -n "$expire_iso" ]; then
    local days_left
    days_left="$(python3 -c '
import sys
from datetime import datetime, timezone
raw=sys.argv[1]
try:
  s=raw.replace("Z","+00:00")
  exp=datetime.fromisoformat(s)
  if exp.tzinfo is None:
    exp=exp.replace(tzinfo=timezone.utc)
  now=datetime.now(timezone.utc)
  print((exp-now).total_seconds()/86400.0)
except Exception:
  print("nan")
' "$expire_iso")"
    echo "days_left=${days_left} threshold=${EXPIRE_DAYS}"
    python3 -c '
import sys
try:
  days=float(sys.argv[1]); thr=float(sys.argv[2])
  raise SystemExit(0 if days<=thr else 1)
except Exception:
  raise SystemExit(1)
' "$days_left" "$EXPIRE_DAYS"
    return $?
  fi

  # expire desconhecido → só se pin antigo
  local age
  age="$(python3 -c '
import sys
from datetime import datetime, timezone
raw=sys.argv[1]
if not raw:
  print(999); raise SystemExit
try:
  s=raw.replace("Z","+00:00")
  pin=datetime.fromisoformat(s)
  if pin.tzinfo is None:
    pin=pin.replace(tzinfo=timezone.utc)
  now=datetime.now(timezone.utc)
  print((now-pin).total_seconds()/86400.0)
except Exception:
  print(999)
' "${pinned_iso:-}")"
  echo "expire=desconhecido age_days=${age} max=${UNKNOWN_MAX_AGE}"
  python3 -c '
import sys
try:
  raise SystemExit(0 if float(sys.argv[1])>=float(sys.argv[2]) else 1)
except Exception:
  raise SystemExit(1)
' "$age" "$UNKNOWN_MAX_AGE"
}

VER=""
if [ -n "$BEST_VER" ]; then
  if decide_near_expire "$BEST_VER" "$BEST_EXPIRE" "$BEST_PINNED"; then
    echo "backend pin perto/expirado — backends devem auto-atualizar; cron nao forca latest"
    VER="$BEST_VER"
  else
    echo "backend pin ainda valido — sincroniza instalador/.env sem buscar latest"
    VER="$BEST_VER"
  fi
else
  CURRENT="$(mf_whatsapp_web_version_ler_cache 2>/dev/null || true)"
  if ! mf_whatsapp_web_version_validar "${CURRENT:-}"; then
    echo "sem store de backend e sem cache — safety-net busca latest"
    VER="$(mf_whatsapp_web_version_resolver 1)"
  else
    EXPIRE_ISO="$(
      curl -fsSL --max-time 15 "$CATALOG_URL" 2>/dev/null | python3 -c '
import json,sys
cur=sys.argv[1]
def norm(v):
  return str(v or "").replace("-alpha","").replace("-beta","").strip()
cur=norm(cur)
try:
  data=json.load(sys.stdin)
except Exception:
  sys.exit(0)
for item in data.get("versions") or []:
  if norm(item.get("version"))==cur:
    print(item.get("expire") or "")
    break
' "$CURRENT"
    )"
    PINNED=""
    if [ -f "$WA_FILE" ]; then
      PINNED="$(python3 -c '
import pathlib, datetime, sys
p=pathlib.Path(sys.argv[1])
print(datetime.datetime.utcfromtimestamp(p.stat().st_mtime).isoformat()+"Z")
' "$WA_FILE" 2>/dev/null || true)"
    fi
    echo "fallback_installer current=${CURRENT} expire=${EXPIRE_ISO:-desconhecido}"
    if decide_near_expire "$CURRENT" "$EXPIRE_ISO" "$PINNED"; then
      echo "installer pin perto/expirado e sem backend store — buscando latest"
      VER="$(mf_whatsapp_web_version_resolver 1)"
    else
      echo "installer pin ainda valido — mantém"
      VER="$CURRENT"
    fi
  fi
fi

echo "after=${VER} source_meta=${BEST_META:-none}"
mf_whatsapp_web_version_salvar_instalador "$VER" || true

APPLIED=0
for envf in /home/deploy/*/backend/.env; do
  [ -f "$envf" ] || continue
  # Nao sobrescreve se o backend ja tem meta proprio com outra versao mais nova de decisao.
  backend_dir="$(dirname "$envf")"
  meta_f="${backend_dir}/WHATSAPP_WEB_VERSION.meta.json"
  if [ -f "$meta_f" ]; then
    meta_ver="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1],encoding="utf-8")).get("version") or "")' "$meta_f" 2>/dev/null || true)"
    if mf_whatsapp_web_version_validar "$meta_ver"; then
      if mf_whatsapp_web_version_aplicar_env "$envf" "$meta_ver"; then
        APPLIED=$((APPLIED + 1))
      fi
      continue
    fi
  fi
  if mf_whatsapp_web_version_aplicar_env "$envf" "$VER"; then
    APPLIED=$((APPLIED + 1))
  fi
done
echo "envs_atualizados=${APPLIED}"
date -u '+%Y-%m-%dT%H:%M:%SZ' > "${INSTALADOR_DIR}/WHATSAPP_WEB_VERSION.updated_at" 2>/dev/null || true
echo "OK"
