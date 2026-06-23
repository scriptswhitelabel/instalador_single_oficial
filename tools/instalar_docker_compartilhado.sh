#!/bin/bash
# Instalação robusta do Docker para Debian/Ubuntu (inclui Trixie, SID e derivados).
# Uso: source este arquivo e chamar instalar_docker_compartilhado

instalar_docker_compartilhado() {
  if command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; then
    return 0
  fi

  local os_id="" os_codename="" arch=""
  if [ -f /etc/os-release ]; then
    # shellcheck disable=SC1091
    . /etc/os-release
    os_id="${ID:-}"
    os_codename="${VERSION_CODENAME:-}"
  fi
  arch=$(dpkg --print-architecture 2>/dev/null || uname -m)

  # Repositório oficial quebrado (ex.: ubuntu trixie sem pacotes)
  if [ -f /etc/apt/sources.list.d/docker.list ]; then
    if ! apt-cache policy docker-ce 2>/dev/null | awk '/Candidate:/ {print $2}' | grep -qv '(none)'; then
      rm -f /etc/apt/sources.list.d/docker.list
    fi
  fi

  _docker_pos_instalacao() {
    systemctl enable docker >/dev/null 2>&1 || true
    systemctl start docker >/dev/null 2>&1 || true
    sleep 2
    command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1
  }

  _docker_instalar_via_get_docker() {
    if ! command -v curl >/dev/null 2>&1; then
      apt-get update -y >/dev/null 2>&1 || true
      apt-get install -y curl ca-certificates >/dev/null 2>&1 || return 1
    fi
    curl -fsSL https://get.docker.com | sh
    _docker_pos_instalacao
  }

  _docker_instalar_via_repo_oficial() {
    apt-get update -y >/dev/null 2>&1 || return 1
    apt-get install -y ca-certificates curl gnupg lsb-release >/dev/null 2>&1 || return 1

    install -m 0755 -d /etc/apt/keyrings
    local repo_url="https://download.docker.com/linux/debian"
    local repo_codename="${os_codename}"

    if [ "$os_id" = "ubuntu" ]; then
      repo_url="https://download.docker.com/linux/ubuntu"
    fi

    case "${repo_codename}" in
      trixie|sid|unstable|testing|n/a|"")
        repo_codename="bookworm"
        ;;
      noble|mantic|lunar)
        repo_codename="jammy"
        ;;
    esac

    curl -fsSL "${repo_url}/gpg" | gpg --dearmor -o /etc/apt/keyrings/docker.gpg 2>/dev/null || return 1
    chmod a+r /etc/apt/keyrings/docker.gpg

    echo "deb [arch=${arch} signed-by=/etc/apt/keyrings/docker.gpg] ${repo_url} ${repo_codename} stable" \
      > /etc/apt/sources.list.d/docker.list

    apt-get update -y >/dev/null 2>&1 || return 1
    apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin >/dev/null 2>&1 || return 1
    _docker_pos_instalacao
  }

  _docker_instalar_via_distro() {
    apt-get update -y >/dev/null 2>&1 || return 1
    apt-get install -y docker.io docker-compose ca-certificates curl >/dev/null 2>&1 || return 1
    _docker_pos_instalacao
  }

  _docker_garantir_compose() {
    if docker compose version >/dev/null 2>&1; then
      return 0
    fi
    if command -v docker-compose >/dev/null 2>&1; then
      return 0
    fi
    apt-get install -y docker-compose-plugin >/dev/null 2>&1 || \
      apt-get install -y docker-compose >/dev/null 2>&1 || true
    docker compose version >/dev/null 2>&1 || command -v docker-compose >/dev/null 2>&1
  }

  if _docker_instalar_via_get_docker; then
    _docker_garantir_compose
    return 0
  fi

  if _docker_instalar_via_repo_oficial; then
    _docker_garantir_compose
    return 0
  fi

  if _docker_instalar_via_distro; then
    _docker_garantir_compose
    return 0
  fi

  return 1
}

verificar_docker_funcionando() {
  if ! command -v docker >/dev/null 2>&1; then
    return 1
  fi
  if ! docker info >/dev/null 2>&1; then
    systemctl start docker >/dev/null 2>&1 || true
    sleep 2
    docker info >/dev/null 2>&1 || return 1
  fi
  docker compose version >/dev/null 2>&1 || command -v docker-compose >/dev/null 2>&1
}
