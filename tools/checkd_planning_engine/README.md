# CheckD offline planning prototype

Python 3.11+, standard library only. This isolated prototype never connects to CheckD, Supabase, or WorkBuddy.

Run tests:

```sh
PYTHONPATH=src python3 -m unittest discover -s tests -v
```

Run the deterministic examples:

```sh
PYTHONPATH=src python3 examples/demo.py
PYTHONPATH=src python3 examples/system_walkthrough.py
PYTHONPATH=src python3 examples/trusted_snapshot_walkthrough.py
```

Run the Drift snapshot JSON runner from the Flutter repository root:

```sh
python3 tools/checkd_planning_engine/examples/run_snapshot.py < snapshot.json
```

`PlanningService` is a transport-neutral read-only service boundary for preview, feasibility, delay, comparison, and risk. Its authenticator is injected; tests use a fake principal only. Responses always set `execution_eligible=false`. It is not an HTTP/MCP server and the test authenticator is not production authentication.

`TrustedSnapshotStore` is an isolated SQLite model for a server-owned cloud snapshot revision, per-device local/upload/download watermarks, provisional-vs-current results, TTL-bound proposals, one-time approval, idempotent apply, and readback-only recovery. The apply transaction is atomic inside this local test database; it does not call CheckD or Supabase. A pending local edit or a cloud revision not acknowledged by the device permits display of a provisional suggestion but blocks proposal creation. A concurrent server version change supersedes the proposal before any business write.

`remote_mcp.py` is a loopback-only Streamable HTTP protocol/authentication skeleton exposing read-only planning tools. Its `TestJwtAuthority` is only a local test issuer; `IntrospectionTokenVerifier` is an injected boundary, not a completed OAuth server or Supabase identity binding. The remote endpoint is not WorkBuddy-tested or deployable as-is: the authorization-code flow, OAuth metadata/registration, CheckD Auth consent and revocation, production token verification/introspection, TLS/hosting, and tenant/Connector approval remain blocked. It never accepts `user_id` from tool arguments and it has no write or approval tool.

The Flutter app's **Smart Planning Preview** page can call a separate developer-only bridge, `local_preview_http.py`. It runs on the developer machine, binds to `127.0.0.1`, requires a temporary local bearer guard, accepts only a submitted read-only Drift snapshot, and offers preview/delay/risk computation without persistence or writes. Start it from the repository root:

```sh
cd tools/checkd_planning_engine
export CHECKD_PLANNING_PREVIEW_TOKEN='<generate a random local-only value of at least 24 characters>'
PYTHONPATH=src python3 -m checkd_planning_engine.local_preview_http --port 8765
```

In another terminal at the repository root, export the same token and run the desktop development app with local build defines (do not commit them):

```sh
cd <repository-root>
flutter run -d macos \
  --dart-define=CHECKD_PLANNING_PREVIEW_URL=http://127.0.0.1:8765 \
  --dart-define=CHECKD_PLANNING_PREVIEW_TOKEN="$CHECKD_PLANNING_PREVIEW_TOKEN"
```

The bridge is intentionally not configured in ordinary builds. Mobile devices cannot reach the developer's loopback by default; use a separately reviewed TLS/tunnel setup before attempting a device run. Temporary work estimates/deadlines entered in the preview page affect only that computation and are never persisted. This bridge is a local integration test path, not a production planning service or identity boundary.

Course input must be occurrences already resolved by Flutter's `buildCalendarOccurrencesForDate`; this package does not reproduce semester, odd/even week, cancellation, makeup, or rescheduling rules. Date-only deadlines are inclusive local dates, represented internally as the following local midnight boundary only for calculation; no data is persisted. The EDF slot allocator is deterministic but heuristic: `no_solution_found` means the heuristic did not find a plan, not that infeasibility is mathematically proven. Property-style seeded tests and a small exhaustive EDF oracle are included, but do not establish global optimality.

`IsolatedStore` is an earlier local prototype. Its `verified=True` flag is only a test seam and is not authentication. `PlanningWorkflowStore` adds local SQLite leases/retries, user-scoped workspaces/idempotency, risk lifecycle and pending notification records, and a one-time approval state machine. `LocalTestPrincipal` is also only a local test seam; neither module is a production multi-user service or cross-device event database. Production must inject a principal derived from validated/revocable CheckD authorization, never from tool arguments. No user data is stored in shared global memory.

The local approval prototype never performs CheckD business writes. Its `begin_apply` consumes the local approval and enters `applying`; `finish_apply` models an authoritative readback result and transitions to `applied`, `readback_pending`, or terminal `failed`. `reconcile_readback` only performs readback/state convergence and never re-applies business changes. Any future cloud implementation still needs an atomic server-side version compare, durable one-time approval, real allowlisted writes, and authoritative readback.
