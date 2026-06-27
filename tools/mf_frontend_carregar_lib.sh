#!/usr/bin/env bash
# Carrega mf_tela_atualizacao_frontend.sh como root (deploy nao le /root/).

mf_frontend_carregar_lib() {
  local lib _dir

  if declare -F mf_frontend_garantir_porta_env >/dev/null 2>&1; then
    return 0
  fi

  _dir="${INSTALADOR_DIR:-}"
  for lib in \
    "${_dir}/tools/mf_tela_atualizacao_frontend.sh" \
    "/root/instalador_single_oficial/tools/mf_tela_atualizacao_frontend.sh" \
    "$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)/mf_tela_atualizacao_frontend.sh" \
    "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." 2>/dev/null && pwd)/tools/mf_tela_atualizacao_frontend.sh"; do
    [ -n "$lib" ] || continue
    [ -f "$lib" ] || continue
    # shellcheck source=/dev/null
    source <(sed '1s/^\xEF\xBB\xBF//' "$lib")
    if declare -F mf_frontend_garantir_porta_env >/dev/null 2>&1; then
      return 0
    fi
  done

  printf '%s\n' "ERRO: mf_tela_atualizacao_frontend.sh nao encontrado." >&2
  return 1
}
