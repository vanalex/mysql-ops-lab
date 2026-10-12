#!/usr/bin/env bash
# Downloads Sakila and loads it on the SOURCE; replication carries it to the replica.
source "$(dirname "$0")/lib.sh"
CACHE="$(dirname "$0")/../.cache"
mkdir -p "$CACHE"

if [ ! -d "$CACHE/sakila-db" ]; then
  curl -fsSL https://downloads.mysql.com/docs/sakila-db.tar.gz -o "$CACHE/sakila-db.tar.gz"
  tar -xzf "$CACHE/sakila-db.tar.gz" -C "$CACHE"
fi

# Stored functions + binary logging can raise error 1418 without this.
mysql_exec mysql-0 -e "SET GLOBAL log_bin_trust_function_creators = ON;"
mysql_exec mysql-0 < "$CACHE/sakila-db/sakila-schema.sql"
mysql_exec mysql-0 < "$CACHE/sakila-db/sakila-data.sql"
mysql_exec mysql-0 < "$(dirname "$0")/../sql/lab-procedures.sql"

echo "Rentals on source:  $(mysql_exec mysql-0 -N -e 'SELECT COUNT(*) FROM sakila.rental')"
sleep 5
echo "Rentals on replica: $(mysql_exec mysql-1 -N -e 'SELECT COUNT(*) FROM sakila.rental')"
