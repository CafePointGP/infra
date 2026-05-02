# Setup Inicial da VPS Hetzner (Staging)

Guia para configurar a VPS do zero para receber deploys automatizados do GitHub Actions.

## Pre-requisitos

- VPS Hetzner criada (CX21 para staging: 2 vCPU, 4 GB RAM, 40 GB SSD)
- Acesso SSH root à VPS
- DNS configurado no Cloudflare:
  - `staging.cafepointgp.club` → IP da VPS
  - `api-staging.cafepointgp.club` → IP da VPS

## 1. Acesso inicial e atualização

```bash
ssh root@<VPS_IP>
apt update && apt upgrade -y
apt install -y curl git ufw fail2ban
```

## 2. Criar usuário deploy

```bash
useradd -m -s /bin/bash deploy
mkdir -p /home/deploy/.ssh
cp ~/.ssh/authorized_keys /home/deploy/.ssh/
chown -R deploy:deploy /home/deploy/.ssh
chmod 700 /home/deploy/.ssh
chmod 600 /home/deploy/.ssh/authorized_keys
```

## 3. Instalar Docker

```bash
curl -fsSL https://get.docker.com | sh
systemctl enable docker
systemctl start docker
usermod -aG docker deploy
```

Verificar: `docker compose version` (deve ser v2.x+)

## 4. Firewall

```bash
ufw default deny incoming
ufw default allow outgoing
ufw allow 22/tcp
ufw allow 80/tcp
ufw allow 443/tcp
ufw --force enable
```

## 5. SSH key para GitHub Actions

Na sua **máquina local**, gere uma chave dedicada:

```bash
ssh-keygen -t ed25519 -C "github-actions-deploy" -f ~/.ssh/cafepointgp_deploy -N ""
```

Copie a chave pública para a VPS:

```bash
ssh-copy-id -i ~/.ssh/cafepointgp_deploy.pub deploy@<VPS_IP>
```

O conteúdo da chave **privada** (`~/.ssh/cafepointgp_deploy`) vai no GitHub Secret `VPS_SSH_KEY`.

## 6. Diretório do projeto na VPS

```bash
# Como root:
mkdir -p /opt/cafepointgp
chown deploy:deploy /opt/cafepointgp

# Como deploy:
su - deploy
cd /opt/cafepointgp
```

### 6.1 Copiar arquivos de config (da sua máquina local)

```bash
# Na máquina local, na raiz do projeto:
scp docker-compose.staging.yml deploy@<VPS_IP>:/opt/cafepointgp/
scp infra/local/scripts/deploy.sh deploy@<VPS_IP>:/opt/cafepointgp/
scp -r infra/staging/nginx deploy@<VPS_IP>:/opt/cafepointgp/

# Na VPS:
ssh deploy@<VPS_IP> "chmod +x /opt/cafepointgp/deploy.sh"
```

### 6.2 Criar .env na VPS

```bash
# Na VPS como deploy:
cat > /opt/cafepointgp/.env << 'EOF'
DB_PASSWORD=<gere-uma-senha-segura>
REDIS_PASSWORD=<gere-uma-senha-segura>
JWT_SECRET=<gere-uma-chave-de-pelo-menos-64-caracteres>
AZURE_STORAGE_CONNECTION=<do-azure-portal>
SENDGRID_API_KEY=<do-sendgrid>
EOF
chmod 600 /opt/cafepointgp/.env
```

Para gerar senhas seguras:

```bash
openssl rand -base64 32  # para DB_PASSWORD e REDIS_PASSWORD
openssl rand -base64 64  # para JWT_SECRET
```

### 6.3 Token ghcr.io na VPS

Crie um GitHub PAT (Personal Access Token) com scope `read:packages` em:
https://github.com/settings/tokens/new

```bash
echo "<SEU_PAT_AQUI>" > /opt/cafepointgp/.ghcr_token
chmod 600 /opt/cafepointgp/.ghcr_token
```

## 7. Certificado SSL (Let's Encrypt)

Antes de rodar o certbot, o DNS já deve apontar para a VPS.

```bash
# Na VPS como deploy:
cd /opt/cafepointgp

# Criar volumes Docker para certbot
docker volume create cafepointgp_certbot_certs
docker volume create cafepointgp_certbot_www

# Subir nginx temporário para o challenge ACME
docker run -d --name certbot-init \
  -p 80:80 \
  -v cafepointgp_certbot_www:/var/www/certbot \
  nginx:alpine \
  sh -c 'mkdir -p /var/www/certbot/.well-known/acme-challenge && nginx -g "daemon off;"'

# Obter certificados
docker run --rm \
  -v cafepointgp_certbot_certs:/etc/letsencrypt \
  -v cafepointgp_certbot_www:/var/www/certbot \
  certbot/certbot certonly \
    --webroot -w /var/www/certbot \
    -d staging.cafepointgp.club \
    -d api-staging.cafepointgp.club \
    --email dev@cafepointgp.club \
    --agree-tos --no-eff-email

# Remover nginx temporário
docker stop certbot-init && docker rm certbot-init
```

## 8. GitHub Secrets

Configure em: `https://github.com/CafePointGP/CafePointGP/settings/secrets/actions`

| Secret | Valor |
|---|---|
| `VPS_HOST` | IP da VPS Hetzner |
| `VPS_SSH_KEY` | Conteúdo de `~/.ssh/cafepointgp_deploy` (chave privada) |
| `VPS_USER` | `deploy` |

## 9. GitHub Environment

Crie um environment `staging` em:
`https://github.com/CafePointGP/CafePointGP/settings/environments`

Isso permite proteções futuras (aprovação manual, branch restrictions).

## 10. Primeiro deploy

Após configurar tudo:

1. Faça um merge na branch `main` do repositório
2. Acompanhe o workflow em: `https://github.com/CafePointGP/CafePointGP/actions`
3. Verifique na VPS:

```bash
ssh deploy@<VPS_IP>
docker ps  # todos containers rodando
curl -k https://staging.cafepointgp.club  # frontend
curl -k https://api-staging.cafepointgp.club/health  # API health
```

## Estrutura final na VPS

```
/opt/cafepointgp/
├── docker-compose.staging.yml
├── deploy.sh
├── .env                    # secrets (chmod 600)
├── .ghcr_token             # PAT ghcr.io (chmod 600)
├── CURRENT_VERSION         # criado pelo deploy.sh
└── nginx/
    ├── nginx.conf
    └── conf.d/
        └── default.conf
```
