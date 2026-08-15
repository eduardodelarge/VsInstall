#!/usr/bin/env bash
#
# install-vscode-arm64.sh — Instala o Visual Studio Code no Raspberry Pi (arm64)
# Alvo: Debian 13 (trixie) / Raspberry Pi OS 64-bit, Raspberry Pi 4
#
# Diferenças em relação à versão anterior:
#   - exige arm64 e explica o porquê se encontrar armhf
#   - detecta e corrige o repositório do Docker apontado para linux/raspbian
#   - tolera repositórios de terceiros quebrados sem abortar a instalação
#   - confirma que o pacote 'code' virá mesmo do repositório da Microsoft
#
# Uso:
#   ./install-vscode-arm64.sh              # instala
#   ./install-vscode-arm64.sh --uninstall  # remove VS Code e repositório
#
set -euo pipefail

KEYRING="/usr/share/keyrings/microsoft.gpg"
SOURCES_LIST="/etc/apt/sources.list.d/vscode.list"
REPO_URL="https://packages.microsoft.com/repos/code"
DOCKER_LIST="/etc/apt/sources.list.d/docker.list"
STAMP="$(date +%Y%m%d-%H%M%S)"

log()  { printf '\033[1;32m[+]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[!]\033[0m %s\n' "$*"; }
die()  { printf '\033[1;31m[x]\033[0m %s\n' "$*" >&2; exit 1; }

# --- Precisa de root ------------------------------------------------------
if [[ $EUID -ne 0 ]]; then
    command -v sudo >/dev/null || die "Rode como root ou instale o sudo."
    log "Reexecutando com sudo..."
    exec sudo -E bash "$0" "$@"
fi

# --- Desinstalação --------------------------------------------------------
if [[ "${1:-}" == "--uninstall" ]]; then
    log "Removendo o VS Code..."
    apt-get remove --purge -y code || true
    apt-get autoremove -y || true
    rm -f "$SOURCES_LIST" "$KEYRING"
    apt-get update -qq || true
    log "VS Code e repositório removidos."
    exit 0
fi

# --- Arquitetura: arm64 obrigatório ---------------------------------------
ARCH="$(dpkg --print-architecture)"
if [[ "$ARCH" != "arm64" ]]; then
    echo
    warn "Arquitetura detectada: $ARCH (este script exige arm64)."
    if [[ "$ARCH" == "armhf" ]]; then
        cat <<'MSG'

    Seu userland é 32 bits. O VS Code até instala em armhf, mas a Microsoft
    descontinuou o build de servidor ARM32 a partir da versão 1.86: extensões
    modernas e o Remote-SSH deixam de funcionar. Como seu kernel já é 64 bits,
    o caminho recomendado é reinstalar o Raspberry Pi OS 64-bit.

MSG
    fi
    die "Abortando para não deixar você com uma instalação quebrada."
fi
log "Arquitetura: $ARCH — suportada oficialmente."

# --- Correção do repositório do Docker ------------------------------------
# get.docker.com configura linux/raspbian em sistemas 32 bits. Esse caminho
# não publica trixie, e o erro derruba o apt-get update inteiro.
fix_docker_repo() {
    [[ -f "$DOCKER_LIST" ]] || return 0
    grep -q 'linux/raspbian' "$DOCKER_LIST" || return 0

    warn "Repositório do Docker aponta para linux/raspbian (variante 32 bits)."
    log  "Corrigindo para linux/debian, que publica pacotes trixie arm64..."
    cp -a "$DOCKER_LIST" "${DOCKER_LIST}.bak-${STAMP}"
    sed -i 's|linux/raspbian|linux/debian|g' "$DOCKER_LIST"
    log  "Backup salvo em ${DOCKER_LIST}.bak-${STAMP}"
}

# Repositórios quebrados não devem impedir a instalação do VS Code.
update_tolerante() {
    local saida
    if saida="$(apt-get update 2>&1)"; then
        return 0
    fi
    warn "Alguns repositórios falharam (não impede o VS Code):"
    grep -E '^(Err|E:)' <<<"$saida" | sed 's/^/      /' || true
    echo
    return 0
}

fix_docker_repo

log "Atualizando listas de pacotes..."
update_tolerante

# --- Já está instalado? ---------------------------------------------------
if command -v code >/dev/null 2>&1; then
    warn "VS Code já presente: $(code --version | head -n1)"
    read -rp "Continuar (atualiza para a última versão)? [s/N] " r
    [[ "${r,,}" == "s" ]] || exit 0
fi

# --- Dependências ---------------------------------------------------------
log "Instalando dependências..."
apt-get install -y wget gpg apt-transport-https ca-certificates

# --- Chave GPG da Microsoft ----------------------------------------------
log "Instalando a chave GPG da Microsoft..."
tmpkey="$(mktemp)"
trap 'rm -f "$tmpkey"' EXIT
wget -qO- https://packages.microsoft.com/keys/microsoft.asc \
    | gpg --dearmor > "$tmpkey"
[[ -s "$tmpkey" ]] || die "Falha ao baixar a chave. Verifique sua conexão."
install -D -o root -g root -m 644 "$tmpkey" "$KEYRING"

# --- Repositório do VS Code ----------------------------------------------
log "Configurando o repositório do VS Code..."
cat > "$SOURCES_LIST" <<EOF
deb [arch=arm64 signed-by=$KEYRING] $REPO_URL stable main
EOF
chmod 644 "$SOURCES_LIST"

log "Recarregando listas de pacotes..."
update_tolerante

# --- Confirma a origem do pacote -----------------------------------------
if ! apt-cache policy code 2>/dev/null | grep -q 'packages.microsoft.com'; then
    die "O pacote 'code' não apareceu no repositório da Microsoft.
    Rode 'sudo apt update' e verifique se houve erro de rede ou de chave GPG."
fi
log "Pacote localizado no repositório oficial da Microsoft."

# --- Instalação -----------------------------------------------------------
log "Instalando o VS Code (leva alguns minutos no Pi)..."
DEBIAN_FRONTEND=noninteractive apt-get install -y code

# --- Verificação ----------------------------------------------------------
command -v code >/dev/null 2>&1 \
    || die "Instalação concluída, mas o comando 'code' não foi encontrado."

log "Instalado com sucesso: $(code --version | head -n1)"
echo
echo "  Abrir:      menu Programação > Visual Studio Code, ou 'code' no terminal"
echo "  Atualizar:  sudo apt update && sudo apt upgrade"
if [[ -f "${DOCKER_LIST}.bak-${STAMP}" ]]; then
    echo "  Docker:     repositório corrigido; teste com 'sudo apt install docker-ce'"
fi
