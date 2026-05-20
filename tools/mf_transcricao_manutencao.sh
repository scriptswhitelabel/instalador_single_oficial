#!/bin/bash
# Manutenção da API de transcrição após git pull/clean (FAST e atualização completa).
# run_transcricao.sh é gerado localmente e é removido por "git clean -fd".

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

# Chamada após git reset/pull/clean (como root).
mf_transcricao_pos_atualizacao_git() {
  local empresa="$1"
  local porta="${2:-4002}"
  local transc_dir="/home/deploy/${empresa}/api_transcricao"
  local main_py="${transc_dir}/main.py"

  [ -f "$main_py" ] || return 0

  mf_transcricao_aplicar_porta_main_py "$main_py" "$porta"
  mf_transcricao_garantir_run_wrapper "$empresa" || return 1

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
. /root/instalador_single_oficial/tools/mf_transcricao_manutencao.sh
mf_transcricao_pip_deps_leve "${transc_dir}"
mf_transcricao_pm2_garantir "${empresa}"
DEPLOYTRANSC
}
