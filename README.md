# MySQL Ops Lab: replication, streaming writes, snapshots and PITR on Kubernetes

A hands-on lab for MySQL operations (not SQL). Sakila is the dataset; Redpanda Connect
generates continuous writes; native MySQL replication copies them; a CronJob and a binlog
archiver push everything to S3-compatible storage so you can practice point-in-time recovery.

## Architecture

```
                        +--------------------------+
  Redpanda Connect ---> |  mysql-0  (source)       | --- binlog stream ---> binlog-archiver ---+
  (rental-generator)    |  svc: mysql-primary      |                                          |
                        +------------+-------------+                                          |
                                     | native async replication (GTID)                        |
                        +------------v-------------+                                          v
                        |  mysql-1  (replica)      | --- util.dumpInstance ---> +----------------------+
                        |  svc: mysql-replica      |     (CronJob, every 6h)    | SeaweedFS (S3 API)   |
                        +--------------------------+                            | s3://mysql-backups/  |
                                                                                |   snapshots/<ts>/    |
                        +--------------------------+   util.loadDump +          |   binlogs/           |
                        |  mysql-restore (scratch) | <---- mysqlbinlog replay --+----------------------+
                        +--------------------------+
```

Point-in-time recovery = latest snapshot before the incident + binlogs replayed up to just before it.
The snapshot is taken from the replica and the binlogs come from the source; that works because GTIDs
identify transactions globally, so already-applied ones are skipped on replay.

## Layout

```
Makefile                       entry point for every step
kind-config.yaml               local Kubernetes cluster
k8s/
  00-namespace.yaml
  10-secrets.example.yaml      copy to 10-secrets.yaml (git-ignored)
  20-mysql-config.yaml         my.cnf + init script (server_id per pod)
  21-mysql-statefulset.yaml    mysql-0 / mysql-1, MySQL 8.4 LTS
  22-mysql-services.yaml       mysql (headless), mysql-primary, mysql-replica
  30-seaweedfs.yaml            S3-compatible storage
  31-create-bucket-job.yaml
  40-redpanda-connect.yaml     write-load generator (scaled to 0 by default)
  50-snapshot-cronjob.yaml     MySQL Shell dump -> S3
  60-binlog-archiver.yaml      mysqlbinlog --stop-never + S3 sync
  70-restore-target.yaml       throwaway MySQL for restore tests
  71-restore-snapshot-job.yaml util.loadDump from S3
  72-pitr-replay-job.yaml      binlog replay up to a timestamp
redpanda-connect/
  rental-generator.yaml        generate -> sql_raw (CALL lab_new_rental)
sql/
  lab-procedures.sql           rental + payment in one transaction
scripts/                       create users, set up replication, load Sakila, status, verify
DRILLS.md                      failure scenarios to practice
```

## Prerequisites

kind (or any cluster with a default StorageClass), kubectl, make, curl, tar.

## Quick start

```bash
make cluster
cp k8s/10-secrets.example.yaml k8s/10-secrets.yaml   # edit passwords + S3 keys
make secrets deploy
make bootstrap          # users -> replication -> Sakila
make status             # both replication threads should say Yes
make storage backups    # SeaweedFS, bucket, snapshot CronJob, binlog archiver
make load-config load-start
make snapshot-now       # don't wait 6 hours for the first one
```

Then work through `DRILLS.md`.

## Things to verify before trusting the skeleton

These are deliberately marked `TODO` in the files:

- Pin every image tag (`latest` is used for SeaweedFS, aws-cli and Redpanda Connect).
- Confirm `mysqlsh` exists in the `mysql:8.4` image; if not, use a MySQL Shell image for the backup/restore jobs.
- Confirm MySQL Shell picks up S3 credentials from `AWS_*` environment variables with your version, and that SeaweedFS accepts its request style.
- The binlog archiver always starts from the oldest binlog on the server and loses local state on restart; make it resume from S3.
- No snapshot or binlog retention yet.
- After a failover, the archiver and `mysql-primary` must follow the new source.

## Next steps

- Prometheus + mysqld_exporter + Grafana, and alerts on lag, failed backups and archiver delay.
- Semi-synchronous replication, then a 3-node InnoDB Cluster.
- Physical backups with XtraBackup as a sidecar streaming to S3 via xbcloud.
- A Redpanda broker in front of the generator, so writes arrive from a topic.
