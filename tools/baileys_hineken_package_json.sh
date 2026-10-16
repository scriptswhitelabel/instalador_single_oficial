#!/usr/bin/env bash
# Baileys/Hineken: token + branch main no package.json do backend (MultiFlow-PRO).
# Uso: . tools/baileys_hineken_package_json.sh
#   mf_baileys_aplicar_token_package_json "$pkg" "$github_token"
#   mf_baileys_fixar_branch_main_package_json "$pkg"

# Fine-grained PAT (github_pat_*) com TOKEN@host → HTTP 401 no npm/git.
# Formato correto: https://x-access-token:TOKEN@github.com/...
mf_baileys_normalizar_url_token_package_json() {
  local pkg="${1:-}"
  [ -z "$pkg" ] || [ ! -f "$pkg" ] && return 0

  # Já aplicado como TOKEN@ → promove para x-access-token:TOKEN@
  # Cobre git+https:// e https://; PAT fino e classic.
  sed -i -E \
    's#(git\+https://|https://)(github_pat_[A-Za-z0-9_]+)@#\1x-access-token:\2@#g' \
    "$pkg"
  sed -i -E \
    's#(git\+https://|https://)(ghp_[A-Za-z0-9]+)@#\1x-access-token:\2@#g' \
    "$pkg"

  # Org antigo redireciona e quebra auth em alguns clientes
  sed -i \
    's|github.com/tswhitelabel/Hineken|github.com/scriptswhitelabel/Hineken|g' \
    "$pkg"
  return 0
}

mf_baileys_fixar_branch_main_package_json() {
  local pkg="${1:-}"
  [ -z "$pkg" ] && return 0
  [ ! -f "$pkg" ] && return 0
  mf_baileys_normalizar_url_token_package_json "$pkg"
  grep -qE 'scriptswhitelabel/Hineken|tswhitelabel/Hineken' "$pkg" 2>/dev/null || return 0
  sed -i -E 's|(github\.com/scriptswhitelabel/Hineken\.git)(#[^"]*)?|\1#main|g' "$pkg"
  return 0
}

# Substitui TOKEN_GITHUB e garante x-access-token: na URL do Baileys.
# $1 = caminho package.json; $2 = github_token
# Retorna 0 se ok / nada a fazer; 1 se token obrigatório e falhou.
mf_baileys_aplicar_token_package_json() {
  local pkg="${1:-}"
  local tok="${2:-}"
  local tok_clean tok_sed

  [ -z "$pkg" ] || [ ! -f "$pkg" ] && return 0

  # Sempre normaliza URLs já gravadas com PAT no formato errado (TOKEN@)
  mf_baileys_normalizar_url_token_package_json "$pkg"

  if ! grep -qE 'TOKEN_GITHUB|scriptswhitelabel/Hineken|tswhitelabel/Hineken' "$pkg" 2>/dev/null; then
    return 0
  fi

  [ -z "$tok" ] && return 1
  tok_clean=$(printf '%s' "$tok" | tr -d '\r\n ')
  [ -z "$tok_clean" ] && return 1
  tok_sed="${tok_clean//&/\\&}"

  if grep -q "TOKEN_GITHUB" "$pkg" 2>/dev/null; then
    # Placeholder clássico: (git+)https://TOKEN_GITHUB@github.com/...
    sed -i -E "s#(git\\+https://|https://)TOKEN_GITHUB@#\\1x-access-token:${tok_sed}@#g" "$pkg"
    # Qualquer TOKEN_GITHUB restante (ex.: já em x-access-token:TOKEN_GITHUB@)
    if grep -q "TOKEN_GITHUB" "$pkg" 2>/dev/null; then
      sed -i "s|TOKEN_GITHUB|${tok_sed}|g" "$pkg"
    fi
  fi

  mf_baileys_fixar_branch_main_package_json "$pkg"
  mf_baileys_normalizar_url_token_package_json "$pkg"

  if grep -q "TOKEN_GITHUB" "$pkg" 2>/dev/null; then
    echo "ERRO: TOKEN_GITHUB ainda presente no package.json após aplicar token."
    return 1
  fi

  # Confere que a URL do Baileys ficou com x-access-token (senão npm dá 401)
  if grep -qE 'Hineken\.git' "$pkg" 2>/dev/null \
    && grep -qE '(git\+)?https://(github_pat_|ghp_)' "$pkg" 2>/dev/null \
    && ! grep -qE 'x-access-token:(github_pat_|ghp_)' "$pkg" 2>/dev/null; then
    echo "ERRO: URL do Baileys sem x-access-token: — npm install falharia com HTTP 401."
    return 1
  fi
  return 0
}
