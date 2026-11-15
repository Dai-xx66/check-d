#!/usr/bin/env bash
set -euo pipefail

container=supabase_db_checkd-planning-sync-validation
result_dir="$(mktemp -d)"
cleanup() {
  docker exec "$container" psql -U postgres -d postgres -v ON_ERROR_STOP=1 -q -c \
    "delete from auth.users where id='80000000-0000-4000-8000-000000000001'" >/dev/null
  rm -rf "$result_dir"
}
trap cleanup EXIT

docker exec -i "$container" psql -U postgres -d postgres -v ON_ERROR_STOP=1 -q \
  < "$(dirname "$0")/prepare_concurrent_apply.sql"

for worker in 1 2; do
  (
    docker exec -i "$container" psql -U postgres -d postgres -v ON_ERROR_STOP=1 -Atq <<'SQL' > "$result_dir/worker-$worker.txt"
begin;
set local role authenticated;
select set_config('request.jwt.claim.sub','80000000-0000-4000-8000-000000000001',true);
select set_config('request.jwt.claims','{"sub":"80000000-0000-4000-8000-000000000001","role":"authenticated"}',true);
select pg_catalog.pg_sleep(0.2);
select public.apply_approved_plan(
  '83000000-0000-4000-8000-000000000001',
  '84000000-0000-4000-8000-000000000001',
  'concurrent-key'
);
commit;
SQL
  ) &
done
wait

python3 - "$result_dir" <<'PY'
import pathlib, sys
directory = pathlib.Path(sys.argv[1])
results = []
for n in (1, 2):
    lines = (directory / f"worker-{n}.txt").read_text().splitlines()
    results.append(next(line for line in lines if '"plan_version_id"' in line))
if results[0] != results[1]:
    raise SystemExit("concurrent idempotent applies returned different results")
if '"readback_verified": true' not in results[0] and '"readback_verified":true' not in results[0]:
    raise SystemExit("apply response did not verify readback")
PY

count=$(docker exec "$container" psql -U postgres -d postgres -Atq -c \
  "select count(*) from public.task_time_blocks where user_id='80000000-0000-4000-8000-000000000001'")
[[ "$count" == "1" ]]
echo "PASS: two concurrent same-key applies produced one business block and one stored result"
