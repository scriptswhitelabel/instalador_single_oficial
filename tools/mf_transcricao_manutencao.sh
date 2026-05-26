#!/bin/bash
# Manutenção da API de transcrição após git pull (FAST e atualização completa).
# run_transcricao.sh é gerado localmente pelo instalador; garante wrapper e PM2 após atualização.

# Extrai porta de app.run / main.py (port=NNNN ou porta NNNN).
mf_transcricao_extrair_porta_main_py() {
  local main_py="$1"
  local porta=""
  [ -f "$main_py" ] || return 1
  porta=$(grep -oE 'port[[:space:]]*=[[:space:]]*[0-9]+' "$main_py" 2>/dev/null | head -1 | grep -oE '[0-9]+' || true)
  if [ -n "$porta" ]; then
    printf '%s' "$porta"
    return 0
  fi
  porta=$(grep -oE 'porta[[:space:]]+[0-9]+' "$main_py" 2>/dev/null | head -1 | grep -oE '[0-9]+' || true)
  [ -n "$porta" ] && printf '%s' "$porta"
}

# Porta canônica da instância: TRANSCRIBE_URL no backend/.env desta pasta.
mf_transcricao_porta_de_backend_env() {
  local emp="$1"
  local env_backend="/home/deploy/${emp}/backend/.env"
  local _url porta=""
  [ -f "$env_backend" ] || return 1
  _url=$(grep -m1 '^TRANSCRIBE_URL=' "$env_backend" 2>/dev/null | cut -d= -f2- | tr -d '\r')
  porta=$(echo "$_url" | sed -nE 's|.*:([0-9]+)(/|$)|\1|p' | head -1)
  [ -n "$porta" ] && printf '%s' "$porta"
}

# Resolve porta SOMENTE para a instância $emp (nunca VARIAVEIS_INSTALACAO global compartilhada).
# Ordem: backend/.env → .mf_porta_transcricao → VARIAVEIS_INSTALACAO_INSTANCIA_* → deploy/VARIAVEIS → main.py → 4002
mf_resolver_porta_transcricao_instancia() {
  local emp="$1"
  local instalador_dir="${2:-/root/instalador_single_oficial}"
  local porta="" main_py="/home/deploy/${emp}/api_transcricao/main.py"
  local saved="/home/deploy/${emp}/api_transcricao/.mf_porta_transcricao"
  local f _e _p _saved

  porta=$(mf_transcricao_porta_de_backend_env "$emp" 2>/dev/null || true)

  if [ -f "$saved" ]; then
    _saved=$(tr -d '\r\n ' <"$saved" 2>/dev/null || true)
    if [[ "$_saved" =~ ^[0-9]+$ ]]; then
      if [ -z "$porta" ]; then
        porta="$_saved"
      elif [ "$porta" = "4002" ] && [ "$_saved" != "4002" ]; then
        porta="$_saved"
      fi
    fi
  fi

  shopt -s nullglob
  for f in "${instalador_dir}/VARIAVEIS_INSTALACAO_INSTANCIA_"*; do
    [ -f "$f" ] || continue
    _e=$(grep -m1 '^empresa=' "$f" 2>/dev/null | cut -d= -f2- | tr -d '\r" ')
    if [ "$_e" = "$emp" ]; then
      _p=$(grep -m1 '^porta_transcricao=' "$f" 2>/dev/null | cut -d= -f2- | tr -d '\r" ')
      [ -n "$_p" ] && porta="$_p"
      break
    fi
  done
  shopt -u nullglob

  if [ -f "/home/deploy/${emp}/VARIAVEIS_INSTALACAO" ]; then
    _p=$(grep -m1 '^porta_transcricao=' "/home/deploy/${emp}/VARIAVEIS_INSTALACAO" 2>/dev/null | cut -d= -f2- | tr -d '\r" ')
    [ -n "$_p" ] && porta="$_p"
  fi

  if [ -z "$porta" ] && [ -f "$main_py" ]; then
    porta=$(mf_transcricao_extrair_porta_main_py "$main_py" 2>/dev/null || true)
  fi

  porta=${porta:-4002}
  printf '%s' "$porta"
}

# Antes do git reset: grava porta real (main.py ou .env) para não perder no checkout.
mf_transcricao_salvar_porta_antes_git() {
  local emp="$1"
  local main_py="/home/deploy/${emp}/api_transcricao/main.py"
  local dest="/home/deploy/${emp}/api_transcricao/.mf_porta_transcricao"
  local porta=""

  [ -f "$main_py" ] || return 0

  porta=$(mf_transcricao_extrair_porta_main_py "$main_py" 2>/dev/null || true)
  [ -z "$porta" ] && porta=$(mf_transcricao_porta_de_backend_env "$emp" 2>/dev/null || true)
  [ -z "$porta" ] && porta=$(mf_resolver_porta_transcricao_instancia "$emp" 2>/dev/null || true)
  [ -n "$porta" ] || return 0

  printf '%s\n' "$porta" >"$dest"
  chown deploy:deploy "$dest" 2>/dev/null || true
  chmod 600 "$dest" 2>/dev/null || true
  return 0
}

mf_transcricao_aplicar_porta_main_py() {
  local main_py="$1"
  local porta="$2"
  [ -f "$main_py" ] || return 1
  sed -i -E "s|port[[:space:]]*=[[:space:]]*[0-9]+|port=${porta}|g" "$main_py" 2>/dev/null || true
  sed -i -E "s|porta[[:space:]]+[0-9]+|porta ${porta}|g" "$main_py" 2>/dev/null || true
  return 0
}

