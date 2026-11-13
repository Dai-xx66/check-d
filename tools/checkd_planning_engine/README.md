# CheckD offline planning prototype

Python 3.11+, standard library only. This isolated prototype never connects to CheckD, Supabase, or WorkBuddy.

Run tests:

```sh
PYTHONPATH=src python3 -m unittest discover -s tests -v
```

Run the deterministic examples:

```sh
PYTHONPATH=src python3 examples/demo.py
```

Course input must be occurrences already resolved by Flutter's `buildCourseOccurrencesForDate`; this package does not reproduce semester, odd/even week, cancellation, makeup, or rescheduling rules. Date-only deadlines are inclusive local dates, represented internally as the following local midnight boundary only for calculation; no data is persisted. The EDF slot allocator is deterministic but heuristic: `feasible=false` means it failed to find a plan, not that infeasibility is mathematically proven.

`IsolatedStore` is a local prototype. Its `verified=True` flag is only a test seam and is not authentication. Production must inject a principal from a validated CheckD OAuth session, never from tool arguments. User IDs partition private data and event idempotency. No user data is stored in shared global memory.
