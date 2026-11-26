#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""REAL-READ 适配层：读 M0 账号**已同步到 Supabase 的**真实任务与课程。

这是隔离开发件，不是已上线能力。读它之前先看这五条边界，每一条都有具体原因：

## 1. 不接受调用方传 `user_id`

用户隔离由 Postgres 的行级安全策略（RLS）里 `auth.uid() = user_id` 决定，不由本模块决定。
一旦允许调用方指定 user_id，隔离就变成「调用方自觉」，而 M0 2026-11-09T10:51 的硬要求是
「必须在服务端实施访问控制，不得仅靠调用方或提示词」。所以 `user_id` 不在任何入参里，
查询也不带 `user_id=eq.` 条件 —— 让 RLS 独自决定能看见哪些行。

**代价（必须知情）**：如果部署时用错了密钥（比如换了 service_role），RLS 会被绕过，
本模块**自身察觉不到**。防线在密钥选择上，不在代码里。这条已写进 M0 操作清单。

## 2. 显式列白名单，不用 `select=*`

返回的列是逐字段列出的常量（`TASK_COLUMNS` / `COURSE_COLUMNS`）。
理由有两条：
- `*` 会把 `notes`、`teacher`、`classroom`、`color`、`user_id` 一并带出来，
  这些字段对排期没用，却都是个人隐私或内部标识；
- 列一变多，前端和验收方都察觉不到，问题只能在事后发现。

M0 2026-11-09T14:08 原文要求「最小字段白名单」，这是它的实现。

## 3. `deleted_at is null` 恒带

真实表都是软删除。漏这个条件会把用户已经删掉的任务读回来，
演示时表现为「我明明删了，Agent 还给我排」——比功能缺失更难看。

## 4. 空集不回落 MOCK（红线）

查到 0 条就是 0 条，返回空数组 + `source="real"`。
**绝不**「因为没数据就换一批假数据顶上」。那样验收方看到的是假通过，
而且是最难发现的一类假：数据看起来完全正常。

## 5. `source` / `as_of` / `data_window` 恒带

M0 2026-11-09T10:51 要求「本阶段必须清晰区分 REAL-READ / MOCK-SCHEDULE / REAL-WRITE」。
`source="real"` 让验收方不必靠域名去猜。
`as_of` 是**本进程读到数据的那一刻**，不是数据本身的修改时间；
`data_window` 是本次查询的时间窗。两者都不是装饰，缺了就无法判断证据是否过期。

## 本模块不做什么

- **不做课程周次展开**（把 `week_rule_type` + `start_week` 展开成具体日期）。
  那是 M2 的模块（M0 2026-11-09T14:08 派工原文：M2「独立负责」课程周次展开）。
  本模块只把规则**原样取出并规范化**，`events` 恒为空数组并带
  `events_unavailable_reason`，展开由调用方组合。
- **不做 Task/Course → Agent 结构 的语义转换。** 同样归 M2。
  本模块输出的是「已做字段白名单与枚举规范化、但仍贴近真实 schema」的结构：
  例如 `deadline` 是 `{"kind":"exact"|"date_only"|"none"}` 的显式形状，
  而 MOCK 用的是同一形状 —— 这一层是对齐的，所以接入方不用为截止时间写两套判断。
  差异之处（如 `duration_target_seconds` 真实可能为 null）**如实保留，不补齐**。
