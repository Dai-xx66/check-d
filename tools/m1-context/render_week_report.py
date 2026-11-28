"""把 ContextSnapshot 渲染成一页 HTML 周视图。

用途：PPT 截图、答辩现场翻看「我们算出来的情境长什么样」。
不是产品界面，是**证据图**——所以底部必须带数据来源与验证强度声明。

用法：
    python render_week_report.py fixtures/seed.json \
        --from 2026-11-23 --through 2026-11-29 \
        --out ../docs/evidence/stage04-context-week-report.html

不依赖第三方库，输出单文件（内联 CSS），可离线打开。
"""

from __future__ import annotations

import argparse
import html
import json
from collections import defaultdict
from datetime import date, datetime

from context_snapshot import build_snapshot

DAY_START = 480    # 08:00
DAY_END = 1380     # 23:00
TRACK_HEIGHT = 620  # px，一天竖轴的高度
WEEKDAY_CN = ["周一", "周二", "周三", "周四", "周五", "周六", "周日"]

CSS = """
:root{
  --bg:#f5f6f8; --card:#ffffff; --line:#e3e7ed; --ink:#1b2330; --muted:#5f6c7b;
  --course:#3b62d9; --course-bg:#e6ecfb; --free:#e7f5ec; --free-line:#8cc7a6;
  --warn:#a86412; --warn-bg:#fdf2df; --ok:#256b46; --ok-bg:#e6f3ec;
}
*{box-sizing:border-box}
body{margin:0;padding:28px 32px 40px;background:var(--bg);color:var(--ink);
  font-family:-apple-system,"Segoe UI","Microsoft YaHei",system-ui,sans-serif;
  font-size:14px;line-height:1.55}
h1{font-size:22px;margin:0 0 4px;letter-spacing:.3px}
.sub{color:var(--muted);font-size:13px;margin-bottom:18px}
.badges{display:flex;gap:8px;flex-wrap:wrap;margin:14px 0 22px}
.badge{display:inline-flex;align-items:center;gap:6px;padding:4px 10px;border-radius:999px;
  font-size:12px;border:1px solid transparent}
.badge.warn{background:var(--warn-bg);color:var(--warn);border-color:#f0dcb8}
.badge.ok{background:var(--ok-bg);color:var(--ok);border-color:#c7e3d3}
.badge.plain{background:#eef1f5;color:var(--muted);border-color:var(--line)}
.grid{display:grid;grid-template-columns:repeat(7,1fr);gap:10px;background:var(--card);
  border:1px solid var(--line);border-radius:14px;padding:14px;box-shadow:0 1px 2px rgba(20,30,50,.04)}
.col{display:flex;flex-direction:column;min-width:0}
.col h3{margin:0 0 8px;font-size:13px;font-weight:600;display:flex;justify-content:space-between;
  align-items:baseline;color:var(--ink)}
.col h3 .d{color:var(--muted);font-weight:400;font-size:11px}
.track{position:relative;height:%(h)dpx;background:#fafbfc;border:1px solid var(--line);
  border-radius:8px;overflow:hidden}
.hourline{position:absolute;left:0;right:0;border-top:1px dashed #eceff3}
.block{position:absolute;left:3px;right:3px;border-radius:6px;padding:3px 5px;font-size:10.5px;
  line-height:1.25;overflow:hidden}
.block.course{background:var(--course-bg);border-left:3px solid var(--course);color:#24325c}
.block.free{background:var(--free);border-left:3px solid var(--free-line);color:#2c5b41}
.free-total{margin-top:6px;font-size:11px;color:var(--muted);text-align:center}
.panels{display:grid;grid-template-columns:1.15fr .85fr;gap:14px;margin-top:16px}
.panel{background:var(--card);border:1px solid var(--line);border-radius:14px;padding:16px 18px;
  box-shadow:0 1px 2px rgba(20,30,50,.04)}
.panel h2{font-size:14px;margin:0 0 12px;font-weight:600}
table{width:100%%;border-collapse:collapse;font-size:12.5px}
th,td{text-align:left;padding:7px 8px;border-bottom:1px solid #eef1f5;vertical-align:top}
th{color:var(--muted);font-weight:500;font-size:11.5px}
td.num{font-variant-numeric:tabular-nums}
.tag{display:inline-block;padding:1px 7px;border-radius:5px;font-size:11px;background:#eef1f5;
  color:var(--muted)}
.tag.unknown{background:var(--warn-bg);color:var(--warn)}
.tag.done{background:var(--ok-bg);color:var(--ok)}
.bar{height:10px;border-radius:6px;background:#eef1f5;overflow:hidden;display:flex;margin:8px 0 6px}
.bar .known{background:var(--course)}
.bar .unknown{background:#e8c98a}
.legend{font-size:11.5px;color:var(--muted)}
.kpis{display:flex;gap:22px;margin:10px 0 4px;flex-wrap:wrap}
.kpi{min-width:88px}
.kpi b{display:block;font-size:20px;font-variant-numeric:tabular-nums}
.kpi span{font-size:11.5px;color:var(--muted)}
footer{margin-top:18px;background:var(--card);border:1px solid var(--line);border-radius:12px;
  padding:14px 18px;font-size:11.8px;color:var(--muted)}
footer b{color:var(--ink)}
footer ol{margin:8px 0 0 18px;padding:0}
footer li{margin:4px 0}
""" % {"h": TRACK_HEIGHT}


