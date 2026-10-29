#!/bin/bash
# Garante VOZ_BRIDGE_SECRET no .env do CRM (UltraWhats / Multiflow) e/ou do MultiFlow VOZ.
# Não sobrescreve valor já preenchido; se um lado tem e o outro não, copia; se nenhum tem, gera.
#
# Uso (CRM, com empresa definida):
#   source tools/mf_env_voz_bridge_secret.sh
#   verificar_e_adicionar_voz_bridge_secret
#
# Uso direto (caminhos explícitos):
#   mf_garantir_voz_bridge_secret "/home/deploy/X/backend/.env" "/home/deploy/multiflow-voz/backend/.env"

MF_VOZ_ROOT_PADRAO="${MF_VOZ_ROOT_PADRAO:-/home/deploy/multiflow-voz}"

_mf_voz_bridge_ler() {
  local env_file="$1"
  local key="$2"
  local val=""
  [ -f "$env_file" ] || return 0
  val=$(grep -m1 "^${key}=" "$env_file" 2>/dev/null | cut -d= -f2- | tr -d '\r' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//;s/^"//;s/"$//;s/^'\''//;s/'\''$//')
  printf '%s' "$val"
}

_mf_voz_bridge_valor_em() {
  local env_file="$1"
  local v=""
  v="$(_mf_voz_bridge_ler "$env_file" "VOZ_BRIDGE_SECRET")"
  if [ -z "$v" ]; then
    v="$(_mf_voz_bridge_ler "$env_file" "MULTIFLOW_VOZ_BRIDGE_SECRET")"
  fi
  printf '%s' "$v"
}

_mf_voz_bridge_gerar() {
  if command -v openssl >/dev/null 2>&1; then
    openssl rand -hex 24 2>/dev/null && return 0
  fi
  head -c 48 /dev/urandom 2>/dev/null | xxd -p | tr -d '\n' | head -c 48
}

_mf_voz_bridge_fix_owner() {
  local env_file="$1"
  [ -f "$env_file" ] || return 0
  if type garantir_permissoes_env_backend >/dev/null 2>&1; then
    garantir_permissoes_env_backend "$env_file"
  else
    chown deploy:deploy "$env_file" 2>/dev/null || true
    chmod 600 "$env_file" 2>/dev/null || chmod 660 "$env_file" 2>/dev/null || true
  fi
}

# Acrescenta VOZ_BRIDGE_SECRET só se a chave canônica estiver ausente ou vazia.
_mf_voz_bridge_escrever_se_falta() {
  local env_file="$1"
  local secret="$2"
  local atual=""
  local rotulo="${3:-.env}"

  if [ -z "$env_file" ] || [ -z "$secret" ]; then
    return 0
  fi
  if [ ! -f "$env_file" ]; then
    printf "${YELLOW} >> AVISO: %s não encontrado — pulando VOZ_BRIDGE_SECRET.\n${WHITE}" "$env_file"
    return 0
  fi

  atual="$(_mf_voz_bridge_valor_em "$env_file")"
  if [ -n "$atual" ]; then
    # Garante a chave canônica mesmo se só existir o alias MULTIFLOW_*
    if ! grep -q '^VOZ_BRIDGE_SECRET=' "$env_file"; then
      echo "" >> "$env_file"
      echo "# Ponte Calling Oficial ↔ MultiFlow VOZ (mesmo valor nos dois lados)" >> "$env_file"
      echo "VOZ_BRIDGE_SECRET=${atual}" >> "$env_file"
      printf "${GREEN} >> VOZ_BRIDGE_SECRET espelhada (a partir do alias) em %s.${WHITE}\n" "$rotulo"
      _mf_voz_bridge_fix_owner "$env_file"
    else
      printf "${GREEN} >> VOZ_BRIDGE_SECRET já existe em %s.${WHITE}\n" "$rotulo"
    fi
    return 0
  fi

  if grep -q '^VOZ_BRIDGE_SECRET=' "$env_file"; then
    sed -i "s|^VOZ_BRIDGE_SECRET=.*|VOZ_BRIDGE_SECRET=${secret}|" "$env_file"
  else
    echo "" >> "$env_file"
    echo "# Ponte Calling Oficial ↔ MultiFlow VOZ (mesmo valor nos dois lados)" >> "$env_file"
    echo "VOZ_BRIDGE_SECRET=${secret}" >> "$env_file"
  fi
  printf "${GREEN} >> VOZ_BRIDGE_SECRET adicionada em %s.${WHITE}\n" "$rotulo"
  _mf_voz_bridge_fix_owner "$env_file"
}

# Resolve o segredo a usar: CRM → VOZ → gerar.
mf_resolver_voz_bridge_secret() {
  local crm_env="${1:-}"
  local voz_env="${2:-}"
  local v=""

  if [ -n "$crm_env" ]; then
    v="$(_mf_voz_bridge_valor_em "$crm_env")"
    if [ -n "$v" ]; then
      printf '%s' "$v"
      return 0
    fi
  fi
  if [ -n "$voz_env" ]; then
    v="$(_mf_voz_bridge_valor_em "$voz_env")"
    if [ -n "$v" ]; then
      printf '%s' "$v"
      return 0
    fi
  fi
  _mf_voz_bridge_gerar
}

# Garante o segredo nos arquivos informados (somente preenche ausência).
mf_garantir_voz_bridge_secret() {
  local crm_env="${1:-}"
  local voz_env="${2:-}"
  local secret=""

  if [ -z "$crm_env" ] && [ -z "$voz_env" ]; then
    return 0
  fi

  printf "${WHITE} >> Conferindo VOZ_BRIDGE_SECRET (ponte CRM ↔ VOZ)...\n${WHITE}"
  secret="$(mf_resolver_voz_bridge_secret "$crm_env" "$voz_env")"
  if [ -z "$secret" ]; then
    printf "${RED} >> Não foi possível gerar VOZ_BRIDGE_SECRET.\n${WHITE}"
    return 0
  fi

  if [ -n "$crm_env" ]; then
    _mf_voz_bridge_escrever_se_falta "$crm_env" "$secret" "CRM (${crm_env})"
  fi
  if [ -n "$voz_env" ]; then
    _mf_voz_bridge_escrever_se_falta "$voz_env" "$secret" "VOZ (${voz_env})"
  fi
}

# Hook padrão dos atualizadores / instalador (usa $empresa).
verificar_e_adicionar_voz_bridge_secret() {
  if [ -z "${empresa:-}" ]; then
    printf "${RED} >> ERRO: Variável 'empresa' não está definida!\n${WHITE}"
    return 0
  fi

  local crm_env="/home/deploy/${empresa}/backend/.env"
  local voz_env=""
  if [ -f "${MF_VOZ_ROOT_PADRAO}/backend/.env" ]; then
    voz_env="${MF_VOZ_ROOT_PADRAO}/backend/.env"
  fi

  if [ ! -f "$crm_env" ] && [ -z "$voz_env" ]; then
    printf "${YELLOW} >> AVISO: .env do CRM e do VOZ ausentes — pulando VOZ_BRIDGE_SECRET.\n${WHITE}"
    return 0
  fi

  # CRM pode não existir neste VPS (só VOZ); ainda assim garante o .env da voz.
  if [ ! -f "$crm_env" ]; then
    crm_env=""
  fi

  mf_garantir_voz_bridge_secret "$crm_env" "$voz_env"
}
