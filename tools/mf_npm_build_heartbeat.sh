#!/bin/bash
# Executa um comando longo (ex.: npm run build) e imprime heartbeat a cada 60s.
# Uso: mf_npm_build_com_heartbeat "frontend 2048MB" env NODE_OPTIONS=... npm run build

mf_npm_build_com_heartbeat() {
  local label="${1:-build}"
  shift

  if [ "$#" -eq 0 ]; then
    echo "ERRO: mf_npm_build_com_heartbeat exige um comando."
    return 2
  fi

  local pid hb_pid mins=0

  "$@" &
  pid=$!

  (
    while kill -0 "$pid" 2>/dev/null; do
      sleep 60
      if kill -0 "$pid" 2>/dev/null; then
        mins=$((mins + 1))
        printf " >> [%s] compilação em andamento... %s min(s) — aguarde (sem saída até concluir)\n" "$label" "$mins"
      fi
    done
  ) &
  hb_pid=$!

  wait "$pid"
  local exit_code=$?

  kill "$hb_pid" 2>/dev/null
  wait "$hb_pid" 2>/dev/null

  return "$exit_code"
}
