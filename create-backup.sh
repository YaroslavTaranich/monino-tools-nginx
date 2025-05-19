docker exec -t postgres pg_dump -U $POSTGRES_USER $POSTGRES_DB > backup.sql
