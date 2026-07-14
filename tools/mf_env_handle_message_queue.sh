#!/bin/bash
# Atualiza/garante variáveis de throughput das filas Bull de mensagem
# (Baileys -handleMessage e WhatsMeow -handleWuzapiMessage) no .env do backend.
# Uso: source este arquivo (requer empresa definida) e chame:
#   verificar_e_adicionar_handle_message_queue_env

verificar_e_adicionar_handle_message_queue_env() {
  if [ -z "${empresa:-}" ]; then
    printf "${RED} >> ERRO: Variável 'empresa' não está definida!\n${WHITE}"
    return 0
  fi

  local ENV_FILE="/home/deploy/${empresa}/backend/.env"
  if [ ! -f "$ENV_FILE" ]; then
    printf "${YELLOW} >> AVISO: Arquivo .env não encontrado em $ENV_FILE. Pulando filas de mensagem.\n${WHITE}"
    return 0
  fi

  printf "${WHITE} >> Verificando variáveis de fila de mensagem (Bull/Meow) no .env...\n${WHITE}"

  # Redis limiter genérico: migra default antigo (1) para 10 (conservador).
  # Throughput de WhatsApp fica em HANDLE_MESSAGE_* (abaixo).
  if grep -qE '^REDIS_OPT_LIMITER_MAX=1[[:space:]]*$' "$ENV_FILE"; then
    sed -i 's/^REDIS_OPT_LIMITER_MAX=1[[:space:]]*$/REDIS_OPT_LIMITER_MAX=10/' "$ENV_FILE"
    printf "${GREEN} >> REDIS_OPT_LIMITER_MAX atualizado de 1 para 10.${WHITE}\n"
  elif grep -qE '^REDIS_OPT_LIMITER_MAX=25[[:space:]]*$' "$ENV_FILE"; then
    # Instalações que receberam 25 logo após o patch — suaviza para 10
    sed -i 's/^REDIS_OPT_LIMITER_MAX=25[[:space:]]*$/REDIS_OPT_LIMITER_MAX=10/' "$ENV_FILE"
    printf "${GREEN} >> REDIS_OPT_LIMITER_MAX suavizado de 25 para 10.${WHITE}\n"
  elif ! grep -q '^REDIS_OPT_LIMITER_MAX=' "$ENV_FILE"; then
    echo "REDIS_OPT_LIMITER_MAX=10" >> "$ENV_FILE"
    printf "${GREEN} >> REDIS_OPT_LIMITER_MAX=10 adicionado.${WHITE}\n"
  fi

  if grep -qE '^REDIS_OPT_LIMITER_DURATION=3000[[:space:]]*$' "$ENV_FILE"; then
    sed -i 's/^REDIS_OPT_LIMITER_DURATION=3000[[:space:]]*$/REDIS_OPT_LIMITER_DURATION=1000/' "$ENV_FILE"
    printf "${GREEN} >> REDIS_OPT_LIMITER_DURATION atualizado de 3000 para 1000.${WHITE}\n"
  elif ! grep -q '^REDIS_OPT_LIMITER_DURATION=' "$ENV_FILE"; then
    echo "REDIS_OPT_LIMITER_DURATION=1000" >> "$ENV_FILE"
    printf "${GREEN} >> REDIS_OPT_LIMITER_DURATION=1000 adicionado.${WHITE}\n"
  fi

  local _hm_header=0
  if ! grep -q '^HANDLE_MESSAGE_QUEUE_CONCURRENCY=' "$ENV_FILE" || \
     ! grep -q '^HANDLE_MESSAGE_LIMITER_MAX=' "$ENV_FILE" || \
     ! grep -q '^HANDLE_MESSAGE_LIMITER_DURATION=' "$ENV_FILE"; then
    _hm_header=1
  fi

  if [ "$_hm_header" = "1" ]; then
    echo "" >> "$ENV_FILE"
    echo "# Throughput filas de mensagem Baileys (-handleMessage) e WhatsMeow (-handleWuzapiMessage)" >> "$ENV_FILE"
  fi

  if ! grep -q '^HANDLE_MESSAGE_QUEUE_CONCURRENCY=' "$ENV_FILE"; then
    echo "HANDLE_MESSAGE_QUEUE_CONCURRENCY=4" >> "$ENV_FILE"
    printf "${GREEN} >> HANDLE_MESSAGE_QUEUE_CONCURRENCY=4 adicionado.${WHITE}\n"
  fi
  if ! grep -q '^HANDLE_MESSAGE_LIMITER_MAX=' "$ENV_FILE"; then
    echo "HANDLE_MESSAGE_LIMITER_MAX=15" >> "$ENV_FILE"
    printf "${GREEN} >> HANDLE_MESSAGE_LIMITER_MAX=15 adicionado.${WHITE}\n"
  fi
  if ! grep -q '^HANDLE_MESSAGE_LIMITER_DURATION=' "$ENV_FILE"; then
    echo "HANDLE_MESSAGE_LIMITER_DURATION=1000" >> "$ENV_FILE"
    printf "${GREEN} >> HANDLE_MESSAGE_LIMITER_DURATION=1000 adicionado.${WHITE}\n"
  fi

  if type garantir_permissoes_env_backend >/dev/null 2>&1; then
    garantir_permissoes_env_backend "$ENV_FILE"
  else
    chown deploy:deploy "$ENV_FILE" 2>/dev/null || true
    chmod 660 "$ENV_FILE" 2>/dev/null || true
  fi
}
