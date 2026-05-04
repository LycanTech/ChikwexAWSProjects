# ChikwexDockerApp

Multi-tier Docker Compose application demonstrating container orchestration best practices.

## Architecture

```
                    ┌─────────────┐
                    │   Client    │
                    └──────┬──────┘
                           │ :80
                    ┌──────▼──────┐
                    │    Nginx    │  (Reverse Proxy)
                    │   Gateway   │
                    └──────┬──────┘
              ┌────────────┴────────────┐
              │                         │
       ┌──────▼──────┐          ┌──────▼──────┐
       │  Frontend   │          │   Backend   │
       │   (React)   │          │   (Flask)   │
       │    :3000    │          │    :5000    │
       └─────────────┘          └──────┬──────┘
                                ┌──────┴──────┐
                         ┌──────▼─────┐ ┌─────▼──────┐
                         │ PostgreSQL │ │   Redis    │
                         │   :5432    │ │   :6379    │
                         └────────────┘ └────────────┘
```

## Services

| Service    | Technology      | Port | Description                    |
|------------|-----------------|------|--------------------------------|
| nginx      | Nginx Alpine    | 80   | Reverse proxy & load balancer  |
| frontend   | React 18        | 3000 | User interface                 |
| backend    | Flask/Gunicorn  | 5000 | REST API                       |
| db         | PostgreSQL 15   | 5432 | Primary database               |
| redis      | Redis 7         | 6379 | Caching layer                  |

## Quick Start

### Prerequisites
- Docker Engine 20.10+
- Docker Compose 2.0+

### Run the Application

```bash
# Clone and navigate to the project
cd ChikwexDockerApp

# Start all services
docker-compose up -d

# View logs
docker-compose logs -f

# Access the application
open http://localhost
```

### Development Mode

```bash
# Start with hot reload enabled
docker-compose -f docker-compose.yml -f docker-compose.dev.yml up

# Backend available at: http://localhost:5000
# Frontend available at: http://localhost:3000
# Database available at: localhost:5432
```

### Production Mode

```bash
# Start with resource limits
docker-compose -f docker-compose.yml -f docker-compose.prod.yml up -d
```

## Environment Variables

Copy `.env.example` to `.env` and configure:

| Variable      | Default     | Description              |
|---------------|-------------|--------------------------|
| DB_NAME       | appdb       | PostgreSQL database name |
| DB_USER       | appuser     | PostgreSQL username      |
| DB_PASSWORD   | apppassword | PostgreSQL password      |
| FLASK_DEBUG   | false       | Enable Flask debug mode  |

## API Endpoints

| Method | Endpoint     | Description              |
|--------|--------------|--------------------------|
| GET    | /health      | Health check             |
| GET    | /api/status  | Service status (DB, Redis)|
| GET    | /api/items   | List all items           |
| POST   | /api/items   | Create new item          |

## Docker Commands

```bash
# Build all images
docker-compose build

# Start services
docker-compose up -d

# Stop services
docker-compose down

# View running containers
docker-compose ps

# View logs
docker-compose logs -f [service]

# Execute command in container
docker-compose exec backend bash

# Remove all data (volumes)
docker-compose down -v
```

## Project Structure

```
ChikwexDockerApp/
├── backend/
│   ├── app.py              # Flask application
│   ├── requirements.txt    # Python dependencies
│   └── Dockerfile          # Multi-stage build
├── frontend/
│   ├── src/
│   │   ├── App.js          # React components
│   │   ├── App.css         # Styles
│   │   └── index.js        # Entry point
│   ├── public/
│   │   └── index.html      # HTML template
│   ├── package.json        # Node dependencies
│   ├── nginx.conf          # Frontend nginx config
│   └── Dockerfile          # Multi-stage build
├── nginx/
│   ├── nginx.conf          # Reverse proxy config
│   └── Dockerfile          # Nginx image
├── scripts/
│   ├── init-db.sql         # Database initialization
│   └── backup.sh           # Backup/restore utility
├── docker-compose.yml      # Main compose file
├── docker-compose.dev.yml  # Development overrides
├── docker-compose.prod.yml # Production overrides
├── docker-compose.secrets.yml # Secrets management
├── .env                    # Environment variables
├── .env.example            # Environment template
└── README.md               # This file
```

## Key Features

- **Multi-stage Builds**: Optimized image sizes
- **Non-root Users**: Enhanced security
- **Health Checks**: Container monitoring
- **Custom Networks**: Service isolation
- **Named Volumes**: Data persistence
- **Environment Configs**: Dev/Staging/Prod support
- **Resource Limits**: Production constraints

## Networking

| Network              | Services                    | Purpose              |
|----------------------|-----------------------------|----------------------|
| chikwex-frontend-net | nginx, frontend             | Frontend traffic     |
| chikwex-backend-net  | nginx, backend, db, redis   | Backend traffic      |

## Backup & Restore

### Database Backup

```bash
# Create backup of PostgreSQL and Redis
./scripts/backup.sh backup

# List available backups
./scripts/backup.sh list

# Restore from backup
./scripts/backup.sh restore ./backups/chikwex_db_20240115_120000.sql.gz
```

### Backup Schedule (Cron)

Add to crontab for automatic daily backups:
```bash
# Daily backup at 2 AM
0 2 * * * cd /path/to/ChikwexDockerApp && ./scripts/backup.sh backup >> /var/log/chikwex-backup.log 2>&1
```

## Secrets Management

For production, use Docker secrets instead of environment variables:

```bash
# Create secrets
echo "secure_db_password" | docker secret create db_password -
echo "secure_redis_password" | docker secret create redis_password -

# Deploy with secrets (requires Docker Swarm)
docker stack deploy -c docker-compose.yml -c docker-compose.secrets.yml chikwex
```

For non-Swarm environments, use `.env` files with restricted permissions:
```bash
chmod 600 .env
```

## Troubleshooting

```bash
# Check container health
docker-compose ps

# View specific service logs
docker-compose logs backend

# Restart a service
docker-compose restart backend

# Rebuild without cache
docker-compose build --no-cache

# Check network connectivity
docker-compose exec backend ping db
```

## Author

Chikwe Azinge - ChikwexDockerApp Assignment 6
