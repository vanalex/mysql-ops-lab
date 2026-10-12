# Drills

Each drill: break something on purpose, recover, and write down what you saw and how long it took.

## 1. Replication lag under load
- Lower `RENTAL_INTERVAL` in `k8s/40-redpanda-connect.yaml` (e.g. `10ms`), re-apply, watch `make status`.
- Compare `Seconds_Behind_Source` with `performance_schema.replication_applier_status_by_worker`.
- Done when: you can explain where the lag comes from and make it disappear.

## 2. Duplicate-key error (1062)
- On mysql-1: `SET GLOBAL super_read_only=OFF;` insert an `actor` row with a chosen `actor_id`.
- On mysql-0: insert the same `actor_id`.
- Diagnose with `make status`; fix by removing the conflicting row on the replica and restarting the applier.
- Done when: replica is running and `make verify` passes (stop load first).

## 3. Missing row (1032)
- Delete a `customer` on the replica, then update it on the source.
- Done when: you can describe two fixes and when each is acceptable.

## 4. Source failure and promotion
- `make load-stop`, then delete the mysql-0 pod or scale the StatefulSet so it stays down.
- On mysql-1: `STOP REPLICA; RESET REPLICA ALL; SET PERSIST super_read_only=OFF, read_only=OFF;`
- Repoint `mysql-primary` to mysql-1 (`kubectl patch svc ...`), restart the generator.
- Bring mysql-0 back as a replica of mysql-1.
- Done when: writes flow to the new source and the old one replicates from it. Note what broke in the binlog archiver.

## 5. Point-in-time recovery
- Note the UTC time, then on mysql-0 run `DELETE FROM sakila.payment WHERE payment_id < 5000;`
- `make restore SNAPSHOT=snapshots/<latest before the delete>`
- `make pitr STOP='<a second before the delete>'`
- `./scripts/verify.sh mysql-0 mysql-restore` will differ (the delete); check the deleted rows exist on mysql-restore.
- Done when: no data from before the delete is lost.

## 6. Gap in the binlog chain
- Scale the binlog archiver to 0, generate load, `FLUSH BINARY LOGS` a few times, then `PURGE BINARY LOGS TO '...'`.
- Restart the archiver and try a PITR across the gap.
- Done when: you can explain the failure and which config/alert would have prevented it.

## 7. Restore to a fresh server from S3 only
- Pretend the cluster is gone: use only what's in `s3://mysql-backups/`.
- Done when: you have a documented runbook and a measured recovery time.

## 8. Storage full
- Shrink the SeaweedFS PVC (new cluster) or fill it, let a snapshot fail.
- Done when: the failure is visible without reading pod logs (alert or status).
