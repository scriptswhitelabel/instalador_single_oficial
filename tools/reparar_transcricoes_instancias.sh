#!/usr/bin/env bash
# Repara porta e PM2 da transcrição em cada instância em /home/deploy/*
# Cada instância usa SUA porta (TRANSCRIBE_URL do backend/.env da pasta).

set -uo pipefail

INSTALADOR_DIR="${INSTALADOR_DIR:-/root/instalador_single_oficial}"
# shellcheck source=/dev/null
source "${INSTALADOR_DIR}/tools/mf_transcricao_manutencao.sh"

declare -A PORTAS_USADAS=()

printf " >> Reparando transcrições (uma porta por instância)...\n\n"

ok=0
skip=0
fail=0

for deploy_dir in /home/deploy/*/; do
  [ -d "$deploy_dir" ] || continue
  emp=$(basename "$deploy_dir")
  main_py="${deploy_dir}api_transcricao/main.py"
  env_backend="${deploy_dir}backend/.env"

  if [ ! -f "$main_py" ]; then
    skip=$((skip + 1))
    continue
  fi

  porta=$(mf_resolver_porta_transcricao_instancia "$emp" "$INSTALADOR_DIR")
  url_ref=""
  if [ -f "$env_backend" ]; then
    url_ref=$(grep -m1 '^TRANSCRIBE_URL=' "$env_backend" 2>/dev/null | cut -d= -f2- | tr -d '\r' || true)
  fi

  if [ -n "${PORTAS_USADAS[$porta]:-}" ] && [ "${PORTAS_USADAS[$porta]}" != "$emp" ]; then
    printf "${RED} >> [%s] ERRO: porta %s já usada por %s (conflito). Ajuste TRANSCRIBE_URL em %s${WHITE}\n" \
      "$emp" "$porta" "${PORTAS_USADAS[$porta]}" "$env_backend"
    fail=$((fail + 1))
    continue
  fi
  PORTAS_USADAS[$porta]="$emp"

  printf " >> [%s] porta ${BLUE}%s${WHITE}" "$emp" "$porta"
  [ -n "$url_ref" ] && printf " (TRANSCRIBE_URL=%s)" "$url_ref"
  printf " ... "

  if mf_transcricao_pos_atualizacao_git "$emp" "$porta"; then
    printf "${GREEN}OK${WHITE}\n"
    ok=$((ok + 1))
  else
    printf "${RED}FALHOU${WHITE}\n"
    fail=$((fail + 1))
  fi
done

printf "\n >> Concluído: %s OK, %s sem api_transcricao, %s falha(s).\n" "$ok" "$skip" "$fail"
printf " >> Verifique: sudo su - deploy -c 'pm2 status | grep transcricao'\n"
