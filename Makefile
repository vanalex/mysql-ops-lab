NS := mysql-lab
K  := kubectl -n $(NS)

.PHONY: help cluster secrets deploy wait users replication sakila bootstrap \
	    storage backups load-config load-start load-stop \
	    snapshot-now restore pitr status verify clean destroy

help:
	@echo "Setup:    cluster secrets deploy bootstrap storage backups load-config load-start"
	@echo "Operate:  status verify snapshot-now load-stop"
	@echo "Recover:  restore SNAPSHOT=snapshots/<ts>   pitr STOP='YYYY-MM-DD HH:MM:SS'"
	@echo "Cleanup:  clean destroy"

## --- Setup ------------------------------------------------------------------

cluster:
	kind create cluster --config kind-config.yaml

secrets:
	@test -f k8s/10-secrets.yaml || (echo "Copy k8s/10-secrets.example.yaml to k8s/10-secrets.yaml and edit it"; exit 1)
	kubectl apply -f k8s/00-namespace.yaml
	kubectl apply -f k8s/10-secrets.yaml

deploy:
	kubectl apply -f k8s/20-mysql-config.yaml -f k8s/21-mysql-statefulset.yaml -f k8s/22-mysql-services.yaml
	$(MAKE) wait

wait:
	$(K) rollout status statefulset/mysql --timeout=300s

# Order matters: users on source -> replica follows from an empty GTID set -> data.
bootstrap: users replication sakila

users:
	./scripts/create-users.sh

replication:
	./scripts/setup-replication.sh

sakila:
	./scripts/load-sakila.sh

storage:
	kubectl apply -f k8s/30-seaweedfs.yaml
	$(K) rollout status deployment/seaweedfs --timeout=180s
	$(K) delete job create-bucket --ignore-not-found
	kubectl apply -f k8s/31-create-bucket-job.yaml
	$(K) wait --for=condition=complete job/create-bucket --timeout=180s

backups:
	kubectl apply -f k8s/50-snapshot-cronjob.yaml -f k8s/60-binlog-archiver.yaml

## --- Load generation ----------------------------------------------------------

load-config:
	$(K) create configmap rental-generator-config \
	  --from-file=redpanda-connect/rental-generator.yaml \
	  --dry-run=client -o yaml | kubectl apply -f -
	kubectl apply -f k8s/40-redpanda-connect.yaml

load-start:
	$(K) scale deployment/rental-generator --replicas=1

load-stop:
	$(K) scale deployment/rental-generator --replicas=0

## --- Operate ------------------------------------------------------------------

status:
	./scripts/status.sh

verify:
	./scripts/verify.sh

snapshot-now:
	$(K) create job --from=cronjob/mysql-snapshot snapshot-manual-$$(date +%s)

## --- Recover ------------------------------------------------------------------

restore:
	@test -n "$(SNAPSHOT)" || (echo "Usage: make restore SNAPSHOT=snapshots/<timestamp>"; exit 1)
	$(K) delete pod mysql-restore --ignore-not-found
	kubectl apply -f k8s/70-restore-target.yaml
	$(K) wait --for=condition=ready pod/mysql-restore --timeout=180s
	$(K) delete job restore-snapshot --ignore-not-found
	sed 's|__SNAPSHOT__|$(SNAPSHOT)|' k8s/71-restore-snapshot-job.yaml | kubectl apply -f -
	$(K) wait --for=condition=complete job/restore-snapshot --timeout=1800s
	$(K) logs job/restore-snapshot

pitr:
	@test -n "$(STOP)" || (echo "Usage: make pitr STOP='YYYY-MM-DD HH:MM:SS' (UTC; run 'make restore' first)"; exit 1)
	$(K) delete job pitr-replay --ignore-not-found
	sed 's|__STOP_DATETIME__|$(STOP)|' k8s/72-pitr-replay-job.yaml | kubectl apply -f -
	$(K) wait --for=condition=complete job/pitr-replay --timeout=1800s
	$(K) logs job/pitr-replay -c replay

## --- Cleanup ------------------------------------------------------------------

clean:
	kubectl delete namespace $(NS) --ignore-not-found

destroy:
	kind delete cluster --name mysql-lab
