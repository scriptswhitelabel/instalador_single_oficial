#!/bin/bash
# Sincroniza o repositório da instância com origin (descarta alterações locais e
# arquivos não rastreados que impediriam checkout/merge).
#
# Uso (como usuário deploy, dentro do diretório do projeto):
#   . /root/instalador_single_oficial/tools/git_sincronizar_repositorio.sh
#   mf_git_sincronizar_repositorio ""                    # Mais Recente (origin)
#   mf_git_sincronizar_repositorio "abc123" "atualizacao"  # commit fixo

mf_git_clean_preservando_locais() {
  git clean -fd \
    -e api_transcricao/run_transcricao.sh \
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

# $1 = commit (vazio = Mais Recente). $2 = prefixo opcional da branch temporária (commit fixo).
# Define MF_GIT_DEPLOY_BRANCH quando sincroniza com origin.
mf_git_sincronizar_repositorio() {
  local commit_alvo="${1:-}"
  local branch_prefix="${2:-atualizacao}"

  chmod -R u+w .git 2>/dev/null || true
  git fetch --all --tags --prune 2>/dev/null || git fetch origin 2>/dev/null || true

  mf_git_clean_preservando_locais

  if [ -n "$commit_alvo" ]; then
    if ! git cat-file -e "${commit_alvo}^{commit}" 2>/dev/null; then
      echo "ERRO: Commit ${commit_alvo} não encontrado após fetch."
      return 1
    fi
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
    return 0
  fi

  MF_GIT_DEPLOY_BRANCH=$(mf_git_detectar_deploy_branch)
  if [ -z "$MF_GIT_DEPLOY_BRANCH" ]; then
    echo "ERRO: Nenhuma branch remota conhecida em origin."
    return 1
  fi

  git reset --hard "origin/${MF_GIT_DEPLOY_BRANCH}" || return 1
  git checkout -B "${MF_GIT_DEPLOY_BRANCH}" "origin/${MF_GIT_DEPLOY_BRANCH}" 2>/dev/null || true
  mf_git_clean_preservando_locais
  git reset --hard "origin/${MF_GIT_DEPLOY_BRANCH}" || return 1
  return 0
}
