#!/usr/bin/env bash
# KoreST License — instalação automática com um comando (By @SpedyNet).
# Num Ubuntu Server 24.04 (x86_64), como root ou com sudo:
#
#   curl -fsSL https://raw.githubusercontent.com/ederdreger/korest-ls-install/main/install.sh | sudo bash
#
# Pergunta só o que falta, na tela:
#   1. o token do GitHub (o KoreST License é privado; o token não aparece na tela);
#   2. o domínio (Enter: korest.ls.spedynet.com.br) e um e-mail para os avisos do certificado;
#   3. a chave privada do KoreST: cole o conteúdo do private.pem (ou o caminho do arquivo).
# E faz o resto sozinho: confere o servidor, o DNS e as portas, instala o Docker e o KoreST License,
# emite o certificado HTTPS (renovação automática) e liga as atualizações do KoreST e do próprio
# KoreST License com o mesmo token. Rodar de novo atualiza para a última versão, sem perguntar nada.
#
# Sem perguntas (automação), passe tudo por variáveis:
#   curl -fsSL .../install.sh | sudo GH_TOKEN=github_pat_... KLS_DOMAIN=korest.ls.spedynet.com.br \
#     KLS_EMAIL=voce@exemplo.com KLS_KEY=/root/license-private.pem KLS_NONINTERACTIVE=1 bash
#
# Este arquivo não tem nada secreto: ele só baixa o resto do repositório privado com o token.
set -euo pipefail

REPO=${KLS_REPO:-ederdreger/korest-ls}
BRANCH=${KLS_BRANCH:-main}
DIST_REPO=${KLS_DIST_REPO:-ederdreger/KoreST}
DIR=${KLS_DIR:-/opt/korest-license}
TOKEN_FILE=/etc/korest-license.token
API=https://api.github.com

log() { printf '\n\033[1;35m==> %s\033[0m\n' "$*"; }
ok() { printf '  \033[1;32m✔\033[0m %s\n' "$*"; }
warn() { printf '  \033[1;33m[aviso] %s\033[0m\n' "$*"; }
die() { printf '\033[1;31m[erro] %s\033[0m\n' "$*" >&2; exit 1; }
tty_ok() { [ "${KLS_NONINTERACTIVE:-0}" != 1 ] && { : < /dev/tty; } 2>/dev/null; }

# Código HTTP do GitHub para o repositório com o token (200, 401, 404...; 000 = sem resposta)
gh_http() {
  curl -sS -o /dev/null -w '%{http_code}' --max-time 20 -H "Authorization: Bearer $1" \
    -H "Accept: application/vnd.github+json" "$API/repos/$2/releases?per_page=1" 2>/dev/null || echo 000
}