def _pct(minute: int) -> float:
    return (minute - DAY_START) / (DAY_END - DAY_START) * 100.0


def _hm(minute: int) -> str:
    return f"{minute // 60:02d}:{minute % 60:02d}"


def _rule_text(rule: dict) -> str:
    nums = rule.get("week_numbers") or []
    if nums:
        return f"指定周次（{len(nums)} 个）"
    kind = (rule.get("week_rule_type") or "").lower()
    if kind == "everyweek":
        return "每周"
    if kind == "oddweeks":
        return "单周"
    if kind == "evenweeks":
        return "双周"
    if kind == "everynweeks":
        n = rule.get("interval_weeks")
        return f"每 {n} 周" if n else "每 N 周"
    return kind or "—"


def _why_not(rule: dict, course: dict, week_no: int | None) -> str:
    """本周这节课为什么没出现。返回人话，用于答辩时解释规则确实生效了。"""
    if course.get("deleted_at") or course.get("status", "active") != "active":
        return "课程已归档 / 非 active，被排除"
    nums = rule.get("week_numbers") or []
    if nums and week_no is not None and week_no not in nums:
        return f"第 {week_no} 周不在指定清单内"
    kind = (rule.get("week_rule_type") or "").lower()
    if week_no is not None:
        if kind == "evenweeks" and week_no % 2 == 1:
            return f"第 {week_no} 周为奇数周，双周课不上"
        if kind == "oddweeks" and week_no % 2 == 0:
            return f"第 {week_no} 周为偶数周，单周课不上"
    return "本周不匹配该规则"


