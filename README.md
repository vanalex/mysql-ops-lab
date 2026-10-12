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

## Services

All of them run in the `mysql-lab` namespace.

| Service | What it does |
|---|---|
| **mysql-0** (`mysql-primary`) | The source. It takes every write and records each transaction in its binlog with a GTID. |
| **mysql-1** (`mysql-replica`) | An async GTID replica of mysql-0, kept `super_read_only`. Snapshots are taken from it so the source isn't loaded. |
| **mysql** (headless) | Gives each pod a stable DNS name (`mysql-0.mysql`, `mysql-1.mysql`), used for replication and by the scripts. |
| **rental-generator** (Redpanda Connect) | Generates continuous write load by calling `lab_new_rental`, which inserts a rental and its payment in one transaction. It is scaled to 0 until `make load-start`. |
| **SeaweedFS** | Local S3-compatible storage. It holds `s3://mysql-backups/` with `snapshots/<ts>/` and `binlogs/`. A one-off job creates the bucket. |
| **mysql-snapshot** (CronJob) | Every 6 hours, runs a MySQL Shell `util.dumpInstance` of the replica and uploads it to `snapshots/<ts>/`. Run `make snapshot-now` to trigger one immediately. |
| **binlog-archiver** | Streams binlogs from the source with `mysqlbinlog --stop-never` and syncs them to `binlogs/`. Together with a snapshot, this makes point-in-time recovery possible. |
| **mysql-restore** | A throwaway MySQL server used only to test restores. It is never part of replication. |
| **restore-snapshot** (Job) | Loads a chosen snapshot from S3 into mysql-restore with `util.loadDump` (`make restore`). |
| **pitr-replay** (Job) | Replays archived binlogs into mysql-restore up to a given timestamp (`make pitr`). |

The `Makefile` is the entry point for every step, `scripts/` has the bootstrap, status and verify helpers, and `DRILLS.md` lists the failure scenarios to practice.

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
