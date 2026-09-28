#!/bin/bash
# Sincroniza o repositório da instância com o remote origin já configurado
# (fetch + reset --hard). Não hardcoda um único repo (ultrawhats, multiflow-pro, etc.).
#
# Uso (sempre via source — NÃO executar como binário):
#   . /root/instalador_single_oficial/tools/git_sincronizar_repositorio.sh
#   mf_git_sincronizar_repositorio ""                    # Mais Recente (origin)
#   mf_git_sincronizar_repositorio "abc123" "atualizacao"  # commit fixo
#
# Opcional (como root, antes do sudo su - deploy):
#   mf_git_aplicar_token_remote "/home/deploy/EMPRESA" "$github_token"
#   mf_git_aplicar_token_remote "/home/deploy/EMPRESA" "$github_token" "https://github.com/org/repo.git"
#
# Recuperação de token inválido (como root, com TTY):
#   mf_git_sincronizar_com_recuperacao_token "" "atualizacao" "/home/deploy/EMPRESA" "$ARQUIVO_VARIAVEIS_USADO"
#   → se o fetch falhar por auth, pede novo PAT, grava na instância, aplica no origin e retenta.
#   → como deploy não lê /root, a lib é copiada para /tmp antes do source.

# Código de saída dedicado: falha de autenticação Git (token inválido / sem acesso).
MF_GIT_EXIT_AUTH="${MF_GIT_EXIT_AUTH:-42}"

# Caminho deste arquivo (para re-source as deploy).
_MF_GIT_SYNC_SH="${BASH_SOURCE[0]:-}"

