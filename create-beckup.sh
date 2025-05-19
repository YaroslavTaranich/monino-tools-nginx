      apk add --no-cache postgresql-client tar find
      BACKUP_DIR=/backups/$$(date +%Y-%m-%d)
      mkdir -p $BACKUP_DIR
      echo \"Creating DB backup...\" 
      pg_dump -h postgres -U $${POSTGRES_USER} -d $${POSTGRES_DB} > $$BACKUP_DIR/db.sql
      echo \"Archiving static files...\" 
      tar -czf $$BACKUP_DIR/static.tar.gz -C /static-data .
      echo \"Cleaning old backups...\"
      find /backups -maxdepth 1 -type d -mtime +7 -exec rm -rf {} \;
      echo \"Backup completed successfully.\"