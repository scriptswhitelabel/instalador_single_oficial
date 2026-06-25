#!/usr/bin/env bash
# Baileys/Hineken: garante branch main no package.json do backend (MultiFlow-PRO).
# Uso como root: . tools/baileys_hineken_package_json.sh && mf_baileys_fixar_branch_main_package_json "$pkg"
# Em heredocs "su - deploy": usar sed inline (deploy não lê /root/instalador_single_oficial).

mf_baileys_fixar_branch_main_package_json() {
  local pkg="${1:-}"
  [ -z "$pkg" ] && return 0
  [ ! -f "$pkg" ] && return 0
  grep -q 'scriptswhitelabel/Hineken' "$pkg" 2>/dev/null || return 0
  sed -i -E 's|(github\.com/scriptswhitelabel/Hineken\.git)(#[^"]*)?|\1#main|g' "$pkg"
  return 0
}
