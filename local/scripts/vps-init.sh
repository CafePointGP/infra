#!/usr/bin/env bash
# vps-init.sh — Setup completo da VPS Hetzner para staging CafePointGP.
# Uso: scp este arquivo para a VPS e execute como root.
#
# sshpass -p '<SENHA>' scp infra/local/scripts/vps-init.sh root@<IP>:/tmp/
# sshpass -p '<SENHA>' ssh root@<IP> "chmod +x /tmp/vps-init.sh && /tmp/vps-init.sh"

set -euo pipefail

echo "============================================"
echo "  CafePointGP — VPS Init (Staging)"
echo "============================================"

# -----------------------------------------------
# 1. Pacotes base
# -----------------------------------------------
echo ""
echo "==> [1/7] Instalando pacotes base..."
apt update -qq
apt install -y -qq curl git ufw fail2ban > /dev/null

# -----------------------------------------------
# 2. Docker
# -----------------------------------------------
echo "==> [2/7] Instalando Docker..."
if command -v docker &> /dev/null; then
    echo "    Docker já instalado: $(docker --version)"
else
    curl -fsSL https://get.docker.com | sh
    systemctl enable docker
    systemctl start docker
    echo "    Docker instalado: $(docker --version)"
fi
echo "    Compose: $(docker compose version)"

# -----------------------------------------------
# 3. Firewall
# -----------------------------------------------
echo "==> [3/7] Configurando firewall..."
ufw default deny incoming > /dev/null
ufw default allow outgoing > /dev/null
ufw allow 22/tcp > /dev/null
ufw allow 80/tcp > /dev/null
ufw allow 443/tcp > /dev/null
ufw --force enable > /dev/null
echo "    UFW ativo: $(ufw status | head -1)"

# -----------------------------------------------
# 4. Diretório de deploy
# -----------------------------------------------
echo "==> [4/7] Criando estrutura de diretórios..."
DEPLOY_DIR="/opt/cafepointgp"
mkdir -p "$DEPLOY_DIR/nginx/conf.d"
echo "    $DEPLOY_DIR criado"

# -----------------------------------------------
# 5. SSH key para GitHub Actions
# -----------------------------------------------
echo "==> [5/7] Gerando chave SSH para GitHub Actions..."
SSH_KEY="$DEPLOY_DIR/.deploy_key"
if [ -f "$SSH_KEY" ]; then
    echo "    Chave já existe, pulando..."
else
    ssh-keygen -t ed25519 -C "github-actions-deploy" -f "$SSH_KEY" -N ""
    cat "${SSH_KEY}.pub" >> /root/.ssh/authorized_keys
    chmod 600 /root/.ssh/authorized_keys
    echo "    Chave gerada e adicionada ao authorized_keys"
fi

# -----------------------------------------------
# 6. Gerar .env com senhas seguras
# -----------------------------------------------
echo "==> [6/7] Gerando .env..."
ENV_FILE="$DEPLOY_DIR/.env"
if [ -f "$ENV_FILE" ]; then
    echo "    .env já existe, pulando..."
else
    DB_PASS=$(openssl rand -base64 32 | tr -d '\n/+=')
    REDIS_PASS=$(openssl rand -base64 32 | tr -d '\n/+=')
    JWT_SECRET=$(openssl rand -base64 64 | tr -d '\n/+=')

    cat > "$ENV_FILE" << EOF
DB_PASSWORD=${DB_PASS}
REDIS_PASSWORD=${REDIS_PASS}
JWT_SECRET=${JWT_SECRET}
EOF
    chmod 600 "$ENV_FILE"
    echo "    .env criado com senhas geradas"
fi

# -----------------------------------------------
# 7. Resumo
# -----------------------------------------------
echo ""
echo "============================================"
echo "  Setup concluído!"
echo "============================================"
echo ""
echo "Próximos passos manuais:"
echo ""
echo "1. Configure os GitHub Secrets (Actions):"
echo "   VPS_HOST = $(curl -s ifconfig.me 2>/dev/null || echo '<IP_DA_VPS>')"
echo "   VPS_USER = root"
echo "   VPS_SSH_KEY = (conteúdo abaixo)"
echo ""
echo "--- CHAVE PRIVADA (copie para GitHub Secret VPS_SSH_KEY) ---"
cat "$SSH_KEY"
echo ""
echo "--- FIM DA CHAVE ---"
echo ""
echo "2. Crie um GitHub PAT com scope 'read:packages' e salve:"
echo "   echo '<PAT>' > $DEPLOY_DIR/.ghcr_token && chmod 600 $DEPLOY_DIR/.ghcr_token"
echo ""
echo "3. Os arquivos de config (compose, nginx, deploy.sh) serão"
echo "   copiados na sequência pelo script de setup local."
echo ""
