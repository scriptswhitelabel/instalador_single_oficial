#!/bin/bash
# Sincroniza o repositório da instância com origin (descarta alterações locais e
# arquivos não rastreados que impediriam checkout/merge).
#
# Uso (como usuário deploy, dentro do diretório do projeto):
#   . /root/instalador_single_oficial/tools/git_sincronizar_repositorio.sh
#   mf_git_sincronizar_repositorio ""                    # Mais Recente (origin)
#   mf_git_sincronizar_repositorio "abc123" "atualizacao"  # commit fixo
#
# Opcional (como root, antes do sudo su - deploy):
#   mf_git_aplicar_token_remote "/home/deploy/EMPRESA" "$github_token"

mf_git_urlencode() {
  local length="${#1}"
  local i c
  for ((i = 0; i < length; i++)); do
    c="${1:i:1}"
    case $c in
    [a-zA-Z0-9.~_-]) printf '%s' "$c" ;;
    *) printf '%%%02X' "'$c" ;;
    esac
  done
}

# Grava github_token no remote origin (HTTPS) para fetch sem prompt interativo.
# $1 = raiz do app (/home/deploy/empresa). $2 = token.
mf_git_aplicar_token_remote() {
  local app_root="${1:-}"
  local token="${2:-}"
  [ -z "$app_root" ] || [ -z "$token" ] && return 1
  [ ! -d "${app_root}/.git" ] && return 1

  local current path_repo tok_enc new_url
  current=$(git -c "safe.directory=${app_root}" -C "${app_root}" remote get-url origin 2>/dev/null) || return 1
  case "$current" in
    https://*) ;;
    *) return 0 ;;
  esac

  path_repo=$(printf '%s' "$current" | sed 's|https://[^@]*@||' | sed 's|^https://||')
  [[ "$path_repo" != *.git ]] && path_repo="${path_repo}.git"
  tok_enc=$(mf_git_urlencode "$token")
  new_url="https://${tok_enc}@${path_repo}"

  if git -c "safe.directory=${app_root}" -C "${app_root}" remote set-url origin "$new_url"; then
    return 0
  fi
  return 1
}

mf_git_clean_preservando_locais() {
  git clean -fd \
    -e api_transcricao/run_transcricao.sh \
    -e backend/.env \
    -e frontend/.env \
    -e api_oficial/.env \
    2>/dev/null || true
}

mf_git_detectar_deploy_branch() {
  if git show-ref --verify --quiet refs/remotes/origin/MULTI100-OFICIAL-u21; then
    printf '%s\n' MULTI100-OFICIAL-u21
  elif git show-ref --verify --quiet refs/remotes/origin/main; then
    printf '%s\n' main
  elif git show-ref --verify --quiet refs/remotes/origin/master; then
    printf '%s\n' master
  fi
}

# Evita hang: git pedindo usuário/senha dentro de heredoc sem TTY.
mf_git_desabilitar_prompt() {
  export GIT_TERMINAL_PROMPT=0
  export GIT_ASKPASS=true
  export SSH_ASKPASS=true
}

# $1 = commit (vazio = Mais Recente). $2 = prefixo opcional da branch temporária (commit fixo).
# Define MF_GIT_DEPLOY_BRANCH quando sincroniza com origin.
mf_git_sincronizar_repositorio() {
  local commit_alvo="${1:-}"
  local branch_prefix="${2:-atualizacao}"

  mf_git_desabilitar_prompt

  echo " >> Git: liberando escrita em .git (pode demorar em repos grandes)..."
  chmod -R u+w .git 2>/dev/null || true

  echo " >> Git: fetch do origin (sem prompt interativo)..."
  if ! git fetch --all --tags --prune; then
    echo " >> Aviso: fetch --all falhou; tentando git fetch origin..."
    if ! git fetch origin; then
      echo "ERRO: git fetch falhou (rede ou credencial/token inválido no remote origin)."
      echo "ERRO: Verifique github_token no arquivo da instância e o remote: git remote -v"
      return 1
    fi
  fi
  echo " >> Git: fetch concluído."

  mf_git_clean_preservando_locais

  if [ -n "$commit_alvo" ]; then
    if ! git cat-file -e "${commit_alvo}^{commit}" 2>/dev/null; then
      echo " >> Commit ${commit_alvo} não encontrado localmente; buscando no remoto..."
      git fetch origin "${commit_alvo}" 2>/dev/null || true
      git fetch origin --depth=2147483647 2>/dev/null || git fetch --unshallow 2>/dev/null || true
    fi
    if ! git cat-file -e "${commit_alvo}^{commit}" 2>/dev/null; then
      echo "ERRO: Commit ${commit_alvo} não encontrado após fetch."
      return 1
    fi
    echo " >> Git: checkout do commit ${commit_alvo}..."
    git checkout -f "${commit_alvo}" || return 1
    git reset --hard "${commit_alvo}" || return 1
    local _br_atu="${branch_prefix}-$(date +%Y%m%d-%H%M%S)"
    git checkout -b "$_br_atu" 2>/dev/null || git checkout "$_br_atu" 2>/dev/null || true
    local _head_atu
    _head_atu=$(git rev-parse HEAD 2>/dev/null)
    if [ "$_head_atu" != "$commit_alvo" ]; then
      echo "ERRO: Checkout falhou. Esperado ${commit_alvo}, atual ${_head_atu}"
      return 1
    fi
    echo " >> Git: checkout concluído (${commit_alvo})."
    return 0
  fi

  MF_GIT_DEPLOY_BRANCH=$(mf_git_detectar_deploy_branch)
  if [ -z "$MF_GIT_DEPLOY_BRANCH" ]; then
    echo "ERRO: Nenhuma branch remota conhecida em origin."
    return 1
  fi

  echo " >> Git: sincronizando branch ${MF_GIT_DEPLOY_BRANCH}..."
  git reset --hard "origin/${MF_GIT_DEPLOY_BRANCH}" || return 1
  git checkout -B "${MF_GIT_DEPLOY_BRANCH}" "origin/${MF_GIT_DEPLOY_BRANCH}" 2>/dev/null || true
  mf_git_clean_preservando_locais
  git reset --hard "origin/${MF_GIT_DEPLOY_BRANCH}" || return 1
  echo " >> Git: branch ${MF_GIT_DEPLOY_BRANCH} sincronizada."
  return 0
}
