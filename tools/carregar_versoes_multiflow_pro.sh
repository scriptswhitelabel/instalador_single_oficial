#!/bin/bash
# Carrega versão|commit de tools/versoes_multiflow_pro.conf para um array associativo global.
# Uso: source este arquivo; mf_carregar_versoes_no_array VERSOES_INSTALACAO
#      ou mf_carregar_versoes_no_array VERSOES

# Aviso exibido na opção [0] Mais Recente (instalação, FAST, atualização completa).
MF_AVISO_OPCAO_MAIS_RECENTE="( Versão DEMO para Homologação )"

mf_arquivo_versoes_multiflow_pro() {
  if [ -n "${INSTALADOR_DIR:-}" ] && [ -f "${INSTALADOR_DIR}/tools/versoes_multiflow_pro.conf" ]; then
    printf '%s\n' "${INSTALADOR_DIR}/tools/versoes_multiflow_pro.conf"
    return 0
  fi
  printf '%s\n' "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/versoes_multiflow_pro.conf"
}

# $1 = nome do array associativo (ex.: VERSOES_INSTALACAO ou VERSOES). Retorna 0 se leu pelo menos uma entrada.
mf_carregar_versoes_no_array() {
  local arr="$1"
  local conf n=0
  conf="$(mf_arquivo_versoes_multiflow_pro)"
  [ ! -f "$conf" ] && return 1
  eval "unset ${arr} 2>/dev/null; declare -gA ${arr}"
  while IFS= read -r line || [ -n "$line" ]; do
    line="${line%$'\r'}"
    [[ "$line" =~ ^[[:space:]]*# ]] && continue
    [[ -z "${line// /}" ]] && continue
    [[ "$line" != *'|'* ]] && continue
    local ver commit
    ver="${line%%|*}"
    commit="${line#*|}"
    ver="${ver%"${ver##*[![:space:]]}"}"; ver="${ver#"${ver%%[![:space:]]*}"}"
    commit="${commit%"${commit##*[![:space:]]}"}"; commit="${commit#"${commit%%[![:space:]]*}"}"
    [[ -z "$ver" || -z "$commit" ]] && continue
    eval "${arr}[\"\${ver}\"]=\"\${commit}\""
    n=$((n + 1))
  done < "$conf"
  [ "$n" -gt 0 ]
}
