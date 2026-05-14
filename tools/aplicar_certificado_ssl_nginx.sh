#!/bin/bash

# Aplica certificado SSL no Nginx via Certbot (modo interativo).

GREEN='\033[1;32m'
BLUE='\033[1;34m'
WHITE='\033[1;37m'
RED='\033[1;31m'
YELLOW='\033[1;33m'

if [ "$EUID" -ne 0 ]; then
  echo
  printf "${WHITE} >> Este script precisa ser executado como root.${WHITE}\n"
  exit 1
fi

banner() {
  printf " ${BLUE}\n"
  printf "  Certificado SSL no Nginx\n"
  printf " ${WHITE}\n"
}

validar_ambiente() {
  if ! command -v nginx >/dev/null 2>&1; then
    printf "${RED} >> Nginx não encontrado. Instale o Nginx antes de aplicar o certificado.${WHITE}\n"
    sleep 3
    return 1
  fi

  if ! command -v certbot >/dev/null 2>&1; then
    printf "${RED} >> Certbot não encontrado. Instale o Certbot antes de continuar.${WHITE}\n"
    sleep 3
    return 1
  fi

  if ! systemctl is-active --quiet nginx 2>/dev/null; then
    printf "${YELLOW} >> Nginx não está ativo. Tentando iniciar...${WHITE}\n"
    if ! systemctl start nginx 2>/dev/null && ! service nginx start 2>/dev/null; then
      printf "${RED} >> Não foi possível iniciar o Nginx.${WHITE}\n"
      sleep 3
      return 1
    fi
  fi

  return 0
}

main() {
  banner
  printf "${WHITE} >> Esta ferramenta executa o Certbot no modo Nginx para emitir ou renovar certificados SSL.${WHITE}\n"
  printf "${WHITE} >> Siga as perguntas do Certbot na sequência.${WHITE}\n"
  echo

  if ! validar_ambiente; then
    return 1
  fi

  printf "${GREEN} >> Executando: certbot --nginx${WHITE}\n"
  echo
  certbot --nginx
  local status=$?

  echo
  if [ "$status" -eq 0 ]; then
    printf "${GREEN} >> Certbot concluído com sucesso.${WHITE}\n"
  else
    printf "${RED} >> Certbot finalizou com erro (código ${status}).${WHITE}\n"
  fi

  sleep 2
  return "$status"
}

main "$@"