# Tudo dentro de main: um download cortado no meio não executa pela metade
main() {
  printf '\033[1;35m%s\033[0m\n' "KoreST License — instalação automática · By @SpedyNet"
  [ "$(id -u)" -eq 0 ] || die "rode como root: curl -fsSL <endereço>/install.sh | sudo bash"

  log "Conferindo o servidor"
  # shellcheck source=/dev/null
  . /etc/os-release
  if [ "${ID:-}" = ubuntu ] && [ "${VERSION_ID:-}" = 24.04 ]; then
    ok "${PRETTY_NAME}"
  elif [ "${KLS_FORCE_OS:-0}" = 1 ]; then
    warn "feito para o Ubuntu Server 24.04; este é ${PRETTY_NAME:-desconhecido} (KLS_FORCE_OS=1)"
  else
    die "feito para o Ubuntu Server 24.04 (este: ${PRETTY_NAME:-desconhecido}). Para tentar mesmo assim: KLS_FORCE_OS=1"
  fi
  [ "$(uname -m)" = x86_64 ] || die "o KoreST License é para servidores x86_64 (este: $(uname -m))"
  local cmd
  for cmd in curl python3 tar gzip sha256sum; do command -v "$cmd" >/dev/null || die "falta o comando $cmd (apt install $cmd)"; done
  if [ -f "$DIR/.env" ] && [ -f "$DIR/docker-compose.yml" ]; then
    ok "KoreST License já instalado em $DIR: vai atualizar e manter tudo"
  fi

  # ---------- Token do GitHub ----------
  log "Token do GitHub"
  local token=${GH_TOKEN:-} http tries=0
  [ -n "$token" ] || token=$(cat "$TOKEN_FILE" 2>/dev/null || true)
  while :; do
    if [ -z "$token" ]; then
      tty_ok || die "falta o token do GitHub: GH_TOKEN=github_pat_... (leitura de $REPO e $DIST_REPO)"
      if [ "$tries" -eq 0 ]; then
        echo "  O KoreST License é privado: precisa de um token de LEITURA do GitHub."
        echo "  GitHub › Settings › Developer settings › Fine-grained tokens › Generate new token:"
        echo "  repositórios $REPO e $DIST_REPO, permissão Contents: Read-only."
      fi
      read -rsp "  Cole o token e tecle Enter (ele não aparece na tela): " token < /dev/tty || true
      echo
    fi
    token=$(printf '%s' "$token" | tr -d '[:space:]')
    tries=$((tries + 1))
    if [[ ! "$token" =~ ^(github_pat_|ghp_)[A-Za-z0-9_]{20,}$ ]]; then
      warn "isso não parece um token do GitHub (começa com github_pat_ ou ghp_)"
    else
      http=$(gh_http "$token" "$REPO")
      case "$http" in
        200) ok "o token enxerga $REPO"; break ;;
        401) warn "o GitHub recusou o token (copiado errado ou vencido)" ;;
        403|404) warn "o token não enxerga $REPO: na criação, marque esse repositório com Contents: Read-only" ;;
        000) die "sem resposta do GitHub (esta VPS tem internet? DNS ok?)" ;;
        *) warn "o GitHub respondeu HTTP $http" ;;
      esac
    fi
    { tty_ok && [ "$tries" -lt 3 ]; } || die "não deu para usar o token do GitHub"
    token=
  done
  # O mesmo token entrega as atualizações do KoreST aos servidores dos clientes
  local dist=no
  if [ "$(gh_http "$token" "$DIST_REPO")" = 200 ]; then
    ok "o token enxerga $DIST_REPO: as atualizações do KoreST ficam ligadas"
    dist=yes
  else
    warn "o token não enxerga $DIST_REPO: os KoreST dos clientes não vão receber atualizações por aqui"
  fi

  # ---------- Gerenciador e instalador completo ----------
  log "Baixando o gerenciador korest-license"
  curl -fsSL --max-time 60 -H "Authorization: Bearer $token" -o /usr/bin/korest-license.new \
    "https://raw.githubusercontent.com/$REPO/$BRANCH/deploy/korest-license" \
    || { rm -f /usr/bin/korest-license.new; die "não consegui baixar o korest-license de github.com/$REPO"; }
  head -1 /usr/bin/korest-license.new | grep -q '^#!.*bash' || { rm -f /usr/bin/korest-license.new; die "download inválido do korest-license"; }
  chmod 0755 /usr/bin/korest-license.new
  mv -f /usr/bin/korest-license.new /usr/bin/korest-license
  ok "/usr/bin/korest-license"

  # Daqui em diante o instalador da última versão publicada (Releases) faz o resto: perguntas,
  # conferências, Docker, chave, certificado HTTPS. O token fica em $TOKEN_FILE (só o root lê),
  # para as atualizações do próprio KoreST License, e no .env, para as do KoreST.
  if [ "$dist" = yes ]; then
    GH_TOKEN=$token KLS_GITHUB_TOKEN=$token KLS_REPO=$REPO KLS_DIR=$DIR /usr/bin/korest-license install
  else
    GH_TOKEN=$token KLS_REPO=$REPO KLS_DIR=$DIR /usr/bin/korest-license install
    echo
    warn "Atualizações do KoreST desligadas: inclua $DIST_REPO no token (Contents: Read-only) e rode"
    warn "sudo korest-license github-token"
  fi
}

main "$@"