mf_transcricao_garantir_run_wrapper() {
  local empresa="$1"
  local transc_dir="/home/deploy/${empresa}/api_transcricao"
  local main_py="${transc_dir}/main.py"
  local wrapper="${transc_dir}/run_transcricao.sh"

  [ -f "$main_py" ] || return 1

  cat >"$wrapper" <<EOF
#!/bin/bash
TRANSC_DIR="${transc_dir}"
cd "\$TRANSC_DIR" || exit 1
USER_SITE=\$(python3 -m site --user-site 2>/dev/null || echo "")
if [ -n "\$USER_SITE" ] && [ -d "\$USER_SITE" ]; then
  export PYTHONPATH="\$USER_SITE:\$PYTHONPATH"
fi
exec python3 "${main_py}"
EOF
  chmod +x "$wrapper"
  chown deploy:deploy "$wrapper" 2>/dev/null || true
  return 0
}

# Python 3.13+ removeu aifc/audioop da stdlib; SpeechRecognition ainda importa aifc.
mf_transcricao_pip_python313_compat() {
  local pip_cmd="${1:-pip3}"

  command -v python3 >/dev/null 2>&1 || return 0
  python3 -c 'import sys; raise SystemExit(0 if sys.version_info >= (3, 13) else 1)' 2>/dev/null || return 0

  printf " >> Python 3.13+: instalando standard-aifc e audioop-lts (SpeechRecognition)...\n"
  $pip_cmd install --user --break-system-packages standard-aifc audioop-lts 2>/dev/null \
    || $pip_cmd install --user standard-aifc audioop-lts 2>/dev/null \
    || true
  return 0
}

# Atualiza dependências Python sem apagar venv (rápido; falhas não interrompem o fluxo).
mf_transcricao_pip_deps_leve() {
  local transc_dir="$1"
  local req="${transc_dir}/requirements.txt"
  local pip_cmd="pip3"

  command -v pip3 >/dev/null 2>&1 || pip_cmd="python3 -m pip"
  command -v python3 >/dev/null 2>&1 || return 0

  if [ -f "$req" ]; then
    $pip_cmd install --user -r "$req" 2>/dev/null \
      || $pip_cmd install --user --break-system-packages -r "$req" 2>/dev/null \
      || true
  fi
  mf_transcricao_pip_python313_compat "$pip_cmd"
  return 0
}

# Recria wrapper e registra PM2 (delete + start se já existir — evita script path quebrado).
mf_transcricao_pm2_garantir() {
  local empresa="$1"
  local transc_dir="/home/deploy/${empresa}/api_transcricao"
  local wrapper="${transc_dir}/run_transcricao.sh"
  local pm2_name="${empresa}-transcricao"

  [ -x "$wrapper" ] || return 1

  if command -v pm2 >/dev/null 2>&1 && pm2 describe "$pm2_name" >/dev/null 2>&1; then
    pm2 delete "$pm2_name" 2>/dev/null || true
  fi

  pm2 start "$wrapper" --name "$pm2_name" --interpreter bash --cwd "$transc_dir" 2>/dev/null \
    || pm2 restart "$pm2_name" 2>/dev/null \
    || true
  pm2 save 2>/dev/null || true
  return 0
}

# Copia o script para pasta da instância (deploy não lê /root).
mf_transcricao_script_para_deploy() {
  local empresa="$1"
  local dest="/home/deploy/${empresa}/.mf_transcricao_manutencao.sh"
  local src="${MF_TRANSC_MAINT_SCRIPT:-}"

  if [ -z "$src" ] || [ ! -f "$src" ]; then
    src="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/mf_transcricao_manutencao.sh"
  fi
  [ -f "$src" ] || src="/root/instalador_single_oficial/tools/mf_transcricao_manutencao.sh"
  [ -f "$src" ] || return 1

  cp -f "$src" "$dest"
  chmod 755 "$dest"
  chown deploy:deploy "$dest" 2>/dev/null || true
  echo "$dest"
}

# Chamada após git reset/pull/clean (como root).
mf_transcricao_pos_atualizacao_git() {
  local empresa="$1"
  local porta="${2:-4002}"
  local transc_dir="/home/deploy/${empresa}/api_transcricao"
  local main_py="${transc_dir}/main.py"
  local script_deploy

  [ -f "$main_py" ] || return 0

  mf_transcricao_aplicar_porta_main_py "$main_py" "$porta"
  mf_transcricao_garantir_run_wrapper "$empresa" || return 1

  script_deploy=$(mf_transcricao_script_para_deploy "$empresa") || return 1

  sudo su - deploy <<DEPLOYTRANSC
set +e
if [ -f /root/instalador_single_oficial/tools/path_node_deploy.sh ]; then
  . /root/instalador_single_oficial/tools/path_node_deploy.sh
else
  export PATH="/usr/local/bin:/usr/bin:\${PATH:-}"
  if [ -d /usr/local/n/versions/node/20.19.4/bin ]; then
    export PATH="/usr/local/n/versions/node/20.19.4/bin:\$PATH"
  fi
fi
# shellcheck source=/dev/null
. "${script_deploy}"
mf_transcricao_pip_deps_leve "${transc_dir}"
mf_transcricao_pm2_garantir "${empresa}"
DEPLOYTRANSC
}
