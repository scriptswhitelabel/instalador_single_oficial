#!/usr/bin/env bash
# Shared: tela de manutencao no frontend (atualizacao FAST / rollback)
# Requer variavel global: empresa

# Exporta apenas chaves necessarias do frontend/.env (sem source).
exportar_vars_frontend_env_seguro() {
  local fe_env="/home/deploy/${empresa}/frontend/.env"
  [ ! -f "$fe_env" ] && return 0
  export REACT_APP_LOGO_URL="$(grep -m1 '^REACT_APP_LOGO_URL=' "$fe_env" 2>/dev/null | cut -d= -f2- | tr -d '\r')"
  export REACT_APP_LOGO="$(grep -m1 '^REACT_APP_LOGO=' "$fe_env" 2>/dev/null | cut -d= -f2- | tr -d '\r')"
  export LOGO_URL="$(grep -m1 '^LOGO_URL=' "$fe_env" 2>/dev/null | cut -d= -f2- | tr -d '\r')"
  export REACT_APP_PRIMARY_COLOR="$(grep -m1 '^REACT_APP_PRIMARY_COLOR=' "$fe_env" 2>/dev/null | cut -d= -f2- | tr -d '\r')"
  export PRIMARY_COLOR="$(grep -m1 '^PRIMARY_COLOR=' "$fe_env" 2>/dev/null | cut -d= -f2- | tr -d '\r')"
  export REACT_APP_SECONDARY_COLOR="$(grep -m1 '^REACT_APP_SECONDARY_COLOR=' "$fe_env" 2>/dev/null | cut -d= -f2- | tr -d '\r')"
  export SECONDARY_COLOR="$(grep -m1 '^SECONDARY_COLOR=' "$fe_env" 2>/dev/null | cut -d= -f2- | tr -d '\r')"
}

