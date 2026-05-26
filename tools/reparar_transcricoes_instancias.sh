#!/usr/bin/env bash
# Repara porta e PM2 da transcrição em todas as instâncias em /home/deploy/*
# Use após rollback que deixou várias transcrições na porta 4002 (Address already in use).

set -euo pipefail

INSTALADOR_DIR="${INSTALADOR_DIR:-/root/instalador_single_oficial}"
# shellcheck source=/dev/null
source "${INSTALADOR_DIR}/tools/mf_transcricao_manutencao.sh"

reparar_porta_de_env() {
  local emp="$1"
  local porta="" env_backend="/home/deploy/${emp}/backend/.env"
  local vars_file=""

  for vars_file in "/home/deploy/${emp}/VARIAVEIS_INSTALACAO" "${INSTALADOR_DIR}/VARIAVEIS_INSTALACAO"; do
    if [ -f "$vars_file" ]; then
      porta=$(grep -m1 '^porta_transcricao=' "$vars_file" 2>/dev/null | cut -d= -f2- | tr -d '\r' | tr -d ' ')
      [ -n "$porta" ] && break
    fi
  done

  if [ -z "$porta" ] && [ -f "$env_backend" ]; then
    local _url
    _url=$(grep -m1 '^TRANSCRIBE_URL=' "$env_backend" 2>/dev/null | cut -d= -f2- | tr -d '\r')
    porta=$(echo "$_url" | sed -nE 's|.*:([0-9]+).*|\1|p' | head -1)
  fi
  porta=${porta:-4002}
  printf '%s' "$porta"
}

printf " >> Reparando transcrições em /home/deploy/* ...\n\n"

ok=0
skip=0
fail=0

for deploy_dir in /home/deploy/*/; do
  [ -d "$deploy_dir" ] || continue
  emp=$(basename "$deploy_dir")
  main_py="${deploy_dir}api_transcricao/main.py"
  if [ ! -f "$main_py" ]; then
    skip=$((skip + 1))
    continue
  fi

  porta=$(reparar_porta_de_env "$emp")
  printf " >> [%s] porta %s ... " "$emp" "$porta"
  if mf_transcricao_pos_atualizacao_git "$emp" "$porta"; then
    printf "OK\n"
    ok=$((ok + 1))
  else
    printf "FALHOU\n"
    fail=$((fail + 1))
  fi
done

printf "\n >> Concluído: %s OK, %s sem api_transcricao, %s falha(s).\n" "$ok" "$skip" "$fail"
printf " >> Verifique: sudo su - deploy -c 'pm2 status | grep transcricao'\n"
