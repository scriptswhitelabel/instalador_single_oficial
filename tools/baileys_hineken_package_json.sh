#!/usr/bin/env bash
# Baileys/Hineken: token + branch main no package.json do backend (MultiFlow-PRO).
# Uso: . tools/baileys_hineken_package_json.sh
#   mf_baileys_aplicar_token_package_json "$pkg" "$github_token"
#   mf_baileys_fixar_branch_main_package_json "$pkg"
#   mf_baileys_git_instead_of_token "$github_token"   # opcional, usuário deploy

# Fine-grained PAT (github_pat_*) com TOKEN@host → HTTP 401 no npm/git.
# Formato correto: https://x-access-token:TOKEN@github.com/...

mf_baileys_token_limpo() {
  printf '%s' "${1:-}" | tr -d '\r\n '
}

# Reescreve QUALQUER URL do Hineken para git+https://x-access-token:TOKEN@...#main
# (evita sed frágil TOKEN@ / placeholder parcial que deixa PAT fino sem usuário).
mf_baileys_forcar_url_hineken_arquivo() {
  local arquivo="${1:-}"
  local tok tok_sed url_ok
  tok=$(mf_baileys_token_limpo "${2:-}")
  [ -z "$arquivo" ] || [ ! -f "$arquivo" ] && return 0
  [ -z "$tok" ] && return 1
  # Escapes para sed: & e \  (delimitador ~ — URL tem #main e @)
  tok_sed=$(printf '%s' "$tok" | sed -e 's/[&\\]/\\&/g')
  url_ok="git+https://x-access-token:${tok_sed}@github.com/scriptswhitelabel/Hineken.git#main"

  # Org antigo
  sed -i \
    's|github.com/tswhitelabel/Hineken|github.com/scriptswhitelabel/Hineken|g' \
    "$arquivo"

  # URL com credencial (TOKEN_GITHUB, github_pat_*, ghp_*, x-access-token:*, etc.)
  # NÃO usar # como delimitador: a URL de destino contém #main
  sed -i -E \
    "s~(git\\+https://|https://)[^[:space:]\"']+@github\\.com/scriptswhitelabel/Hineken\\.git[^\"']*~${url_ok}~g" \
    "$arquivo"

  # URL limpa sem credencial
  sed -i -E \
    "s~(git\\+https://|https://)github\\.com/scriptswhitelabel/Hineken\\.git[^\"']*~${url_ok}~g" \
    "$arquivo"

  # Placeholder residual em qualquer posição
  if grep -q "TOKEN_GITHUB" "$arquivo" 2>/dev/null; then
    sed -i -E \
      "s~(git\\+https://|https://)TOKEN_GITHUB@~\\1x-access-token:${tok_sed}@~g" \
      "$arquivo"
    sed -i "s|TOKEN_GITHUB|${tok_sed}|g" "$arquivo"
  fi

  # Promove PAT fino/classic ainda em TOKEN@ (sem x-access-token)
  sed -i -E \
    's~(git\+https://|https://)(github_pat_[A-Za-z0-9_]+)@~\1x-access-token:\2@~g' \
    "$arquivo"
  sed -i -E \
    's~(git\+https://|https://)(ghp_[A-Za-z0-9]+)@~\1x-access-token:\2@~g' \
    "$arquivo"

  return 0
}

mf_baileys_normalizar_url_token_arquivo() {
  local arquivo="${1:-}"
  [ -z "$arquivo" ] || [ ! -f "$arquivo" ] && return 0
  sed -i -E \
    's#(git\+https://|https://)(github_pat_[A-Za-z0-9_]+)@#\1x-access-token:\2@#g' \
    "$arquivo"
  sed -i -E \
    's#(git\+https://|https://)(ghp_[A-Za-z0-9]+)@#\1x-access-token:\2@#g' \
    "$arquivo"
  sed -i \
    's|github.com/tswhitelabel/Hineken|github.com/scriptswhitelabel/Hineken|g' \
    "$arquivo"
  return 0
}

mf_baileys_normalizar_url_token_package_json() {
  mf_baileys_normalizar_url_token_arquivo "${1:-}"
}