# Garante +x em tools/*.sh (e leitura) para não falhar com Permission denied / 127.
# deploy não executa estes arquivos como binário — usamos source — mas +x evita
# scripts legados e deixa o diretório tools consistente no servidor.
mf_garantir_tools_executaveis() {
  local tools_dir="${1:-}"
  local self_dir=""

  if [ -z "$tools_dir" ]; then
    if [ -n "${INSTALADOR_DIR:-}" ] && [ -d "${INSTALADOR_DIR}/tools" ]; then
      tools_dir="${INSTALADOR_DIR}/tools"
    elif [ -n "${_MF_GIT_SYNC_SH:-}" ] && [ -f "${_MF_GIT_SYNC_SH}" ]; then
      self_dir="$(cd "$(dirname "${_MF_GIT_SYNC_SH}")" && pwd)"
      tools_dir="$self_dir"
    elif [ -d "/root/instalador_single_oficial/tools" ]; then
      tools_dir="/root/instalador_single_oficial/tools"
    else
      return 0
    fi
  fi
  [ -d "$tools_dir" ] || return 0
  chmod a+rx "$tools_dir"/*.sh 2>/dev/null || true
}

# Copia lib para caminho legível pelo usuário deploy (/root/* costuma ser inacessível).
# Retorna o caminho a usar no source (stdout). Caller deve rm se for /tmp.
mf_git_sync_sh_legivel_deploy() {
  local src="${1:-}"
  local tmp=""

  [ -n "$src" ] && [ -f "$src" ] || return 1

  # Já legível por deploy? Reutiliza.
  if sudo -u deploy test -r "$src" 2>/dev/null; then
    printf '%s\n' "$src"
    return 0
  fi

  tmp=$(mktemp /tmp/mf_git_sync_XXXXXX.sh) || return 1
  cp -f "$src" "$tmp" || {
    rm -f "$tmp"
    return 1
  }
  chmod 644 "$tmp" 2>/dev/null || true
  printf '%s\n' "$tmp"
}

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

# Remove credenciais embutidas de uma URL git (https://TOKEN@host/... → https://host/...).
mf_git_url_publica() {
  local url="${1:-}"
  [ -z "$url" ] && return 1
  printf '%s\n' "$url" | sed -E 's#^(https?://)[^/@]+@#\1#'
}

# Retorna a URL pública do remote origin da pasta ($1 = app_root).
mf_git_origin_publico() {
  local app_root="${1:-}"
  local current
  [ -z "$app_root" ] || [ ! -d "${app_root}/.git" ] && return 1
  current=$(git -c "safe.directory=${app_root}" -C "${app_root}" remote get-url origin 2>/dev/null) || return 1
  mf_git_url_publica "$current"
}

# True se a URL for HTTPS github.com (qualquer owner/repo).
mf_git_url_https_github() {
  local url="${1:-}"
  echo "$url" | grep -Eqi '^https://([^/@]+@)?github\.com/'
}

# Grava github_token no remote origin (HTTPS) para fetch sem prompt interativo.
# Por padrão preserva o host/path já configurado no origin (não troca de repositório).
# $1 = raiz do app (/home/deploy/empresa). $2 = token.
# $3 opcional = URL canônica sem token (https://github.com/org/repo.git) para set-url antes do token.
mf_git_aplicar_token_remote() {
  local app_root="${1:-}"
  local token="${2:-}"
  local repo_canonico="${3:-}"
  [ -z "$app_root" ] || [ -z "$token" ] && return 1
  [ ! -d "${app_root}/.git" ] && return 1

  local current path_repo tok_enc new_url
  if [ -n "$repo_canonico" ]; then
    path_repo=$(mf_git_url_publica "$repo_canonico" | sed 's|^https://||' | sed 's|^http://||')
    [[ "$path_repo" != *.git ]] && path_repo="${path_repo}.git"
  else
    current=$(git -c "safe.directory=${app_root}" -C "${app_root}" remote get-url origin 2>/dev/null) || return 1
    case "$current" in
      https://*) ;;
      *) return 0 ;;
    esac
    path_repo=$(printf '%s' "$current" | sed 's|https://[^@]*@||' | sed 's|^https://||')
    [[ "$path_repo" != *.git ]] && path_repo="${path_repo}.git"
  fi

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

# True se a mensagem de erro do git indicar falha de autenticação/credencial.
mf_git_eh_erro_auth() {
  local msg="${1:-}"
  [ -z "$msg" ] && return 1
  echo "$msg" | grep -Eiq \
    'Authentication failed|Invalid username or token|invalid[[:space:]]+(username|token)|could not read Username|Permission denied \(publickey\)|ERROR:.*(401|403)|fatal:.*(Authentication|credential)|remote:.*(Invalid|Unauthorized|Permission)|Repository not found'
}

# Marca falha de auth para o caller (root) detectar mesmo se o exit code for mascarado.
mf_git_marcar_auth_falhou() {
  if [ -n "${MF_GIT_AUTH_MARKER:-}" ]; then
    printf 'auth\n' > "${MF_GIT_AUTH_MARKER}" 2>/dev/null || true
  fi
}

# Fetch com captura de stderr. Retorna 0 ok, MF_GIT_EXIT_AUTH (42) auth, 1 outro erro.
mf_git_fetch_detectando_auth() {
  local err_file rc=0
  err_file=$(mktemp 2>/dev/null || echo "/tmp/mf_git_fetch_err_$$")
  mf_git_desabilitar_prompt

  if git fetch --all --tags --prune 2>"$err_file"; then
    rm -f "$err_file" 2>/dev/null || true
    return 0
  fi

  echo " >> Aviso: fetch --all falhou; tentando git fetch origin..."
  if git fetch origin 2>>"$err_file"; then
    rm -f "$err_file" 2>/dev/null || true
    return 0
  fi

  # Exibe o erro do git para o operador
  if [ -s "$err_file" ]; then
    cat "$err_file" >&2 || true
  fi

  if mf_git_eh_erro_auth "$(cat "$err_file" 2>/dev/null)"; then
    echo "ERRO: autenticação Git falhou (token inválido ou sem acesso ao remote origin)."
    echo "ERRO: Verifique github_token no arquivo da instância e o remote: git remote -v"
    mf_git_marcar_auth_falhou
    rm -f "$err_file" 2>/dev/null || true
    return "${MF_GIT_EXIT_AUTH}"
  fi

  echo "ERRO: git fetch falhou (rede ou credencial/token inválido no remote origin)."
  echo "ERRO: Verifique github_token no arquivo da instância e o remote: git remote -v"
  # Heurística: stderr menciona token/auth/credential → trata como auth recuperável
  if grep -Eiq 'token|auth|credential|password|username' "$err_file" 2>/dev/null; then
    mf_git_marcar_auth_falhou
    rm -f "$err_file" 2>/dev/null || true
    return "${MF_GIT_EXIT_AUTH}"
  fi

  rm -f "$err_file" 2>/dev/null || true
  return 1
}

# Valida PAT contra um repo HTTPS (ls-remote; fallback clone raso).
# $1 = token; $2 = URL ou host/path (ex.: https://github.com/org/repo.git).
mf_git_validar_token_ls_remote() {
  local token="${1:-}"
  local repo_ref="${2:-}"
  local token_encoded url err_file test_dir repo_host

  [ -z "$token" ] || [ -z "$repo_ref" ] && return 1
  repo_host=$(echo "$repo_ref" | sed 's|^https://||' | sed 's|^http://||' | sed 's|^[^@]*@||')
  [[ "$repo_host" != *.git ]] && repo_host="${repo_host}.git"
  token_encoded=$(mf_git_urlencode "$token")
  url="https://${token_encoded}@${repo_host}"

  mf_git_desabilitar_prompt
  err_file=$(mktemp 2>/dev/null || echo "/tmp/mf_git_val_err_$$")

  if git ls-remote --exit-code "${url}" HEAD >/dev/null 2>"$err_file"; then
    rm -f "$err_file" 2>/dev/null || true
    return 0
  fi

  test_dir="/tmp/mf_git_test_clone_$$"
  if git clone --depth 1 "${url}" "${test_dir}" >/dev/null 2>>"$err_file"; then
    rm -rf "${test_dir}" >/dev/null 2>&1
    rm -f "$err_file" 2>/dev/null || true
    return 0
  fi
  rm -rf "${test_dir}" >/dev/null 2>&1
  MF_GIT_ERRO_VALIDACAO=$(head -3 "$err_file" 2>/dev/null | tr '\n' ' ')
  rm -f "$err_file" 2>/dev/null || true
  return 1
}

# Grava github_token (e opcionalmente repo_url) no arquivo de variáveis da instância.
# $1 = arquivo; $2 = token; $3 = repo_url opcional.
mf_git_gravar_token_instancia() {
  local arquivo="${1:-}"
  local token="${2:-}"
  local repo="${3:-}"
  local token_sed repo_sed

  [ -z "$arquivo" ] || [ -z "$token" ] && return 1
  [ ! -f "$arquivo" ] && return 1

  cp "$arquivo" "${arquivo}.backup.$(date +%Y%m%d_%H%M%S)" 2>/dev/null || true

  token_sed="${token//&/\\&}"
  if grep -q "^github_token=" "$arquivo"; then
    sed -i "s|^github_token=.*|github_token=${token_sed}|" "$arquivo"
  else
    echo "github_token=${token}" >> "$arquivo"
  fi

  if [ -n "$repo" ]; then
    repo_sed="${repo//&/\\&}"
    if grep -q "^repo_url=" "$arquivo"; then
      sed -i "s|^repo_url=.*|repo_url=${repo_sed}|" "$arquivo"
    else
      echo "repo_url=${repo}" >> "$arquivo"
    fi
  fi
  return 0
}

# Lê uma linha do terminal do operador (não do heredoc).
mf_git_read_tty() {
  local prompt="${1:-}"
  local _line=""
  if [ -r /dev/tty ]; then
    printf '%s' "$prompt" > /dev/tty 2>/dev/null || printf '%s' "$prompt"
    IFS= read -r _line < /dev/tty || return 1
  else
    printf '%s' "$prompt"
    IFS= read -r _line || return 1
  fi
  printf '%s\n' "$_line"
}

# Prompt interativo: novo PAT → validar → gravar instância → aplicar no origin.
# $1 = app_root; $2 = arquivo de variáveis da instância.
# Retorna 0 se token ok e aplicado; 1 se usuário cancelar ou token continuar inválido.
mf_git_recuperar_token_interativo() {
  local app_root="${1:-}"
  local arquivo_vars="${2:-}"
  local origin_publico="" repo_alvo="" novo_token="" resposta=""

  [ -z "$app_root" ] || [ ! -d "${app_root}/.git" ] && {
    echo "ERRO: app_root git inválido para recuperar token: ${app_root:-}"
    return 1
  }
  [ -z "$arquivo_vars" ] || [ ! -f "$arquivo_vars" ] && {
    echo "ERRO: arquivo de variáveis da instância não encontrado: ${arquivo_vars:-}"
    return 1
  }

  # Recarrega vars atuais (repo_url etc.)
  # shellcheck source=/dev/null
  . "$arquivo_vars" 2>/dev/null || true

  origin_publico=$(mf_git_origin_publico "$app_root" 2>/dev/null || true)
  # Fonte da verdade: repo_url das variáveis; origin só se repo_url estiver vazio.
  if [ -n "${repo_url:-}" ] && mf_git_url_https_github "$repo_url"; then
    repo_alvo=$(mf_git_url_publica "$repo_url")
  else
    repo_alvo="${origin_publico:-}"
  fi
  if [ -z "$repo_alvo" ]; then
    echo "ERRO: nem origin nem repo_url definidos — não é possível validar o token."
    return 1
  fi
  [[ "$repo_alvo" != *.git ]] && [[ "$repo_alvo" =~ github\.com ]] && repo_alvo="${repo_alvo}.git"

  if [ -n "$origin_publico" ] && [ -n "${repo_url:-}" ]; then
    _o=$(mf_git_url_publica "$origin_publico" | tr '[:upper:]' '[:lower:]' | sed 's|\.git$||')
    _r=$(mf_git_url_publica "$repo_url" | tr '[:upper:]' '[:lower:]' | sed 's|\.git$||')
    if [ -n "$_o" ] && [ -n "$_r" ] && [ "$_o" != "$_r" ]; then
      echo " >> Aviso: origin (${origin_publico}) difere de repo_url. Validando/aplicando contra repo_url: ${repo_alvo}"
    fi
  fi

  echo
  echo "=============================================================="
  echo " Token inválido / autenticação Git falhou."
  echo " Repositório: ${repo_alvo}"
  echo "=============================================================="
  echo

  while true; do
    echo "Token inválido. Cole um novo GitHub PAT:"
    echo "(Enter vazio ou 'c' cancela a atualização)"
    novo_token=$(mf_git_read_tty "> " | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | tr -d '\r\n')
    if [ -z "$novo_token" ] || [ "$novo_token" = "c" ] || [ "$novo_token" = "C" ]; then
      echo " >> Operação cancelada pelo usuário (token não informado)."
      return 1
    fi

    echo " >> Validando token (git ls-remote)..."
    MF_GIT_ERRO_VALIDACAO=""
    if ! mf_git_validar_token_ls_remote "$novo_token" "$repo_alvo"; then
      echo " >> Token ainda inválido ou sem acesso a ${repo_alvo}."
      [ -n "${MF_GIT_ERRO_VALIDACAO:-}" ] && echo " >> Detalhe: ${MF_GIT_ERRO_VALIDACAO}"
      resposta=$(mf_git_read_tty "Tentar outro token? (s/N): " | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | tr '[:upper:]' '[:lower:]' | tr -d '\r')
      if [ "$resposta" = "s" ] || [ "$resposta" = "sim" ]; then
        continue
      fi
      echo " >> Operação cancelada (token continua inválido)."
      return 1
    fi

    echo " >> Token validado. Gravando na instância e alinhando origin ao repo_url..."
    if ! mf_git_gravar_token_instancia "$arquivo_vars" "$novo_token" "$repo_alvo"; then
      echo "ERRO: não foi possível gravar github_token em ${arquivo_vars}"
      return 1
    fi

    # Alinha origin ao repo_url (fonte da verdade nas variáveis).
    if ! mf_git_aplicar_token_remote "$app_root" "$novo_token" "$repo_alvo"; then
      if ! mf_git_aplicar_token_remote "$app_root" "$novo_token"; then
        echo "ERRO: não foi possível aplicar o token no remote origin."
        return 1
      fi
    fi

    # Confirma ls-remote no origin local (mesmo caminho do update)
    mf_git_desabilitar_prompt
    if ! git -c "safe.directory=${app_root}" -C "${app_root}" ls-remote --exit-code origin HEAD >/dev/null 2>&1; then
      echo " >> Aviso: ls-remote origin ainda falhou após aplicar o token."
      resposta=$(mf_git_read_tty "Informar outro token? (s/N): " | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | tr '[:upper:]' '[:lower:]' | tr -d '\r')
      if [ "$resposta" = "s" ] || [ "$resposta" = "sim" ]; then
        continue
      fi
      return 1
    fi

    github_token="$novo_token"
    repo_url="$repo_alvo"
    export github_token repo_url
    echo " >> github_token salvo e remoto origin atualizado. Retentando sync..."
    echo
    return 0
  done
}

# $1 = commit (vazio = Mais Recente). $2 = prefixo opcional da branch temporária (commit fixo).
# Define MF_GIT_DEPLOY_BRANCH quando sincroniza com origin.
# Retorna MF_GIT_EXIT_AUTH (42) se o fetch falhar por autenticação.
mf_git_sincronizar_repositorio() {
  local commit_alvo="${1:-}"
  local branch_prefix="${2:-atualizacao}"
  local origin_publico=""
  local fetch_rc=0

  mf_git_desabilitar_prompt

  origin_publico=$(git remote get-url origin 2>/dev/null | sed -E 's#^(https?://)[^/@]+@#\1#' || true)
  if [ -n "$origin_publico" ]; then
    echo " >> Git: remote origin = ${origin_publico}"
  else
    echo "ERRO: remote origin não configurado nesta pasta. Configure com: git remote -v"
    return 1
  fi

  echo " >> Git: liberando escrita em .git (pode demorar em repos grandes)..."
  chmod -R u+w .git 2>/dev/null || true

  echo " >> Git: fetch do origin (sem prompt interativo)..."
  mf_git_fetch_detectando_auth
  fetch_rc=$?
  if [ "$fetch_rc" -ne 0 ]; then
    return "$fetch_rc"
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
    echo "ERRO: Nenhuma branch remota conhecida em origin (esperado: MULTI100-OFICIAL-u21, main ou master)."
    return 1
  fi

  echo " >> Git: sincronizando branch ${MF_GIT_DEPLOY_BRANCH} (reset --hard origin/${MF_GIT_DEPLOY_BRANCH})..."
  git reset --hard "origin/${MF_GIT_DEPLOY_BRANCH}" || return 1
  git checkout -B "${MF_GIT_DEPLOY_BRANCH}" "origin/${MF_GIT_DEPLOY_BRANCH}" 2>/dev/null || true
  mf_git_clean_preservando_locais
  git reset --hard "origin/${MF_GIT_DEPLOY_BRANCH}" || return 1
  echo " >> Git: branch ${MF_GIT_DEPLOY_BRANCH} sincronizada."
  return 0
}

# Como root: aplica token atual, sincroniza como deploy; se auth falhar, pede novo PAT e retenta.
# $1 = commit (vazio = Mais Recente); $2 = prefixo branch; $3 = app_root; $4 = arquivo variáveis.
# Até sucesso ou cancelamento do usuário.
mf_git_sincronizar_com_recuperacao_token() {
  local commit_alvo="${1:-}"
  local branch_prefix="${2:-atualizacao}"
  local app_root="${3:-}"
  local arquivo_vars="${4:-}"
  local marker="" sync_sh="" rc=0 repo_canonico="" sync_for_deploy="" sync_tmp=""

  [ -z "$app_root" ] || [ ! -d "${app_root}/.git" ] && {
    echo "ERRO: app_root inválido: ${app_root:-}"
    return 1
  }
  [ -z "$arquivo_vars" ] || [ ! -f "$arquivo_vars" ] && {
    echo "ERRO: arquivo de variáveis não encontrado: ${arquivo_vars:-}"
    return 1
  }

  sync_sh="${_MF_GIT_SYNC_SH}"
  if [ -z "$sync_sh" ] || [ ! -f "$sync_sh" ]; then
    if [ -f "${INSTALADOR_DIR:-}/tools/git_sincronizar_repositorio.sh" ]; then
      sync_sh="${INSTALADOR_DIR}/tools/git_sincronizar_repositorio.sh"
    elif [ -f "/root/instalador_single_oficial/tools/git_sincronizar_repositorio.sh" ]; then
      sync_sh="/root/instalador_single_oficial/tools/git_sincronizar_repositorio.sh"
    else
      echo "ERRO: git_sincronizar_repositorio.sh não encontrado para sincronizar como deploy."
      return 1
    fi
  fi

  mf_garantir_tools_executaveis "$(cd "$(dirname "$sync_sh")" && pwd)"
  chmod a+rx "$sync_sh" 2>/dev/null || true

  # deploy não lê /root — source do path original → Permission denied → 127.
  # Sempre preferir cópia legível em /tmp quando necessário.
  sync_for_deploy=$(mf_git_sync_sh_legivel_deploy "$sync_sh") || {
    echo "ERRO: não foi possível preparar git_sincronizar_repositorio.sh legível para deploy."
    return 1
  }
  case "$sync_for_deploy" in
    /tmp/mf_git_sync_*) sync_tmp="$sync_for_deploy" ;;
  esac

  marker="/tmp/mf_git_auth_failed_$$"
  rm -f "$marker" 2>/dev/null || true

  while true; do
    rm -f "$marker" 2>/dev/null || true
    # shellcheck source=/dev/null
    . "$arquivo_vars" 2>/dev/null || true

    # Update: repo_url das variáveis da instância é a fonte da verdade.
    # Não usar o origin atual se ele divergir (ex.: origin foi sobrescrito para
    # multiflow-pro por engano enquanto repo_url=ultrawhats).
    origin_antes=$(mf_git_origin_publico "$app_root" 2>/dev/null || true)
    repo_canonico="${repo_url:-}"
    if [ -n "$repo_canonico" ] && mf_git_url_https_github "$repo_canonico"; then
      [[ "$repo_canonico" != *.git ]] && repo_canonico="${repo_canonico}.git"
      if [ -n "$origin_antes" ]; then
        origin_norm=$(mf_git_url_publica "$origin_antes" | tr '[:upper:]' '[:lower:]' | sed 's|\.git$||')
        repo_norm=$(mf_git_url_publica "$repo_canonico" | tr '[:upper:]' '[:lower:]' | sed 's|\.git$||')
        if [ -n "$origin_norm" ] && [ "$origin_norm" != "$repo_norm" ]; then
          echo " >> Aviso: origin (${origin_antes}) difere de repo_url (${repo_canonico})."
          echo " >> Corrigindo remote origin para o repo_url da instância."
        fi
      fi
      echo " >> Repositório da instância (repo_url): ${repo_canonico}"
      if [ -n "${github_token:-}" ]; then
        echo " >> Aplicando github_token e alinhando origin ao repo_url..."
        mf_git_aplicar_token_remote "$app_root" "$github_token" "$repo_canonico" \
          || mf_git_aplicar_token_remote "$app_root" "$github_token" || true
      else
        # Sem token: ainda assim alinha o path do origin ao repo_url (HTTPS sem credencial).
        git -c "safe.directory=${app_root}" -C "${app_root}" remote set-url origin "$repo_canonico" 2>/dev/null || true
      fi
    elif [ -n "${github_token:-}" ]; then
      echo " >> Aplicando github_token no remote origin (repo_url ausente; preserva path atual)..."
      mf_git_aplicar_token_remote "$app_root" "$github_token" || true
    fi

    # Sync como deploy (ownership correto). Propaga exit code (incl. 42).
    # Sempre `source` (nunca executar o .sh como binário) para definir mf_git_*.
    set +e
    sudo -u deploy env \
      MF_GIT_AUTH_MARKER="$marker" \
      MF_GIT_EXIT_AUTH="${MF_GIT_EXIT_AUTH}" \
      GIT_TERMINAL_PROMPT=0 \
      GIT_ASKPASS=true \
      bash -c "
        set +e
        cd $(printf '%q' "$app_root") || exit 1
        # shellcheck source=/dev/null
        . $(printf '%q' "$sync_for_deploy") || {
          echo \"ERRO: falha ao source $(printf '%q' "$sync_for_deploy") (permissão/leitura).\"
          exit 1
        }
        if ! type mf_git_sincronizar_repositorio >/dev/null 2>&1; then
          echo 'ERRO: mf_git_sincronizar_repositorio não definida após source.'
          exit 1
        fi
        mf_git_sincronizar_repositorio $(printf '%q' "$commit_alvo") $(printf '%q' "$branch_prefix")
        exit \$?
      "
    rc=$?
    set -e

    if [ "$rc" -eq 0 ]; then
      rm -f "$marker" "$sync_tmp" 2>/dev/null || true
      return 0
    fi

    if [ -f "$marker" ] || [ "$rc" -eq "${MF_GIT_EXIT_AUTH}" ]; then
      echo " >> Falha de autenticação no git fetch — solicitando novo token..."
      if ! mf_git_recuperar_token_interativo "$app_root" "$arquivo_vars"; then
        rm -f "$marker" "$sync_tmp" 2>/dev/null || true
        return 1
      fi
      # shellcheck source=/dev/null
      . "$arquivo_vars" 2>/dev/null || true
      continue
    fi

    echo "ERRO: sincronização git falhou (código ${rc}) — não é falha de token recuperável."
    rm -f "$marker" "$sync_tmp" 2>/dev/null || true
    return "$rc"
  done
}
