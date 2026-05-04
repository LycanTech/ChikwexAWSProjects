#!/bin/bash
# ChikwexDockerApp - Database Backup Script
# Usage: ./scripts/backup.sh [backup|restore] [backup_file]

set -e

# Configuration
CONTAINER_NAME="chikwex-db"
BACKUP_DIR="./backups"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
DB_NAME="${DB_NAME:-appdb}"
DB_USER="${DB_USER:-appuser}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Create backup directory if it doesn't exist
mkdir -p "$BACKUP_DIR"

backup() {
    echo -e "${YELLOW}Starting PostgreSQL backup...${NC}"

    BACKUP_FILE="${BACKUP_DIR}/chikwex_db_${TIMESTAMP}.sql.gz"

    # Create compressed backup
    docker exec "$CONTAINER_NAME" pg_dump -U "$DB_USER" "$DB_NAME" | gzip > "$BACKUP_FILE"

    if [ $? -eq 0 ]; then
        echo -e "${GREEN}Backup completed successfully!${NC}"
        echo "Backup saved to: $BACKUP_FILE"
        echo "Size: $(du -h "$BACKUP_FILE" | cut -f1)"

        # Keep only last 7 backups
        echo -e "${YELLOW}Cleaning old backups (keeping last 7)...${NC}"
        ls -t "$BACKUP_DIR"/chikwex_db_*.sql.gz 2>/dev/null | tail -n +8 | xargs -r rm -f
        echo -e "${GREEN}Cleanup complete.${NC}"
    else
        echo -e "${RED}Backup failed!${NC}"
        exit 1
    fi
}

restore() {
    if [ -z "$1" ]; then
        echo -e "${RED}Error: Please specify backup file to restore${NC}"
        echo "Usage: $0 restore <backup_file>"
        echo ""
        echo "Available backups:"
        ls -lh "$BACKUP_DIR"/chikwex_db_*.sql.gz 2>/dev/null || echo "No backups found"
        exit 1
    fi

    BACKUP_FILE="$1"

    if [ ! -f "$BACKUP_FILE" ]; then
        echo -e "${RED}Error: Backup file not found: $BACKUP_FILE${NC}"
        exit 1
    fi

    echo -e "${YELLOW}WARNING: This will overwrite the current database!${NC}"
    read -p "Are you sure you want to restore from $BACKUP_FILE? (y/N) " -n 1 -r
    echo

    if [[ $REPLY =~ ^[Yy]$ ]]; then
        echo -e "${YELLOW}Restoring database...${NC}"

        # Drop and recreate database
        docker exec "$CONTAINER_NAME" psql -U "$DB_USER" -c "DROP DATABASE IF EXISTS $DB_NAME;"
        docker exec "$CONTAINER_NAME" psql -U "$DB_USER" -c "CREATE DATABASE $DB_NAME;"

        # Restore from backup
        gunzip -c "$BACKUP_FILE" | docker exec -i "$CONTAINER_NAME" psql -U "$DB_USER" "$DB_NAME"

        if [ $? -eq 0 ]; then
            echo -e "${GREEN}Restore completed successfully!${NC}"
        else
            echo -e "${RED}Restore failed!${NC}"
            exit 1
        fi
    else
        echo "Restore cancelled."
    fi
}

backup_redis() {
    echo -e "${YELLOW}Starting Redis backup...${NC}"

    REDIS_BACKUP="${BACKUP_DIR}/chikwex_redis_${TIMESTAMP}.rdb"

    # Trigger Redis save and copy the dump file
    docker exec chikwex-redis redis-cli BGSAVE
    sleep 2
    docker cp chikwex-redis:/data/appendonly.aof "${BACKUP_DIR}/chikwex_redis_${TIMESTAMP}.aof" 2>/dev/null || true

    echo -e "${GREEN}Redis backup completed!${NC}"
}

list() {
    echo -e "${YELLOW}Available backups:${NC}"
    echo ""
    echo "PostgreSQL backups:"
    ls -lh "$BACKUP_DIR"/chikwex_db_*.sql.gz 2>/dev/null || echo "  No PostgreSQL backups found"
    echo ""
    echo "Redis backups:"
    ls -lh "$BACKUP_DIR"/chikwex_redis_*.aof 2>/dev/null || echo "  No Redis backups found"
}

# Main
case "$1" in
    backup)
        backup
        backup_redis
        ;;
    restore)
        restore "$2"
        ;;
    list)
        list
        ;;
    *)
        echo "ChikwexDockerApp Backup Utility"
        echo ""
        echo "Usage: $0 {backup|restore|list}"
        echo ""
        echo "Commands:"
        echo "  backup              Create backup of PostgreSQL and Redis"
        echo "  restore <file>      Restore PostgreSQL from backup file"
        echo "  list                List available backups"
        echo ""
        exit 1
        ;;
esac