mf_baileys_normalizar_urls_backend() {
  local pkg="${1:-}"
  local tok="${2:-}"
  local dir lock
  [ -z "$pkg" ] || [ ! -f "$pkg" ] && return 0
  dir=$(dirname "$pkg")
  if [ -n "$tok" ]; then
    mf_baileys_forcar_url_hineken_arquivo "$pkg" "$tok" || return 1
  else
    mf_baileys_normalizar_url_token_arquivo "$pkg"
  fi
  lock="${dir}/package-lock.json"
  if [ -f "$lock" ]; then
    if [ -n "$tok" ]; then
      mf_baileys_forcar_url_hineken_arquivo "$lock" "$tok" || true
    else
      mf_baileys_normalizar_url_token_arquivo "$lock"
    fi
  fi
  return 0
}

mf_baileys_fixar_branch_main_package_json() {
  local pkg="${1:-}"
  [ -z "$pkg" ] && return 0
  [ ! -f "$pkg" ] && return 0
  grep -qE 'scriptswhitelabel/Hineken|tswhitelabel/Hineken' "$pkg" 2>/dev/null || return 0
  sed -i -E 's|(github\.com/scriptswhitelabel/Hineken\.git)(#[^"]*)?|\1#main|g' "$pkg"
  return 0
}

mf_baileys_package_usa_git_hineken() {
  local pkg="${1:-}"
  [ -f "$pkg" ] || return 1
  grep -qE 'Hineken\.git|TOKEN_GITHUB' "$pkg" 2>/dev/null
}

# git url.insteadOf: npm/git reescreve https://github.com/ → x-access-token (backup).
# Chamar como o usuário que roda npm (deploy).
mf_baileys_git_instead_of_token() {
  local tok
  tok=$(mf_baileys_token_limpo "${1:-}")
  [ -z "$tok" ] && return 1
  if ! command -v git >/dev/null 2>&1; then
    return 0
  fi
  git config --global url."https://x-access-token:${tok}@github.com/".insteadOf "https://github.com/" 2>/dev/null || true
  git config --global url."https://x-access-token:${tok}@github.com/".insteadOf "git+https://github.com/" 2>/dev/null || true
  # Formato antigo TOKEN@ (sem usuário) → força x-access-token
  git config --global url."https://x-access-token:${tok}@github.com/".insteadOf "https://${tok}@github.com/" 2>/dev/null || true
  return 0
}

# Substitui TOKEN_GITHUB e força URL Hineken com x-access-token:.
# $1 = caminho package.json; $2 = github_token
# Retorna 0 se ok / nada a fazer; 1 se token obrigatório e falhou.
mf_baileys_aplicar_token_package_json() {
  local pkg="${1:-}"
  local tok
  local dir lock
  tok=$(mf_baileys_token_limpo "${2:-}")

  [ -z "$pkg" ] || [ ! -f "$pkg" ] && return 0

  if ! grep -qE 'TOKEN_GITHUB|scriptswhitelabel/Hineken|tswhitelabel/Hineken' "$pkg" 2>/dev/null; then
    return 0
  fi

  [ -z "$tok" ] && return 1

  mf_baileys_forcar_url_hineken_arquivo "$pkg" "$tok" || return 1
  mf_baileys_fixar_branch_main_package_json "$pkg"

  dir=$(dirname "$pkg")
  lock="${dir}/package-lock.json"
  if [ -f "$lock" ]; then
    mf_baileys_forcar_url_hineken_arquivo "$lock" "$tok" || true
  fi

  if grep -q "TOKEN_GITHUB" "$pkg" 2>/dev/null; then
    echo "ERRO: TOKEN_GITHUB ainda presente no package.json após aplicar token."
    return 1
  fi

  # URL ainda no formato TOKEN@ (sem x-access-token) → falha explícita
  if grep -qE 'Hineken\.git' "$pkg" 2>/dev/null; then
    if grep -qE '(git\+https://|https://)(github_pat_|ghp_)' "$pkg" 2>/dev/null; then
      echo "ERRO: URL do Baileys sem x-access-token: — npm install falharia com HTTP 401."
      return 1
    fi
    if ! grep -q 'x-access-token:' "$pkg" 2>/dev/null; then
      if grep -qE '(git\+https://|https://)github\.com/.*/Hineken' "$pkg" 2>/dev/null; then
        echo "ERRO: Baileys aponta para Hineken sem token na URL."
        return 1
      fi
    fi
  fi
  return 0
}
