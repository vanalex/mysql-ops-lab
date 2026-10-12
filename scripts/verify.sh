#!/usr/bin/env bash
# Compares row counts and CHECKSUM TABLE between two servers.
# Stop the load first (`make load-stop`) and let the replica catch up,
# otherwise the source keeps moving and results will differ.
# Usage: verify.sh [podA] [podB]   (defaults: mysql-0 mysql-1)
source "$(dirname "$0")/lib.sh"
A="${1:-mysql-0}"; B="${2:-mysql-1}"
TABLES="actor address category city country customer film film_actor film_category film_text inventory language payment rental staff store"

rc=0
for t in $TABLES; do
  a=$(mysql_exec "$A" -N -e "CHECKSUM TABLE sakila.$t" | cut -f2)
  b=$(mysql_exec "$B" -N -e "CHECKSUM TABLE sakila.$t" | cut -f2)
  if [ "$a" = "$b" ]; then echo "OK    $t"; else echo "DIFF  $t ($A=$a $B=$b)"; rc=1; fi
done
exit $rc
# TODO: try pt-table-checksum, which works while writes continue
