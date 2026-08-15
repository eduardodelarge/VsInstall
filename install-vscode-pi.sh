#!/usr/bin/env bash
#
# install-vscode.sh — Instala o Visual Studio Code no Raspberry Pi
# Testado em: Debian 13 (trixie) / Raspberry Pi OS, Raspberry Pi 4, arm64
#
# Uso:
#   ./install-vscode.sh              # instala
#   ./install-vscode.sh --uninstall  # remove o VS Code e o repositório
#
set -euo pipefail

KEYRING="/usr/share/keyrings/microsoft.gpg"
SOURCES_LIST="/etc/apt/sources.list.d/vscode.list"
REPO_URL="https://packages.microsoft.com/repos/code"

log()  { printf '\033[1;32m[+]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[!]\033[0m %s\n' "$*"; }
die()  { printf '\033[1;31m[x]\033[0m %s\n' "$*" >&2; exit 1; }

# --- Precisa de root (via sudo) -------------------------------------------
if [[ $EUID -ne 0 ]]; then
    command -v sudo >/dev/null || die "Rode como root ou instale o sudo."
    log "Reexecutando com sudo..."
    exec sudo -E bash "$0" "$@"
fi

# --- Desinstalação --------------------------------------------------------
if [[ "${1:-}" == "--uninstall" ]]; then
    log "Removendo o VS Code..."
    apt-get remove --purge -y code || true
    rm -f "$SOURCES_LIST" "$KEYRING"
    apt-get update -qq || true
    log "VS Code e repositório removidos."
    exit 0
fi

# --- Verificação de arquitetura -------------------------------------------
ARCH="$(dpkg --print-architecture)"
case "$ARCH" in
    arm64|armhf|amd64) log "Arquitetura detectada: $ARCH" ;;
    *) die "Arquitetura '$ARCH' não é suportada pelo VS Code." ;;
esac

if [[ "$ARCH" == "armhf" ]]; then
    warn "Sistema de 32 bits. Funciona, mas o build arm64 é bem mais rápido."
fi

# --- Já está instalado? ---------------------------------------------------
if command -v code >/dev/null 2>&1; then
    warn "VS Code já instalado: $(code --version | head -n1)"
    read -rp "Continuar mesmo assim (atualiza para a última versão)? [s/N] " r
    [[ "${r,,}" == "s" ]] || exit 0
fi

# --- Dependências ---------------------------------------------------------
log "Instalando dependências..."
apt-get update -qq
apt-get install -y wget gpg apt-transport-https ca-certificates

# --- Chave GPG da Microsoft ----------------------------------------------
log "Baixando e instalando a chave GPG da Microsoft..."
tmpkey="$(mktemp)"
trap 'rm -f "$tmpkey"' EXIT
wget -qO- https://packages.microsoft.com/keys/microsoft.asc \
    | gpg --dearmor > "$tmpkey"
install -D -o root -g root -m 644 "$tmpkey" "$KEYRING"

# --- Repositório ----------------------------------------------------------
log "Configurando o repositório do VS Code..."
cat > "$SOURCES_LIST" <<EOF
deb [arch=amd64,arm64,armhf signed-by=$KEYRING] $REPO_URL stable main
EOF
chmod 644 "$SOURCES_LIST"

# --- Instalação -----------------------------------------------------------
log "Atualizando listas de pacotes..."
apt-get update -qq

log "Instalando o VS Code (pode demorar alguns minutos no Pi)..."
DEBIAN_FRONTEND=noninteractive apt-get install -y code

# --- Verificação ----------------------------------------------------------
if command -v code >/dev/null 2>&1; then
    log "Instalado com sucesso: $(code --version | head -n1)"
    echo
    echo "Abra pelo menu (Programação > Visual Studio Code) ou rode: code"
    echo "Atualizações futuras vêm junto com: sudo apt update && sudo apt upgrade"
else
    die "A instalação terminou, mas o comando 'code' não foi encontrado."
fi
