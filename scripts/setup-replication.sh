#!/usr/bin/env bash
# Points mysql-1 at mysql-0 using GTID auto-positioning and makes it read-only.
# Intended for a FRESH replica: the RESET wipes its GTID history.
source "$(dirname "$0")/lib.sh"

mysql_exec mysql-1 <<SQL
STOP REPLICA;
RESET BINARY LOGS AND GTIDS;
CHANGE REPLICATION SOURCE TO
  SOURCE_HOST = 'mysql-0.mysql',
  SOURCE_PORT = 3306,
  SOURCE_USER = 'repl',
  SOURCE_PASSWORD = '$(secret REPL_PASSWORD)',
  SOURCE_AUTO_POSITION = 1,
  GET_SOURCE_PUBLIC_KEY = 1,
  SOURCE_CONNECT_RETRY = 10;
START REPLICA;
SET PERSIST read_only = ON;
SET PERSIST super_read_only = ON;
SQL

sleep 3
mysql_exec mysql-1 -e "SHOW REPLICA STATUS\G" \
  | grep -E 'Replica_IO_Running|Replica_SQL_Running|Seconds_Behind_Source|Last_.*Error:'
