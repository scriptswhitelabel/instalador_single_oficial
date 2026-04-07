#!/usr/bin/env bash
# Uso: . /root/instalador_single_oficial/tools/path_node_deploy.sh
# Deve rodar no contexto do usuário deploy (ex.: dentro de sudo su - deploy <<EOF).
# Garante npm/npx no PATH: prefere Node 20.19.4 via n, senão a versão mais recente em /usr/local/n.

export PATH="/usr/local/bin:/usr/bin:${PATH:-}"

if [ -d /usr/local/n/versions/node/20.19.4/bin ]; then
  export PATH="/usr/local/n/versions/node/20.19.4/bin:$PATH"
elif [ -d /usr/local/n/versions/node ]; then
  _mf_n_latest=$(ls -1 /usr/local/n/versions/node 2>/dev/null | sort -V | tail -1)
  if [ -n "$_mf_n_latest" ] && [ -d "/usr/local/n/versions/node/${_mf_n_latest}/bin" ]; then
    export PATH="/usr/local/n/versions/node/${_mf_n_latest}/bin:$PATH"
  fi
  unset _mf_n_latest
fi

if ! command -v npm >/dev/null 2>&1; then
  echo "ERRO: npm não encontrado no PATH." >&2
  echo "      Como root, instale Node 20.19.4 (ex.: n 20.19.4) ou verifique /usr/local/n/versions/node/*/bin." >&2
  exit 1
fi