ativar_tela_atualizacao_frontend() {
  local frontend_dir="/home/deploy/${empresa}/frontend"
  local build_dir="${frontend_dir}/build"
  local backup_dir="${frontend_dir}/.build_pre_update"
  local logo_url="${REACT_APP_LOGO_URL:-${REACT_APP_LOGO:-${LOGO_URL:-}}}"
  local cor_primaria="${REACT_APP_PRIMARY_COLOR:-${PRIMARY_COLOR:-#2563eb}}"
  local cor_secundaria="${REACT_APP_SECONDARY_COLOR:-${SECONDARY_COLOR:-#1e3a8a}}"
  local nome_empresa="${nome_titulo:-${empresa}}"
  local logo_fallback_text
  logo_fallback_text=$(printf '%s' "${nome_empresa}" | awk '{a=toupper(substr($1,1,1)); b=toupper(substr($2,1,1)); if (b=="") b=toupper(substr($1,2,1)); printf "%s%s", a,b}')
  [ -z "${logo_fallback_text}" ] && logo_fallback_text="MF"

  rm -rf "${backup_dir}"
  if [ -d "${build_dir}" ]; then
    mv "${build_dir}" "${backup_dir}"
  fi
  mkdir -p "${build_dir}"

  cat > "${build_dir}/index.html" <<EOF
<!DOCTYPE html>
<html lang="pt-BR">
<head>
  <meta charset="UTF-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1.0" />
  <title>${nome_empresa} | Atualizacao em andamento</title>
  <style>
    :root {
      --primary: ${cor_primaria};
      --secondary: ${cor_secundaria};
      --bg: #0f172a;
      --text: #e2e8f0;
    }
    * { box-sizing: border-box; }
    body {
      margin: 0;
      min-height: 100vh;
      font-family: Inter, Arial, sans-serif;
      background: radial-gradient(circle at 20% 20%, var(--secondary), var(--bg) 60%);
      color: var(--text);
      display: flex;
      align-items: center;
      justify-content: center;
      padding: 24px;
    }
    .card {
      width: 100%;
      max-width: 520px;
      background: rgba(15, 23, 42, 0.78);
      border: 1px solid rgba(148, 163, 184, 0.28);
      border-radius: 18px;
      padding: 36px 30px;
      text-align: center;
      box-shadow: 0 20px 50px rgba(0, 0, 0, 0.45);
      backdrop-filter: blur(4px);
    }
    .logo {
      width: 74px;
      height: 74px;
      object-fit: contain;
      margin-bottom: 14px;
    }
    .logo-fallback {
      width: 74px;
      height: 74px;
      border-radius: 14px;
      margin: 0 auto 14px auto;
      display: grid;
      place-items: center;
      background: linear-gradient(135deg, var(--primary), var(--secondary));
      color: #fff;
      font-weight: 700;
      font-size: 24px;
    }
    h1 {
      margin: 0 0 10px 0;
      font-size: 24px;
      color: #f8fafc;
    }
    p {
      margin: 0;
      color: #cbd5e1;
      line-height: 1.5;
    }
    .bar {
      margin-top: 24px;
      height: 10px;
      background: rgba(148, 163, 184, 0.3);
      border-radius: 999px;
      overflow: hidden;
    }
    .bar span {
      display: block;
      height: 100%;
      width: 35%;
      border-radius: inherit;
      background: linear-gradient(90deg, var(--primary), #38bdf8, var(--secondary));
      animation: loading 1.35s ease-in-out infinite;
    }
    .counter {
      margin-top: 14px;
      font-size: 13px;
      color: #94a3b8;
    }
    @keyframes loading {
      0% { transform: translateX(-110%); }
      100% { transform: translateX(320%); }
    }
  </style>
</head>
<body>
  <div class="card">
    __LOGO_BLOCK__
    <h1>Sistema em atualizacao</h1>
    <p>Estamos aplicando melhorias no <strong>${nome_empresa}</strong>.<br />Volte em instantes para continuar usando normalmente.</p>
    <div class="bar"><span></span></div>
    <div class="counter">Tempo estimado restante: <strong id="countdown">10:00</strong></div>
  </div>
  <script>
    const countdownEl = document.getElementById('countdown');
    const totalSeconds = 10 * 60;
    const storageKey = 'mf_update_countdown_end_' + window.location.host;
    const now = Date.now();
    let endAt = parseInt(localStorage.getItem(storageKey) || '0', 10);

    if (!endAt || endAt <= now) {
      endAt = now + (totalSeconds * 1000);
      localStorage.setItem(storageKey, String(endAt));
    }

    const formatTime = (value) => {
      const minutes = Math.floor(value / 60);
      const seconds = value % 60;
      return String(minutes).padStart(2, '0') + ':' + String(seconds).padStart(2, '0');
    };

    const tick = () => {
      const remainingSeconds = Math.max(0, Math.ceil((endAt - Date.now()) / 1000));
      countdownEl.textContent = formatTime(remainingSeconds);
      if (remainingSeconds <= 0) {
        localStorage.removeItem(storageKey);
      }
    };

    tick();
    setInterval(tick, 1000);
  </script>
</body>
</html>
EOF

  if [ -n "${logo_url}" ]; then
    sed -i "s|__LOGO_BLOCK__|<img class=\"logo\" src=\"${logo_url}\" alt=\"Logo ${nome_empresa}\" />|g" "${build_dir}/index.html"
  else
    sed -i "s|__LOGO_BLOCK__|<div class=\"logo-fallback\">${logo_fallback_text}</div>|g" "${build_dir}/index.html"
  fi

  chown -R deploy:deploy "${build_dir}"
  chmod -R 775 "${build_dir}"
}

publicar_build_frontend_atualizado() {
  local frontend_dir="/home/deploy/${empresa}/frontend"
  local build_dir="${frontend_dir}/build"
  local backup_dir="${frontend_dir}/.build_pre_update"
  local next_dir="${frontend_dir}/.build_nova"

  if [ ! -d "${next_dir}" ]; then
    printf "${RED} >> ERRO: build novo nao encontrado em ${next_dir}.${WHITE}\n"
    return 1
  fi

  rm -rf "${build_dir}"
  mv "${next_dir}" "${build_dir}"
  rm -rf "${backup_dir}"
  chown -R deploy:deploy "${build_dir}"
  chmod -R 775 "${build_dir}"
}

restaurar_build_frontend_anterior() {
  local frontend_dir="/home/deploy/${empresa}/frontend"
  local build_dir="${frontend_dir}/build"
  local backup_dir="${frontend_dir}/.build_pre_update"
  local next_dir="${frontend_dir}/.build_nova"

  rm -rf "${next_dir}"
  rm -rf "${build_dir}"
  if [ -d "${backup_dir}" ]; then
    mv "${backup_dir}" "${build_dir}"
    chown -R deploy:deploy "${build_dir}"
    chmod -R 775 "${build_dir}"
  fi
}
