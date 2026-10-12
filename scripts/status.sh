#!/usr/bin/env bash
# Quick health view: replication threads, lag, GTIDs.
source "$(dirname "$0")/lib.sh"

echo "== Source (mysql-0) =="
mysql_exec mysql-0 -e "SELECT @@server_id, @@read_only, @@gtid_executed\G"
echo "== Replica (mysql-1) =="
mysql_exec mysql-1 -e "SHOW REPLICA STATUS\G" \
  | grep -E 'Source_Host|Replica_IO_Running|Replica_SQL_Running|Seconds_Behind_Source|Retrieved_Gtid_Set|Executed_Gtid_Set|Last_.*Error:'
echo "== Applier workers =="
mysql_exec mysql-1 -e "SELECT WORKER_ID, SERVICE_STATE, LAST_ERROR_NUMBER, LAST_APPLIED_TRANSACTION
  FROM performance_schema.replication_applier_status_by_worker;"
