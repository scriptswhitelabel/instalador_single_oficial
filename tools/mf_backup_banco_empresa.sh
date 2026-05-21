#!/bin/bash
# Backup do banco de uma instância em /home/deploy/backup-<empresa>/
# Uso: source "$(dirname ...)/tools/mf_backup_banco_empresa.sh"
#      mf_backup_banco_empresa "web01" && echo "$MF_BACKUP_ARQUIVO"

# Resolve container Postgres da instância (VPS com várias instâncias: nunca usa "o primeiro postgres" genérico).
mf_backup_resolver_container_postgres() {
  local empresa="$1"
  local db_user="$2"
  local db_pass="$3"
  local db_name="$4"
  local name candidatos=() n

  command -v docker >/dev/null 2>&1 || return 1
  [[ "$empresa" =~ ^[a-zA-Z0-9_]+$ ]] || return 1
  [[ "$db_name" =~ ^[a-zA-Z0-9_]+$ ]] || return 1
  [ -n "$db_pass" ] || return 1

  # Padrão do instalador / agendar_backup_bd_docker.sh
  if docker ps --format '{{.Names}}' 2>/dev/null | grep -qx "postgres_${empresa}"; then
    echo "postgres_${empresa}"
    return 0
  fi

  # Containers cujo nome inclui a empresa (ex.: postgres_empresa2, pg-empresa2)
  while IFS= read -r name; do
    [ -n "$name" ] && candidatos+=("$name")
  done < <(docker ps --format '{{.Names}}' 2>/dev/null | grep -iE "^postgres[_-]${empresa}\$|^pg[_-]?${empresa}\$" || true)

  if [ "${#candidatos[@]}" -eq 1 ]; then
    echo "${candidatos[0]}"
    return 0
  fi

  if [ "${#candidatos[@]}" -gt 1 ]; then
    printf "ERRO: Vários containers Postgres para a instância %s: %s\n" "$empresa" "${candidatos[*]}" >&2
    return 1
  fi

  # Alta Performance: postgres_otimizapp compartilhado — só se o banco desta instância existir nele
  if docker ps --format '{{.Names}}' 2>/dev/null | grep -qx "postgres_otimizapp"; then
    if docker exec postgres_otimizapp env PGPASSWORD="${db_pass}" \
      psql -h 127.0.0.1 -p 5432 -U "${db_user}" -d postgres -tAc \
      "SELECT 1 FROM pg_database WHERE datname='${db_name}'" 2>/dev/null | grep -q '^1$'; then
      echo "postgres_otimizapp"
      return 0
    fi
  fi

  # Último recurso: um único container postgres_* em execução (VPS single-tenant legado)
  local todos_pg=()
  while IFS= read -r name; do
    [ -n "$name" ] && todos_pg+=("$name")
  done < <(docker ps --format '{{.Names}}' 2>/dev/null | grep -iE '^postgres[_-]' | grep -vi pgbouncer || true)

  if [ "${#todos_pg[@]}" -eq 1 ]; then
    n="${todos_pg[0]}"
    if docker exec "$n" env PGPASSWORD="${db_pass}" \
      psql -h 127.0.0.1 -p 5432 -U "${db_user}" -d postgres -tAc \
      "SELECT 1 FROM pg_database WHERE datname='${db_name}'" 2>/dev/null | grep -q '^1$'; then
      echo "$n"
      return 0
    fi
  elif [ "${#todos_pg[@]}" -gt 1 ]; then
    printf "ERRO: VPS com várias instâncias Postgres (%s). Container esperado: postgres_%s\n" \
      "${todos_pg[*]}" "$empresa" >&2
    return 1
  fi

  return 1
}

mf_backup_banco_empresa() {
  local empresa="$1"
  local env_file="/home/deploy/${empresa}/backend/.env"
  MF_BACKUP_ARQUIVO=""
  local min_bytes=1024

  [ -n "$empresa" ] || return 1
  [ -f "$env_file" ] || return 1

  local db_user db_pass db_name db_host db_port backup_dir data
  db_user=$(grep -m1 '^DB_USER=' "$env_file" 2>/dev/null | cut -d '=' -f2- | tr -d '\r')
  db_pass=$(grep -m1 '^DB_PASS=' "$env_file" 2>/dev/null | cut -d '=' -f2- | tr -d '\r')
  db_name=$(grep -m1 '^DB_NAME=' "$env_file" 2>/dev/null | cut -d '=' -f2- | tr -d '\r')
  db_host=$(grep -m1 '^DB_HOST=' "$env_file" 2>/dev/null | cut -d '=' -f2- | tr -d '\r')
  db_port=$(grep -m1 '^DB_PORT=' "$env_file" 2>/dev/null | cut -d '=' -f2- | tr -d '\r')

  db_user="${db_user:-$empresa}"
  db_name="${db_name:-$empresa}"
  db_host="${db_host:-127.0.0.1}"
  [ "$db_host" = "localhost" ] && db_host="127.0.0.1"
  db_port="${db_port:-5432}"

  [ -n "$db_pass" ] || return 1
  [[ "$db_name" =~ ^[a-zA-Z0-9_]+$ ]] || return 1

  backup_dir="/home/deploy/backup-${empresa}"
  mkdir -p "${backup_dir}"
  chown deploy:deploy "${backup_dir}" 2>/dev/null || true

  data=$(date +%Y-%m-%d_%H-%M-%S)
  MF_BACKUP_ARQUIVO="${backup_dir}/backup-${db_name}-${data}.sql"

  local docker_pg pgdump_err="/tmp/pgdump_err_$$.log"
  local pgdump_ok=0
  : >"$pgdump_err"

  docker_pg=$(mf_backup_resolver_container_postgres "$empresa" "$db_user" "$db_pass" "$db_name" 2>>"$pgdump_err") || docker_pg=""

  if [ -n "$docker_pg" ]; then
    if docker exec "$docker_pg" env PGPASSWORD="${db_pass}" pg_dump -h 127.0.0.1 -p 5432 \
      -U "${db_user}" -d "${db_name}" -F p >"${MF_BACKUP_ARQUIVO}" 2>>"$pgdump_err"; then
      pgdump_ok=1
    fi
  fi

  if [ "$pgdump_ok" -eq 0 ]; then
    export PGPASSWORD="${db_pass}"
    if pg_dump -h "${db_host}" -p "${db_port}" -U "${db_user}" -d "${db_name}" -F p \
      >"${MF_BACKUP_ARQUIVO}" 2>>"$pgdump_err"; then
      pgdump_ok=1
    fi
    unset PGPASSWORD
  fi

  if [ "$pgdump_ok" -eq 0 ]; then
    [ -s "$pgdump_err" ] && cat "$pgdump_err" >&2
    rm -f "$pgdump_err" "${MF_BACKUP_ARQUIVO}"
    return 1
  fi

  rm -f "$pgdump_err"
  chown deploy:deploy "${MF_BACKUP_ARQUIVO}" 2>/dev/null || true

  if [ ! -s "${MF_BACKUP_ARQUIVO}" ] || [ "$(wc -c <"${MF_BACKUP_ARQUIVO}" 2>/dev/null || echo 0)" -lt "$min_bytes" ]; then
    printf "ERRO: Backup inválido ou muito pequeno (< %s bytes): %s\n" "$min_bytes" "${MF_BACKUP_ARQUIVO}" >&2
    rm -f "${MF_BACKUP_ARQUIVO}"
    return 1
  fi
  return 0
}
