#!/usr/bin/env bash
# Política de versões do instalador (ligar/desligar sem apagar código legado).
#
# MF_OCULTAR_MENU_ROLLBACK=1     → não mostra opção 4 (Roolback) no menu; case 4 ainda funciona
# MF_FORCAR_COMMIT_MAIS_RECENTE=1 → instala/atualiza sempre a branch remota mais recente (sem menu)

: "${MF_OCULTAR_MENU_ROLLBACK:=1}"
: "${MF_FORCAR_COMMIT_MAIS_RECENTE:=1}"

mf_politica_forcar_mais_recente() {
  [ "${MF_FORCAR_COMMIT_MAIS_RECENTE}" = "1" ]
}

mf_aplicar_versao_mais_recente_instalacao() {
  declare -g versao_instalacao="Mais_Recente"
  declare -g commit_instalacao=""
  printf "${GREEN} >> Versão: última do Git (branch remota) — menu de versões oculto.${WHITE}\n"
  echo
  return 0
}

mf_aplicar_versao_mais_recente_atualizacao() {
  declare -g versao_atualizacao="Mais_Recente"
  declare -g commit_atualizacao=""
  printf "${GREEN} >> Atualização: última do Git (branch remota) — menu de versões oculto.${WHITE}\n"
  echo
  return 0
}
