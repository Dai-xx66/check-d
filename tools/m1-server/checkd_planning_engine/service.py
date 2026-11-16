"""Local-only structured planning service boundary.

Authentication is injected. The bundled tests use a fake authenticator and
must not be interpreted as OAuth, WorkBuddy SSO, or production authorization.
"""
from __future__ import annotations

from dataclasses import asdict, dataclass
from datetime import date, datetime
from typing import Any, Callable

from .engine import calculate_slack, compare_proposals, generate_schedule, simulate_delay
from .importer import Snapshot, import_snapshot
from .risk import evaluate_risks


@dataclass(frozen=True)
class ServiceError:
    code: str
    message: str
    retryable: bool = False
    details: dict[str, Any] | None = None

    def to_json(self) -> dict[str, Any]:
        return {"code": self.code, "message": self.message,
                "retryable": self.retryable, "details": self.details or {}}


class PlanningService:
    """A transport-neutral API for preview, feasibility, delay, compare, risk."""

    def __init__(self, authenticate: Callable[[object], str]):
        self._authenticate = authenticate

    def handle(self, request: dict[str, Any], auth_context: object | None) -> dict[str, Any]:
        try:
            subject = self._authenticate(auth_context)
            if not isinstance(subject, str) or not subject.strip():
                raise PermissionError("verified principal required")
        except Exception:
            return {"ok": False, "error": ServiceError(
                "AUTH_REQUIRED", "需要有效的 CheckD 用户身份。"
            ).to_json()}

        try:
            if not isinstance(request, dict) or "user_id" in request:
                raise ValueError("request must be an object and cannot contain user_id")
            payload = request.get("snapshot")
            if not isinstance(payload, dict):
                raise ValueError("snapshot object required")
            snapshot_payload = dict(payload)
            if snapshot_payload.get("subject_ref") != subject:
                raise PermissionError("snapshot principal mismatch")
            snapshot = import_snapshot(snapshot_payload)
            expected = request.get("expected_version")
            if expected is not None and expected != snapshot.version:
                return self._error("SNAPSHOT_STALE", "数据版本已变化，请重新读取并生成方案。",
                                   details={"current_version": snapshot.version})
            operation = request.get("operation", "preview")
            if operation not in {"preview", "feasibility", "delay", "compare", "risk"}:
                raise ValueError("unsupported operation")
            result = generate_schedule(snapshot.planning_input)
            unmodeled_recurring = snapshot_payload.get(
                "unmodeled_recurring_occurrence_ids", []
            )
            if not isinstance(unmodeled_recurring, list):
                raise ValueError("unmodeled recurring occurrence list required")
            analysis = self._analysis_outcome(snapshot, result, unmodeled_recurring)
            response: dict[str, Any] = {
                "ok": True,
                "subject_ref": subject,
                "snapshot_version": snapshot.version,
                "snapshot_digest": snapshot.digest,
                "captured_at": snapshot.captured_at.isoformat(),
                "sync_state": snapshot.sync_state,
                "provisional": snapshot.provisional,
                "execution_eligible": False,
                "operation": operation,
                "outcome": analysis,
                "schedule": asdict(result),
                "missing_data": {
                    "unknown_effort_task_ids": list(snapshot.unknown_effort_task_ids),
                    "missing_deadline_task_ids": list(snapshot.missing_deadline_task_ids),
                    "existing_plan_needing_effort_task_ids": list(snapshot.existing_plan_needing_effort_task_ids),
                    "unmodeled_recurring_occurrence_ids": unmodeled_recurring,
                },
                "optimality_proven": False,
            }
            if operation == "delay":
                delay = request.get("delay")
                if not isinstance(delay, dict) or not isinstance(delay.get("task_id"), str):
                    raise ValueError("delay.task_id and delay.until are required")
                until = self._instant(delay.get("until"))
                response["delay_analysis"] = simulate_delay(
                    snapshot.planning_input, delay["task_id"], until
                )
            elif operation == "compare":
                delay = request.get("delay")
                if not isinstance(delay, dict) or not isinstance(delay.get("task_id"), str):
                    raise ValueError("compare requires delay.task_id and delay.until")
                alternative = simulate_delay(
                    snapshot.planning_input,
                    delay["task_id"],
                    self._instant(delay.get("until")),
                )["after"]
                from .engine import ScheduleResult
                response["comparison"] = compare_proposals(
                    result,
                    ScheduleResult(**alternative),
                )
            elif operation == "risk":
                tasks_by_id = {row["task_id"]: row for row in snapshot_payload["tasks"]}
                schedulable = {task.task_id: task for task in snapshot.planning_input.tasks}
                risk_inputs = []
                for task_id, row in tasks_by_id.items():
                    task = schedulable.get(task_id)
                    slack = calculate_slack(snapshot.planning_input, task) if task else {}
                    deadline = (
                        date.fromisoformat(row["deadline_date"])
                        if row.get("deadline_date") else
                        self._instant(row["deadline_at"]) if row.get("deadline_at") else None
                    )
                    risk_inputs.append({
                        "task_id": task_id,
                        "deadline": task.deadline if task else deadline,
                        "planned_at": self._instant(row["planned_at"]) if row.get("planned_at") else None,
                        "completed": row.get("completion_status") == "completed",
                        # Unknown remaining effort stays unknown; zero would
                        # incorrectly suppress capacity risk for unmodeled tasks.
                        "remaining_seconds": task.remaining_seconds if task else row.get("remaining_seconds"),
                        **slack,
                    })
                response["risks"] = evaluate_risks(
                    risk_inputs, evaluated_at=snapshot.planning_input.now
                )
                response["risk_status"] = (
                    "unknown_due_to_missing_data"
                    if self._analysis_outcome(snapshot, result, unmodeled_recurring)
                    == "unknown_due_to_missing_data"
                    else "complete_for_snapshot"
                )
            return response
        except PermissionError:
            return self._error("NOT_FOUND", "未找到可访问的规划数据。")
        except (KeyError, TypeError, ValueError, OverflowError) as error:
            return self._error("INVALID_INPUT", "规划请求或快照结构无效。",
                               details={"validation_error": type(error).__name__})

    @staticmethod
    def _analysis_outcome(snapshot: Snapshot, result: object, unmodeled_recurring: list) -> str:
        missing = (snapshot.unknown_effort_task_ids or snapshot.missing_deadline_task_ids
                   or snapshot.existing_plan_needing_effort_task_ids
                   or unmodeled_recurring)
        if missing:
            return "unknown_due_to_missing_data"
        return "found_feasible" if getattr(result, "feasible", False) else "no_solution_found"

    @staticmethod
    def _instant(value: object) -> datetime:
        if not isinstance(value, str):
            raise ValueError("timestamp string required")
        parsed = datetime.fromisoformat(value.replace("Z", "+00:00"))
        if parsed.tzinfo is None or parsed.utcoffset() is None:
            raise ValueError("timestamp must include UTC offset")
        return parsed

    @staticmethod
    def _error(code: str, message: str, *, details: dict[str, Any] | None = None) -> dict[str, Any]:
        outcome = "invalid_input" if code == "INVALID_INPUT" else None
        return {"ok": False, **({"outcome": outcome} if outcome else {}),
                "error": ServiceError(code, message, False, details).to_json()}
