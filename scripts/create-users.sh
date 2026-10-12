#!/usr/bin/env bash
# Creates lab users on the SOURCE. Run before setup-replication.sh so the
# replica receives these transactions through replication too.
source "$(dirname "$0")/lib.sh"

mysql_exec mysql-0 <<SQL
CREATE USER IF NOT EXISTS 'repl'@'%' IDENTIFIED BY '$(secret REPL_PASSWORD)';
GRANT REPLICATION SLAVE ON *.* TO 'repl'@'%';

CREATE USER IF NOT EXISTS 'labwriter'@'%' IDENTIFIED BY '$(secret WRITER_PASSWORD)';
GRANT SELECT, INSERT, UPDATE, EXECUTE ON sakila.* TO 'labwriter'@'%';

CREATE USER IF NOT EXISTS 'backup'@'%' IDENTIFIED BY '$(secret BACKUP_PASSWORD)';
GRANT SELECT, RELOAD, PROCESS, EVENT, TRIGGER, SHOW VIEW,
      REPLICATION CLIENT, BACKUP_ADMIN ON *.* TO 'backup'@'%';

CREATE USER IF NOT EXISTS 'binlog_archiver'@'%' IDENTIFIED BY '$(secret BINLOG_PASSWORD)';
GRANT REPLICATION SLAVE, REPLICATION CLIENT ON *.* TO 'binlog_archiver'@'%';
SQL
echo "Users created on mysql-0."
