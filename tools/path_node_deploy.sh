#!/usr/bin/env bash
# Uso: . /root/instalador_single_oficial/tools/path_node_deploy.sh
# Deve rodar no contexto do usuário deploy (ex.: dentro de sudo su - deploy <<EOF).
# Garante npm/npx no PATH: prefere Node 20.19.4 via n, senão a versão mais recente em /usr/local/n.

export PATH="/usr/local/bin:/usr/bin:${PATH:-}"

if [ -d /usr/local/n/versions/node/20.19.4/bin ]; then
  export PATH="/usr/local/n/versions/node/20.19.4/bin:$PATH"
elif [ -d /usr/local/n/versions/node ]; then
  _mf_n_latest=$(ls -1 /usr/local/n/versions/node 2>/dev/null | sort -V | tail -1)
  if [ -n "$_mf_n_latest" ] && [ -d "/usr/local/n/versions/node/${_mf_n_latest}/bin" ]; then
    export PATH="/usr/local/n/versions/node/${_mf_n_latest}/bin:$PATH"
  fi
  unset _mf_n_latest
fi

if ! command -v npm >/dev/null 2>&1; then
  echo "ERRO: npm não encontrado no PATH." >&2
  echo "      Como root, instale Node 20.19.4 (ex.: n 20.19.4) ou verifique /usr/local/n/versions/node/*/bin." >&2
  exit 1
fi

# Git: sincronização com origin (usado nas atualizações opção 2/8).
# Carrega tools/git_sincronizar_repositorio.sh se existir; senão usa fallback embutido.
_mf_tools_dir="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
if [ -f "${_mf_tools_dir}/git_sincronizar_repositorio.sh" ]; then
  # shellcheck source=tools/git_sincronizar_repositorio.sh
  . "${_mf_tools_dir}/git_sincronizar_repositorio.sh"
else
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
fi

if [ -f "${_mf_tools_dir}/baileys_hineken_package_json.sh" ]; then
  # shellcheck source=tools/baileys_hineken_package_json.sh
  . "${_mf_tools_dir}/baileys_hineken_package_json.sh"
fi
unset _mf_tools_dir
