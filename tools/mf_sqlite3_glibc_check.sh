#!/usr/bin/env bash
# Detecta sqlite3 nativo incompatível com a GLIBC do host (ERR_DLOPEN_FAILED)
# e recompila no servidor de destino — evita Baileys travado em OPENING/conectando.
#
# Uso (no diretório do backend, após npm install):
#   . tools/mf_sqlite3_glibc_check.sh
#   mf_garantir_sqlite3_compativel_glibc [dir_backend]
#
# Em heredocs "su - deploy": path_node_deploy.sh carrega este script automaticamente.
# Genérico: qualquer instância (/home/deploy/<empresa>/backend) — ultrawhats, multiflow, oplano, etc.

mf_garantir_sqlite3_compativel_glibc() {
  local backend_dir="${1:-.}"
  local cwd_prev err_out rebuild_out

  if [ ! -d "$backend_dir" ]; then
    echo " >> sqlite3/GLIBC: pasta backend não encontrada (${backend_dir}) — pulando."
    return 0
  fi

  cwd_prev=$(pwd)
  cd "$backend_dir" || {
    echo " >> sqlite3/GLIBC: não foi possível entrar em ${backend_dir} — pulando."
    return 0
  }

  # Sem dependência sqlite3: nada a fazer (não quebra updates sem Baileys/sqlite).
  if [ ! -d "node_modules/sqlite3" ]; then
    if [ -f package.json ] && grep -qE '"sqlite3"[[:space:]]*:' package.json 2>/dev/null; then
      echo " >> sqlite3/GLIBC: listado no package.json mas node_modules/sqlite3 ausente — pulando."
    else
      echo " >> sqlite3/GLIBC: sqlite3 não instalado neste backend — pulando."
    fi
    cd "$cwd_prev" 2>/dev/null || true
    return 0
  fi

  if ! command -v node >/dev/null 2>&1; then
    echo " >> sqlite3/GLIBC: node não encontrado no PATH — pulando."
    cd "$cwd_prev" 2>/dev/null || true
    return 0
  fi

  echo " >> sqlite3/GLIBC: verificando require('sqlite3') no host..."
  if err_out=$(node -e "require('sqlite3')" 2>&1); then
    echo " >> sqlite3/GLIBC: OK — binário compatível com o sistema (sem rebuild)."
    cd "$cwd_prev" 2>/dev/null || true
    return 0
  fi

  echo " >> sqlite3/GLIBC: DETECTADO — falha ao carregar sqlite3 (ERR_DLOPEN_FAILED / GLIBC incompatível)."
  echo " >> sqlite3/GLIBC: detalhe: $(printf '%s' "$err_out" | tr '\n' ' ' | head -c 280)"
  echo " >> sqlite3/GLIBC: ajustando com npm rebuild sqlite3 --build-from-source..."

  if ! rebuild_out=$(npm rebuild sqlite3 --build-from-source 2>&1); then
    echo " >> sqlite3/GLIBC: FALHOU — rebuild from source não concluiu."
    echo " >> sqlite3/GLIBC: $(printf '%s' "$rebuild_out" | tail -5 | tr '\n' ' ' | head -c 400)"
    echo " >> sqlite3/GLIBC: aviso — Baileys pode ficar em OPENING; rode manualmente no backend: npm rebuild sqlite3 --build-from-source"
    cd "$cwd_prev" 2>/dev/null || true
    return 0
  fi

  if node -e "require('sqlite3')" 2>/dev/null; then
    echo " >> sqlite3/GLIBC: rebuild OK — require('sqlite3') funcionando neste host."
  else
    err_out=$(node -e "require('sqlite3')" 2>&1 || true)
    echo " >> sqlite3/GLIBC: FALHOU — rebuild rodou mas require ainda falha."
    echo " >> sqlite3/GLIBC: detalhe: $(printf '%s' "$err_out" | tr '\n' ' ' | head -c 280)"
    echo " >> sqlite3/GLIBC: aviso — verifique build-essential/python3 e reinicie o backend após corrigir."
  fi

  cd "$cwd_prev" 2>/dev/null || true
  return 0
}
