# CafePoint GP — Infraestrutura

Configurações de infraestrutura para os ambientes do CafePoint GP. Montado como submodule no monorepo principal.

## Estrutura

```
infra/
├── local/                      # Docker Compose — dev & produção single-server
│   ├── nginx/                  # Reverse proxy
│   │   ├── nginx.conf          # Config principal
│   │   ├── conf.d/
│   │   │   └── default.conf    # Virtual hosts, rate limiting, TLS
│   │   └── ssl/                # Certificados TLS (não versionados)
│   │
│   ├── pgadmin/                # pgAdmin 4 (dev only)
│   │   ├── servers.json        # Auto-registro do servidor Postgres
│   │   └── pgpassfile          # Credenciais para conexão sem senha
│   │
│   ├── postgres/               # Inicialização do PostgreSQL
│   │   └── init.sql            # Extensões (pg_uuidv7, pgcrypto)
│   │
│   └── scripts/                # Scripts de deploy e manutenção
│
└── k8s/                        # (futuro) Kubernetes manifests
```

## Convenção

Cada serviço que precise de configuração externa tem sua própria pasta em `infra/<ambiente>/<serviço>/`. Os caminhos são referenciados no `docker-compose.yml` via `./infra/local/<serviço>/...`.

## local/ — Referência de volumes

| Arquivo | Montado em | Serviço |
|---|---|---|
| `nginx/nginx.conf` | `/etc/nginx/nginx.conf` | nginx |
| `nginx/conf.d/default.conf` | `/etc/nginx/conf.d/default.conf` | nginx |
| `nginx/ssl/` | `/etc/nginx/ssl/` | nginx |
| `pgadmin/servers.json` | `/pgadmin4/servers.json` | pgadmin (dev) |
| `pgadmin/pgpassfile` | `/tmp/pgpassfile` | pgadmin (dev) |
| `postgres/init.sql` | `/docker-entrypoint-initdb.d/init.sql` | postgres |

## Portas de desenvolvimento local

| Serviço | Porta |
|---|---|
| Frontend | `localhost:3000` |
| API | `localhost:5001` |
| pgAdmin | `localhost:5050` |
| PostgreSQL | `localhost:5433` |
| Redis | `localhost:6380` |

## Adicionando config de novo serviço

1. Crie a pasta `infra/local/<serviço>/`
2. Adicione os arquivos de configuração
3. Referencie no `docker-compose.yml` ou `docker-compose.override.yml` via `./infra/local/<serviço>/...`