- 不做排程、不做写入、不做缓存、不做重试。
- 不把真实数据伪装成 MOCK：`source` 字段恒为 `real`，且不需要调用方推断。
"""

import json
import re
import urllib.error
import urllib.parse
import urllib.request
from datetime import datetime, timezone


# --------------------------------------------------------------------------
# 列白名单
# --------------------------------------------------------------------------
# 每一列都对应一个具体用途，没有「先留着以后可能用」的列。
# 改这里等于改对外契约，改之前想清楚验收方是否知情。

TASK_COLUMNS = ("id", "name", "type", "status", "updated_at")

# 截止时间在这里。注意：`due_date` / `due_at` 不在 `tasks` 表上，
# 而在 `one_time_reminders` 上（migration `202609150001` §add column）。
# 这是最容易写错的一处，写错的表现是「截止时间永远为空」而不是报错。
TASK_REMINDER_COLUMNS = ("task_id", "available_from", "planned_date",
                         "due_date", "due_at")

TASK_LONG_TERM_COLUMNS = ("task_id", "check_mode", "target_duration_seconds")

TASK_SCHEDULE_COLUMNS = ("task_id", "schedule_type", "weekdays",
                         "starts_on", "ends_on")

COURSE_COLUMNS = ("id", "name", "status", "semester", "updated_at")

COURSE_RULE_COLUMNS = ("id", "course_id", "weekday", "week_rule_type",
                       "start_week", "end_week", "interval_weeks",
                       "week_numbers", "starts_at_minute", "ends_at_minute")

# 单日例外（临时停课、调课、挪到别的时间）。
# 只取排期需要的列：`temporary_classroom` 与 `reminder_minute_of_day` 对排期无用，
# 属个人信息，不取；`notes` 是用户随手写的，更不取。
OVERRIDE_COLUMNS = ("id", "item_type", "item_id", "local_date", "action",
                    "planned_start_minute", "planned_end_minute")

# 学期锚点（migration `202609100001` stage_14 L49）。
# M0 2026-11-10T02:04 亲自在 App「编辑学期」页核到：大二上学期 / 首周 2026-08-31 /
# 总周数 18 / 已设为当前学期。所以**这不是缺失设计**，读不到只能是读取链路没闭合。
# 他的要求：不可写死 2026-08-31、不可凭当前星期猜、不可新建重复学期表；
# 云端缺记录或当前学期无法确定时 fail-closed，blocked 上报。
SEMESTER_COLUMNS = ("id", "name", "first_week_start_date", "total_weeks",
                    "schedule_template_id", "is_current", "updated_at")


# --------------------------------------------------------------------------
# 枚举转换
# --------------------------------------------------------------------------
# 真实库与 MOCK 的命名风格不同，必须显式转换，不能靠字符串相似碰运气。
#
#   tasks.type       long_term / one_time        →  MOCK kind: recurring / one_time
#   week_rule_type   everyWeek / oddWeeks …      →  MOCK: every_week / odd_weeks …
#
# `custom` 两侧同名。遇到未知值**不静默兜底**：抛错比猜一个更安全，
# 因为猜错的结果是排出一份看起来正常、实际错误的课表。

TASK_KIND_BY_TYPE = {"one_time": "one_time", "long_term": "recurring"}

WEEK_RULE_BY_DB = {
    "everyWeek": "every_week",
    "oddWeeks": "odd_weeks",
    "evenWeeks": "even_weeks",
    "everyNWeeks": "every_n_weeks",
    "custom": "custom",
}

# 单日例外的 `item_type`：库里是 `oneTime`，MOCK 风格是 `one_time`。
# 同一个坑在 `week_rule_type` 上也有一份 —— 真实 schema 用 camelCase，
# 工具层用 snake_case。**统一在这里转，下游不要转第二次。**
# 两处都不做「未知值兜底」：静默放过一个没见过的枚举，等于把错误往后推一层。
ITEM_TYPE_BY_DB = {
    "oneTime": "one_time",
    "recurring": "recurring",
    "course": "course",
}


class RealReadError(Exception):
    """REAL 读取失败。code 限定在契约 21 码闭集内，不新增码。"""

    def __init__(self, code, message, details=None):
        super().__init__(message)
        self.code = code
        self.message = message
        self.details = details or []


# --------------------------------------------------------------------------
# 传输层（可注入，便于在没有任何真实凭证的情况下跑测试）
# --------------------------------------------------------------------------

_BEARER_RE = re.compile(r"(Bearer\s+)[A-Za-z0-9._\-]+", re.I)


def _scrub(value, limit=200):
    """把异常文本压成一句可上报的原因，并擦掉任何 Bearer 令牌。

    上报出去的东西会被贴进邮件和群聊，所以宁短勿全、宁擦勿露。
    """
    text = str(value)
    text = _BEARER_RE.sub(r"\1<redacted>", text)
    return text[:limit]


def urllib_transport(url, headers, timeout):
    """默认传输：返回 (http_status, body_bytes)。

    只做一次请求，不重试。重试属于调用策略，塞进来会让超时语义变模糊。
    """
    req = urllib.request.Request(url, headers=headers, method="GET")
    try:
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            return resp.status, resp.read()
    except urllib.error.HTTPError as exc:
        return exc.code, exc.read()
    except Exception as exc:                       # 连接失败/超时/DNS
        # 2026-11-10 M0 报「URLError / HTTP 0」后补：只报异常类名不够用——
        # `URLError` 背后可能是 DNS 解析失败、出口被拦、TLS 握手失败，处置完全不同。
        # 这里带上一句底层原因（截断），**不含令牌**：令牌在请求头里，不进异常文本，
        # 仍然做一次 Bearer 擦除兜底。
        raise RealReadError(
            "DEPENDENCY_UNAVAILABLE",
            "无法连接数据源。",
            [{"field": "transport",
              "reason": type(exc).__name__,
              "detail": _scrub(getattr(exc, "reason", exc))}],
        )


class SupabaseReader:
    """PostgREST 只读客户端。只实现 select，没有写入通道。

    **没有写方法不是遗漏**：REAL-WRITE 需要 M0 另行授权（C 阶段），
    这里连代码路径都不留，避免哪天被误调用。
    """

    def __init__(self, base_url, anon_key, access_token, timeout=10, transport=None):
        if not base_url or not anon_key:
            raise RealReadError("DEPENDENCY_UNAVAILABLE",
                                "REAL 数据源未配置（缺 base_url 或 anon key）。")
        if not access_token:
            # 这不是配置错误，是运行态过期：access_token 约 1 小时失效。
            # 报 503 会让运维误以为服务挂了；这里给 401，语义是「要重新授权」。
            raise RealReadError("AUTH_REQUIRED",
                                "缺少用户级访问令牌（短期授权可能已过期）。")
        self.base_url = base_url.rstrip("/")
        self.anon_key = anon_key
        self.access_token = access_token
        self.timeout = timeout
        self._transport = transport or urllib_transport

    def select(self, table, columns, filters=None, order=None):
        """读一张表。filters 是 PostgREST 语法片段列表，例如 ["deleted_at=is.null"]。"""
        params = [("select", ",".join(columns))]
        for f in (filters or []):
            k, _, v = f.partition("=")
            params.append((k, v))
        if order:
            params.append(("order", order))
        url = "%s/rest/v1/%s?%s" % (self.base_url, table,
                                    urllib.parse.urlencode(params))

        headers = {
            "apikey": self.anon_key,
            # 用用户级 JWT，不是 service_role。RLS 靠它识别 auth.uid()。
            "Authorization": "Bearer " + self.access_token,
            "Accept": "application/json",
            # 让 PostgREST 返回精确条数对不上时不要 416，演示场景不需要 count。
            "Prefer": "return=representation",
        }
        status, raw = self._transport(url, headers, self.timeout)

        if status in (401, 403):
            # 403 在 RLS 语境下通常是「策略拒绝」或「JWT 角色不是 authenticated」。
            # 两者都归到 AUTH_REQUIRED/FORBIDDEN，不暴露数据库原文。
            code = "AUTH_REQUIRED" if status == 401 else "FORBIDDEN"
            raise RealReadError(code, "数据源拒绝了本次读取（令牌无效或无权访问）。",
                                [{"field": "table", "reason": table}])
        if status == 404:
            # 表不存在通常意味着「连到了别的项目」或 migration 未执行。
            raise RealReadError("DEPENDENCY_UNAVAILABLE", "数据源缺少目标表。",
                                [{"field": "table", "reason": table}])
        if status >= 500:
            raise RealReadError("DEPENDENCY_UNAVAILABLE", "数据源异常。",
                                [{"field": "table", "reason": str(status)}])
        if status >= 400:
            raise RealReadError("DEPENDENCY_UNAVAILABLE", "数据源返回未预期的状态。",
                                [{"field": "table", "reason": str(status)}])

        try:
            rows = json.loads(raw.decode("utf-8"))
        except Exception:
            raise RealReadError("INTERNAL_ERROR", "数据源返回的不是合法 JSON。",
                                [{"field": "table", "reason": table}])
        if not isinstance(rows, list):
            raise RealReadError("INTERNAL_ERROR", "数据源返回结构不是数组。",
                                [{"field": "table", "reason": table}])
        return rows


# --------------------------------------------------------------------------
# 规范化（不改变语义，只处理「数据库有、JSON 不好表达」的三处）
# --------------------------------------------------------------------------

def _iso(value):
    """timestamptz → ISO 8601 带偏移。已是字符串就原样。"""
    if value is None:
        return None
    if isinstance(value, str):
        return value
    return value.isoformat()


def _date(value):
    """date → 'YYYY-MM-DD'。

    **不补时间**。`due_date` 的语义是「那一天的截止」，由 migration
    `202609150001` 的注释原文确定：「Date-only deadline … no synthetic end-of-day time」。
    补 23:59:59 会把「按天算」变成「按秒算」，排程结果随之改变。
    """
    if value is None:
        return None
    if isinstance(value, str):
        return value
    return value.isoformat()[:10]


def _deadline_of(reminder):
    """把 `due_date` / `due_at` 两列收敛成一个显式结构。

    库里已有 `num_nonnulls(due_date, due_at) <= 1` 约束，但这里仍然判断两者共存的情况：
    约束是 `not valid` 加的（历史行未回填校验），不能假设运行时一定成立。
    真的同时出现时，**优先 due_at**（更精确），并在 details 里留痕，不静默择一。
    """
    if not reminder:
        return {"kind": "none"}, None
    due_at = reminder.get("due_at")
    due_date = reminder.get("due_date")
    if due_at and due_date:
        return ({"kind": "exact", "at": _iso(due_at)},
                "due_date 与 due_at 同时存在，按约定取 due_at；库约束为 not valid，历史行可能违反")
    if due_at:
        return {"kind": "exact", "at": _iso(due_at)}, None
    if due_date:
        return {"kind": "date_only", "date": _date(due_date)}, None
    return {"kind": "none"}, None


def _week_rule(value):
    if value is None:
        return None
    mapped = WEEK_RULE_BY_DB.get(value)
    if mapped is None:
        # 不猜。未知枚举值意味着 schema 变了而本模块没跟上，报错比排出错课表好。
        raise RealReadError(
            "INTERNAL_ERROR",
            "课程周次规则出现未知取值，拒绝猜测。",
            [{"field": "week_rule_type", "reason": value}],
        )
    return mapped


def _group_by(rows, key):
    out = {}
    for r in rows:
        out.setdefault(r.get(key), []).append(r)
    return out


# --------------------------------------------------------------------------
# 窗口判定（契约 §6.1「date_range：实际查询范围」）
# --------------------------------------------------------------------------
#
# 背景：2026-11-10 M3 复核指出 `start`/`end` 只被写进 `data_window` 回显、
# 从未参与筛选（原 L354 过滤只有 deleted_at/status 两个条件）。M0 同日裁定
# 「口径乙：严格筛选，但逾期任务必须单列」。
#
# 三个类别各有独立语义，不可合并：
#   in_window     落在查询窗口内，可被引擎排入未来时段
#   overdue       截止日已过且仍未完成 —— 必须返回给用户看，但**绝不可**排进未来
#   undated       没有任何日期约束 —— 随时可排，丢弃它等于静默漏排
# 窗口外且未逾期的（未来才到期）不返回，这是「窗口真生效」的唯一体现。

WINDOW_IN = "in_window"
WINDOW_OVERDUE = "overdue"
WINDOW_UNDATED = "undated"
WINDOW_OUT = "out_of_window"


def _task_dates(task):
    """取任务的 (计划日, 截止日)，都是 'YYYY-MM-DD' 或 None。

    一次性任务的日期在 `one_time_reminders` 上，不在 `tasks` 上；循环任务没有
    单点日期，只有 recurrence 的起止。两者不能混用同一个字段名。
    """
    planned = task.get("planned_date")
    dl = task.get("deadline") or {}
    kind = dl.get("kind")
    if kind == "date_only":
        due = dl.get("date")
    elif kind == "exact":
        # 带时刻的字符串取日期部分按天比，与 `_date` 的「不补时间」口径一致。
        due = (dl.get("at") or "")[:10] or None
    else:
        due = None
    return planned, due


def _classify_task(task, start, end, today):
    """判定一个 Task 属于哪个窗口类别，返回 (status, reason)。

    `reason` 是给人看的一句话，会被原样放进响应，所以写中文、不带行话。
    """
    if task.get("kind") == "recurring":
        rec = task.get("recurrence") or {}
        s, e = rec.get("starts_on"), rec.get("ends_on")
        # 循环规则与窗口有没有交集；ends_on 为空表示一直持续。
        if (not s or s <= end) and (not e or e >= start):
            return WINDOW_IN, "循环规则覆盖查询窗口"
        if e and e < start and e < today:
            return WINDOW_OVERDUE, "循环规则在 %s 已结束，且早于今天" % e
        return WINDOW_OUT, "循环规则不覆盖查询窗口"

    planned, due = _task_dates(task)

    if not planned and not due:
        return WINDOW_UNDATED, "未设置计划日与截止日，无法判断落在哪个时段"

    # 逾期优先于窗口：逾期任务必须单独可见，不能被"窗口外"悄悄吃掉。
    for d, label in ((due, "截止日"), (planned, "计划日")):
        if d and d < today and d < start:
            return WINDOW_OVERDUE, "%s %s 已过期，不再排入未来时段" % (label, d)

    for d, label in ((planned, "计划日"), (due, "截止日")):
        if d and start <= d <= end:
            return WINDOW_IN, "%s %s 落在查询窗口内" % (label, d)

    return WINDOW_OUT, "计划日与截止日都在查询窗口之外"



# --------------------------------------------------------------------------
# 对外接口
# --------------------------------------------------------------------------

class RealRead:
    """REAL-READ 的两个只读工具实现。

    只做「取 + 规范化」。课程周次展开留给 M2 的模块，这里不重复实现，
    避免两个模块各自展开、结果不一致 —— 那种不一致在演示现场极难解释。
    """

    def __init__(self, reader):
        self.reader = reader

    # -- list_tasks --------------------------------------------------------
    def list_tasks(self, start, end, kinds=None, statuses=None, today=None):
        kinds = kinds or ["recurring", "one_time"]
        statuses = statuses or ["active"]
        as_of = datetime.now(timezone.utc).isoformat()
        # 逾期判定基准。可注入，好让测试构造确定的负向场景（真实调用不传）。
        if today is None:
            today = datetime.now(timezone.utc).date().isoformat()
        elif hasattr(today, "isoformat"):
            today = today.isoformat()

        task_rows = self.reader.select(
            "tasks", TASK_COLUMNS,
            filters=["deleted_at=is.null", "status=in.(%s)" % ",".join(statuses)],
            order="updated_at.desc",
        )
        # 空集立刻返回，不再发后续三张表的请求。
        # 这既是省一次往返，也是把「空就是空」这件事写在最前面。
        if not task_rows:
            return self._tasks_payload([], start, end, as_of, [])

        ids = [r["id"] for r in task_rows]
        in_filter = "task_id=in.(%s)" % ",".join(ids)

        reminders = _group_by(self.reader.select(
            "one_time_reminders", TASK_REMINDER_COLUMNS,
            filters=[in_filter]), "task_id")
        long_terms = _group_by(self.reader.select(
            "long_term_tasks", TASK_LONG_TERM_COLUMNS,
            filters=[in_filter]), "task_id")
        # `task_schedules` **没有** `deleted_at` 列（migration 202609020001 建表时就没有，
        # 后续 202609100001 只加了 weekdays_mask）。这张表的删除靠外键 `on delete cascade` 硬删。
        # 带 `deleted_at=is.null` 会被 PostgREST 判 400（column does not exist），
        # 表现是整个 list_tasks 失败，而假 PostgREST 不校验列名，所以单测发现不了。
        schedules = _group_by(self.reader.select(
            "task_schedules", TASK_SCHEDULE_COLUMNS,
            filters=[in_filter]), "task_id")

        notes = []
        tasks = []
        for row in task_rows:
            kind = TASK_KIND_BY_TYPE.get(row.get("type"))
            if kind is None or kind not in kinds:
                continue
            reminder = (reminders.get(row["id"]) or [None])[0]
            deadline, warn = _deadline_of(reminder)
            if warn:
                notes.append({"task_id": row["id"], "note": warn})
            shaped = self._shape_task(
                row, kind, deadline, reminder,
                (long_terms.get(row["id"]) or [None])[0],
                schedules.get(row["id"]) or [],
            )
            shaped["window_status"], shaped["window_reason"] = _classify_task(
                shaped, start, end, today)
            tasks.append(shaped)
        # 只丢弃「窗口外且未逾期」这一类。逾期与未设日期都保留并单列 ——
        # 前者是用户最需要看到的东西，后者丢弃等于静默漏排（M0 2026-11-10 裁定原文）。
        kept = [t for t in tasks if t["window_status"] != WINDOW_OUT]
        return self._tasks_payload(kept, start, end, as_of, notes,
                                   excluded=len(tasks) - len(kept))

    def _shape_task(self, row, kind, deadline, reminder, long_term, schedules):
        duration = (long_term or {}).get("target_duration_seconds")
        task = {
            "task_id": row["id"],
            "kind": kind,
            "name": row.get("name"),
            "status": row.get("status"),
            "updated_at": _iso(row.get("updated_at")),
            "deadline": deadline,
            # 时长只认 `long_term_tasks.target_duration_seconds`。
            # 真实 schema 里没有「一次性任务的预计耗时」字段，
            # 所以这里**不估算、不补默认值** —— 字段不存在就不假造（M0 派工原文）。
            "duration_target_seconds": duration,
            # execution_mode 由「有没有时长目标」推导，不是库里的独立字段。
            "execution_mode": "timed" if duration is not None else "untimed",
        }
        if kind == "one_time":
            # 这两个字段只存在于 one_time_reminders，且只对一次性任务有意义。
            # recurring 任务给 None，不编一个空日期出来。
            task["available_from"] = _date((reminder or {}).get("available_from"))
            task["planned_date"] = _date((reminder or {}).get("planned_date"))
        if schedules:
            s = schedules[0]
            task["recurrence"] = {
                "preset": s.get("schedule_type"),
                "weekdays": s.get("weekdays") or [],
                "starts_on": _date(s.get("starts_on")),
                "ends_on": _date(s.get("ends_on")),
                # 真实表没有「每天固定几点做」这个字段（scheduled_minute_of_day 在 MOCK 才有），
                # 保持 None 而不是编一个值。
                "scheduled_minute_of_day": None,
            }
        return task

    def _tasks_payload(self, tasks, start, end, as_of, notes, excluded=0):
        by_status = {WINDOW_IN: 0, WINDOW_OVERDUE: 0, WINDOW_UNDATED: 0}
        for t in tasks:
            st = t.get("window_status")
            if st in by_status:
                by_status[st] += 1
        payload = {
            "source": "real",
            "as_of": as_of,
            "data_window": {"start": start, "end": end},
            # 明确写出窗口已生效。此前 `data_window` 只是回显，
            # 从响应上分辨不出「筛过」和「没筛」—— 这是那次缺陷能藏住的原因。
            "window_applied": True,
            "tasks": tasks,
            "task_count": len(tasks),
            # 三类分列。`in_window` 之外的两类不可被引擎排进未来时段：
            # `overdue` 已经过期，`undated` 没有时间依据。
            "window_counts": {
                "in_window": by_status[WINDOW_IN],
                "overdue": by_status[WINDOW_OVERDUE],
                "undated": by_status[WINDOW_UNDATED],
                "excluded_out_of_window": excluded,
            },
        }
        if notes:
            # 结构性异常不吞掉，但也不升级成错误：数据能读，只是有可疑之处。
            payload["warnings"] = notes
        return payload

    # -- get_calendar_events ----------------------------------------------
    def get_calendar_events(self, start, end, external_fixed_events=None):
        as_of = datetime.now(timezone.utc).isoformat()

        # 单日例外先读，且**不因为「没有课程」就跳过**：
        # 一个没录课程的用户照样可能给某个任务设了「今天不做」。
        # 早先的顺序是先查 courses、空了就直接 return，会把这类例外整片丢掉。
        overrides = self._read_overrides(start, end)

        # 学期锚点：M2 的周次展开要它，M0 2026-11-10T02:04 明确「由 M1 读取层送进去」。
        # 读不到不阻断整次调用（tasks 那部分仍然有效），但必须上报，不许静默给空数组。
        semesters, semester_blocked = self._read_semesters()

        course_rows = self.reader.select(
            "courses", COURSE_COLUMNS,
            filters=["deleted_at=is.null"], order="updated_at.desc")

        courses = []
        if course_rows:
            ids = [r["id"] for r in course_rows]
            rules = _group_by(self.reader.select(
                "course_schedule_rules", COURSE_RULE_COLUMNS,
                filters=["course_id=in.(%s)" % ",".join(ids),
                         "deleted_at=is.null"]), "course_id")
            for row in course_rows:
                courses.append({
                    "course_id": row["id"],
                    "name": row.get("name"),
                    "status": row.get("status"),
                    "semester": row.get("semester"),
                    "updated_at": _iso(row.get("updated_at")),
                    "rules": [self._shape_rule(r) for r in rules.get(row["id"], [])],
                })
        return self._events_payload(courses, [], overrides, start, end, as_of,
                                    semesters, semester_blocked)

    def _read_semesters(self):
        """读学期表并判定「当前学期锚点是否唯一且明确」。

        返回 `(semesters, blocked)`：
        - `semesters` 照原样给全（调用方可能要看全部学期，不只当前那个）
        - `blocked` 是 fail-closed 的上报出口，空数组表示锚点明确

        三种 blocked 情形（M2 2026-11-10T02:08 已在他的模块里定同样的码，两边一致）：
        没有学期记录 / 有记录但没有一条标记为当前 / 同时多条当前。

        **不猜**：不做「取 updated_at 最新的那条」这种兜底。猜错的后果是整学期课表错位。
        """
        rows = self.reader.select(
            "semesters", SEMESTER_COLUMNS,
            filters=["deleted_at=is.null"], order="updated_at.desc")

        out = []
        for r in rows:
            out.append({
                "semester_id": r["id"],
                "name": r.get("name"),
                "first_week_start_date": _date(r.get("first_week_start_date")),
                "total_weeks": r.get("total_weeks"),
                "schedule_template_id": r.get("schedule_template_id"),
                "is_current": bool(r.get("is_current")),
                "updated_at": _iso(r.get("updated_at")),
            })

        blocked = []
        current = [s for s in out if s["is_current"]]
        if not out:
            blocked.append({
                "code": "MISSING_SEMESTER_ANCHOR",
                "message": "云端没有学期记录（semesters 为空），无法确定学期首周。",
                "basis": {"table": "semesters", "rows": 0},
            })
        elif not current:
            blocked.append({
                "code": "MISSING_SEMESTER_ANCHOR",
                "message": "有 %d 条学期记录，但没有一条标记为当前学期。" % len(out),
                "basis": {"table": "semesters", "rows": len(out), "current_rows": 0},
            })
        elif len(current) > 1:
            blocked.append({
                "code": "MULTIPLE_CURRENT_SEMESTERS",
                "message": "同时有 %d 条当前学期，拒绝猜测取哪一条。" % len(current),
                "basis": {"table": "semesters", "rows": len(out),
                          "current_rows": len(current),
                          "current_ids": [s["semester_id"] for s in current]},
            })
        return out, blocked

    def _read_overrides(self, start, end):
        """读单日例外。**按查询窗口过滤**，不把整张历史拉下来。

        `daily_item_overrides` 会随时间无限增长（每天每项最多一条），
        不带日期条件地全量读，演示用的小账号没问题，真用起来就是性能陷阱。
        """
        rows = self.reader.select(
            "daily_item_overrides", OVERRIDE_COLUMNS,
            filters=["deleted_at=is.null",
                     "local_date=gte." + start,
                     "local_date=lte." + end])
        out = []
        for r in rows:
            item_type = ITEM_TYPE_BY_DB.get(r.get("item_type"))
            if item_type is None:
                raise RealReadError(
                    "INTERNAL_ERROR", "单日例外出现未知 item_type，拒绝猜测。",
                    [{"field": "item_type", "reason": r.get("item_type")}])
            out.append({
                "override_id": r["id"],
                "item_type": item_type,
                "item_id": r.get("item_id"),
                "local_date": _date(r.get("local_date")),
                "action": r.get("action"),
                "planned_start_minute": r.get("planned_start_minute"),
                "planned_end_minute": r.get("planned_end_minute"),
            })
        return out

    def _shape_rule(self, r):
        return {
            "rule_id": r["id"],
            "weekday": r.get("weekday"),
            "week_rule_type": _week_rule(r.get("week_rule_type")),
            "start_week": r.get("start_week"),
            "end_week": r.get("end_week"),
            "interval_weeks": r.get("interval_weeks"),
            "week_numbers": r.get("week_numbers") or [],
            "start_minute": r.get("starts_at_minute"),
            "end_minute": r.get("ends_at_minute"),
        }

    def _events_payload(self, courses, events, overrides, start, end, as_of,
                        semesters=None, semester_blocked=None):
        return {
            "source": "real",
            "as_of": as_of,
            "data_window": {"start": start, "end": end},
            # 学期锚点：M2 的 expand_course_rules 用第一周的日期把「第几周」落到具体日历日。
            # M0 2026-11-10T02:04 的原话是「由 M1 读取层把相应学期首周日期送到 M2」。
            # 这里给全量学期列表 + 明确的 blocked 出口，不替他挑。
            "semesters": semesters or [],
            "semester_blocked": semester_blocked or [],
            "courses": courses,
            # `events` 是「已展开成具体日期时段」的结果。本模块**不展开**，
            # 因此这里恒为空数组，而不是拿规则凑一个出来。
            # 展开由 M2 的模块提供，调用方组合后填入。
            "events": events,
            "events_unavailable_reason": "week_expansion_not_implemented_here",
            "daily_overrides": overrides,
        }