def render(snapshot: dict, days: list[date], source_note: str,
           courses: list[dict] | None = None,
           rules: list[dict] | None = None) -> str:
    courses_by_day: dict[str, list[dict]] = defaultdict(list)
    for ev in snapshot["fixed_events"]:
        courses_by_day[ev["date"]].append(ev)
    free_by_day: dict[str, list[dict]] = defaultdict(list)
    for sl in snapshot["free_slots"]:
        free_by_day[sl["date"]].append(sl)

    # ---- 周视图 ----
    cols = []
    for day in days:
        iso = day.isoformat()
        blocks = []
        for hour in range(9, 24):
            percent = _pct(hour * 60)
            if 0 <= percent <= 100:
                blocks.append(f'<div class="hourline" style="top:{percent:.2f}%"></div>')
        for ev in courses_by_day.get(iso, []):
            top = _pct(ev["start_minute"])
            height = _pct(ev["end_minute"]) - top
            label = html.escape(ev["title"])
            blocks.append(
                f'<div class="block course" style="top:{top:.2f}%;height:{height:.2f}%">'
                f'<b>{_hm(ev["start_minute"])}–{_hm(ev["end_minute"])}</b><br>{label}</div>'
            )
        for sl in free_by_day.get(iso, []):
            top = _pct(sl["start_minute"])
            height = _pct(sl["end_minute"]) - top
            blocks.append(
                f'<div class="block free" style="top:{top:.2f}%;height:{height:.2f}%">'
                f'<b>{_hm(sl["start_minute"])}–{_hm(sl["end_minute"])}</b><br>{sl["minutes"]} 分钟</div>'
            )
        total_free = sum(s["minutes"] for s in free_by_day.get(iso, []))
        cols.append(
            f'<div class="col"><h3>{WEEKDAY_CN[day.weekday()]}'
            f'<span class="d">{day.month}/{day.day}</span></h3>'
            f'<div class="track">{"".join(blocks)}</div>'
            f'<div class="free-total">空闲 {total_free} 分钟'
            f'{" · " + str(len(courses_by_day.get(iso, []))) + " 节课" if courses_by_day.get(iso) else " · 无课"}</div>'
            f'</div>'
        )

    # ---- 任务表 ----
    rows = []
    for t in snapshot["tasks"]:
        est = t.get("estimated_minutes")
        est_cell = (f'<span class="tag unknown">unknown</span>' if est is None
                    else f'{est}')
        status = ('<span class="tag done">已完成</span>' if t.get("completed")
                  else '<span class="tag">未完成</span>')
        due = t.get("due_date") or t.get("due_at") or "—"
        planned = t.get("planned_date") or "—"
        rows.append(
            f'<tr><td>{html.escape(t["name"])}</td>'
            f'<td>{"单次" if t["type"] == "one_time" else "长期"}</td>'
            f'<td class="num">{planned}</td><td class="num">{due}</td>'
            f'<td class="num">{est_cell}</td><td>{status}</td></tr>'
        )

    wl = snapshot["workload"]
    total_known = wl["known_minutes"]
    unknown_n = wl["unknown_estimate_count"]
    # 负荷条：已知时长按 1 分钟=1px 的相对比例展示；未知的按条数画等宽块
    known_w = 100 if unknown_n == 0 else max(12, min(88, 100 - unknown_n * 6))
    bar = (
        f'<div class="bar"><div class="known" style="width:{known_w}%"></div>'
        f'<div class="unknown" style="width:{100 - known_w}%"></div></div>'
    )

    status_badge = {
        "ok": '<span class="badge ok">status = ok</span>',
        "partial": '<span class="badge warn">status = partial</span>',
        "blocked": '<span class="badge warn">status = blocked</span>',
    }.get(snapshot["status"], "")
    blocking = "".join(
        f'<span class="badge plain">{html.escape(b["code"])}</span>'
        for b in snapshot["blocking"]
    )
    fresh = snapshot["freshness"]
    fresh_badges = "".join([
        f'<span class="badge plain">semester: {fresh["semester"]}</span>',
        f'<span class="badge plain">task_occurrences: {fresh["task_occurrences"]}</span>',
        f'<span class="badge plain">completions: {fresh["completions"]}</span>',
    ])

    semester = snapshot["semester"]
    sem_txt = (f"第 {snapshot['fixed_events'][0]['week_no']} 教学周"
               if snapshot["fixed_events"] else "教学周未知")

    # ---- 课程规则与本周生效情况（答辩最容易被问「为什么这天没课」）----
    appeared = {(ev["ref_id"], ev["start_minute"], ev["end_minute"])
                for ev in snapshot["fixed_events"]}
    course_by_id = {c["id"]: c for c in (courses or [])}
    week_no_now = None
    fw = semester.get("first_week_start_date")
    if fw:
        week_no_now = (days[0] - date.fromisoformat(str(fw)[:10])).days // 7 + 1

    rule_rows = []
    for r in (rules or []):
        if r.get("deleted_at"):
            continue
        c = course_by_id.get(r.get("course_id"))
        if not c:
            continue
        key = (r.get("course_id"), r.get("starts_at_minute"), r.get("ends_at_minute"))
        now_on = key in appeared
        wd = r.get("weekday")
        wd_txt = WEEKDAY_CN[wd - 1] if isinstance(wd, int) and 1 <= wd <= 7 else "—"
        on_cell = ('<span class="tag done">上课</span>' if now_on
                   else '<span class="tag unknown">不上</span>')
        why = "—" if now_on else html.escape(_why_not(r, c, week_no_now))
        rule_rows.append(
            "<tr>"
            f'<td>{html.escape(c.get("name", r.get("course_id", "")))}</td>'
            f"<td>{wd_txt}</td>"
            f'<td class="num">{_hm(r["starts_at_minute"])}–{_hm(r["ends_at_minute"])}</td>'
            f"<td>{_rule_text(r)}</td>"
            f"<td>{on_cell}</td>"
            f"<td>{why}</td>"
            "</tr>"
        )
    rule_rows_html = "".join(rule_rows) if rule_rows else '<tr><td colspan="6">无课程规则</td></tr>'

    now = datetime.now().strftime("%Y-%m-%d %H:%M")

    return f"""<!DOCTYPE html>
<html lang="zh-CN"><head><meta charset="utf-8">
<title>CheckD · 情境快照周视图</title>
<style>{CSS}</style></head>
<body>
<h1>情境快照 · 一周视图</h1>
<div class="sub">
  学期 {html.escape(str(semester.get("first_week_start_date", "—")))} 起 · {sem_txt} ·
  窗口 {snapshot["window"]["from"]} → {snapshot["window"]["through"]} · {snapshot["timezone"]} ·
  日窗 {_hm(DAY_START)}–{_hm(DAY_END)}
</div>

<div class="badges">{status_badge}{blocking}{fresh_badges}
  <span class="badge plain">energy_self_report: {snapshot.get("energy_self_report") if snapshot.get("energy_self_report") is not None else "未提供"}</span>
</div>

<div class="grid">{"".join(cols)}</div>

<div class="panels">
  <div class="panel">
    <h2>任务与负荷</h2>
    <table>
      <thead><tr><th>任务</th><th>类型</th><th>计划日</th><th>截止</th><th>预计分钟</th><th>状态</th></tr></thead>
      <tbody>{"".join(rows) if rows else '<tr><td colspan="6">窗口内无任务</td></tr>'}</tbody>
    </table>
    <div style="margin-top:14px">
      {bar}
      <div class="legend">蓝＝已知时长 {total_known} 分钟；黄＝{unknown_n} 个任务时长未知（按条数占位，不代表真实时长）</div>
      <div class="kpis">
        <div class="kpi"><b>{wl["open_task_count"]}</b><span>未完成任务</span></div>
        <div class="kpi"><b>{total_known}</b><span>已知负荷（分钟）</span></div>
        <div class="kpi"><b>{unknown_n}</b><span>时长未知（条）</span></div>
        <div class="kpi"><b>{wl["status"]}</b><span>workload 状态</span></div>
      </div>
    </div>
  </div>

  <div class="panel">
    <h2>这张图是怎么算出来的</h2>
    <table>
      <tbody>
        <tr><th style="width:34%">课程</th><td>courses + course_schedule_rules + semesters 三表联算，周次 = (日期 − 开学日) / 7 + 1</td></tr>
        <tr><th>空闲</th><td>日窗按分钟打点，减去当天课程段，合并连续分钟，丢弃 &lt; 5 分钟碎片</td></tr>
        <tr><th>任务纳入</th><td>长期任务全纳入；单次任务按计划日/截止日/提醒时间落窗</td></tr>
        <tr><th>时长</th><td>仅长期任务有目标时长（秒 ÷ 60）；单次任务表里没有时长列，故恒为 unknown</td></tr>
        <tr><th>已归档</th><td>归档课程与任务被排除，图上不应出现</td></tr>
      </tbody>
    </table>

    <h2 style="margin-top:18px">课程规则与本周生效情况</h2>
    <table>
      <thead><tr><th>课程</th><th>周几</th><th>时段</th><th>规则</th><th>本周</th><th>说明</th></tr></thead>
      <tbody>{rule_rows_html}</tbody>
    </table>
    <div class="legend" style="margin-top:8px">
      「不上」不是漏算，是规则判它本周不该上——答辩时可直接指着这一行解释。
    </div>
  </div>
</div>

<footer>
  <b>数据与验证强度（请勿删节引用）</b>
  <ol>
    <li>{html.escape(source_note)}</li>
    <li><b>SQL 未执行</b>：三个 migration 从未在任何真实数据库执行，三张表不存在（PGRST205 只读探测实测）。
        本图由 Python 参考实现计算，与 SQL 同算法、同字段，<b>不等于数据库已验证</b>。</li>
    <li><b>partial 的含义</b>：空闲时段只扣了课程、<b>没扣任务</b>（长周期任务实例需客户端发布）。
        所以图中绿色块不等于「这段时间真的全空」，只能读作「这段时间没有课」。</li>
    <li><b>时长未知不按 0 处理</b>：unknown 的任务不计入已知负荷，单独计数；把它当 0 会算出「今天很闲」的假结论。</li>
  </ol>
  生成时间 {now} · 渲染器 tools/m1-context/render_week_report.py
</footer>
</body></html>
"""


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("fixture")
    ap.add_argument("--from", dest="w_from", required=True)
    ap.add_argument("--through", dest="w_through", required=True)
    ap.add_argument("--energy", type=int, default=None)
    ap.add_argument("--out", required=True)
    args = ap.parse_args()

    with open(args.fixture, encoding="utf-8") as fh:
        seed = json.load(fh)

    snapshot = build_snapshot(
        window_from=args.w_from, window_through=args.w_through,
        semesters=seed.get("semesters", []),
        courses=seed.get("courses", []),
        rules=seed.get("course_schedule_rules", []),
        tasks=seed.get("tasks", []),
        one_time_reminders=seed.get("one_time_reminders", []),
        long_term_tasks=seed.get("long_term_tasks", []),
        completions=seed.get("task_completions", []),
        task_schedules=seed.get("task_schedules", []),
        occurrences_available=seed.get("occurrences_available", False),
        occurrences_cover_window=seed.get("occurrences_cover_window", False),
        energy_self_report=args.energy,
    )

    y1, m1, d1 = (int(x) for x in args.w_from.split("-"))
    y2, m2, d2 = (int(x) for x in args.w_through.split("-"))
    days = []
    cur = date(y1, m1, d1)
    end = date(y2, m2, d2)
    while cur <= end:
        days.append(cur)
        cur = cur.fromordinal(cur.toordinal() + 1)

    note = ("数据来源：仓库内 fixture（结构取自真实课程/任务表的列语义，值已脱敏），"
            "不是真实账号数据。窗口与课程规则与真实实现一致，因此算法结果可复现，"
            "但不可当作某位用户的真实课表引用。")
    out = render(snapshot, days, note,
                 courses=seed.get("courses", []),
                 rules=seed.get("course_schedule_rules", []))
    with open(args.out, "w", encoding="utf-8") as fh:
        fh.write(out)
    print(f"wrote {args.out}  ({len(out)} bytes, {len(days)} days, "
          f"{len(snapshot['fixed_events'])} courses, {len(snapshot['tasks'])} tasks)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
