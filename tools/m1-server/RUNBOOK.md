# 比赛版工具服务 · 运行说明（M1）

本目录有**两样东西**，别混：

| 文件 | 是什么 | 状态 |
|---|---|---|
| `errors.py` + `tests/test_errors.py` | 契约 §4.1 的 21 码 HTTP 映射与失败信封，34 条单测 | 已交付（PR #10） |
| `app.py` | 把 `tools/m1-mock/tool_server.py` 的 7 个工具暴露成 HTTP / MCP 服务 | 本次比赛版新增 |

工具实现只有一份，在 `tools/m1-mock/tool_server.py`。`app.py` 只做传输层：
鉴权、JSON、HTTP 状态、证据记录。**不要在 app.py 里加第二套业务逻辑。**

---

## 一、本机运行（只绑回环）

```bash
cd tools/m1-server
CHECKD_DEMO_TOKEN=<随机口令> CHECKD_ADMIN_KEY=<随机管理口令> PORT=8790 python app.py
```

默认 `BIND=127.0.0.1`，**只有本机能连**。这是刻意设计：默认值就是安全边界，
要让本机之外可访问必须显式给 `BIND`，且会打警告。

## 二、部署到平台沙箱

服务跑在平台沙箱，用户电脑不开任何端口：

```bash
python work/m1/build_deploy.py            # 组装 work/deploy/checkd-tools
```

部署时启动命令：

```
BIND=0.0.0.0 CHECKD_DEMO_TOKEN=<口令> CHECKD_ADMIN_KEY=<管理口令> PYTHONUNBUFFERED=1 python3 app.py
```

沙箱内绑 `0.0.0.0` 是平台要求（反向代理回源）。**沙箱外不要这么跑。**

### 2.1 发布前必须重建并核对（2026-11-08 定稿）

部署目录是**构建产物，不是真源**。仓库改了没重建就发布 = 带旧代码上线；
而且 `/health` 的精简输出（4 键）**分辨不出上线件是哪个 commit**，事后没法从公网反推。
2026-11-08 02:05 实测过：部署目录里 `snapshot_store.py` 落后两个提交（37,506 B，缺 TTL 两次修改），
其余 11 个文件与 HEAD 逐字节相同——只有重建才会对上。

每次发布前：

```bash
python work/m1/build_deploy.py               # 脚本先 rmtree 再重拼，可反复跑
cat work/deploy/checkd-tools/MANIFEST.json   # 逐文件 bytes / sha256
```

核对判据（任一条不满足就别发布）——**比 LF 归一后的 sha256，不比字节数**：

```bash
cd work/repo/check-d
for f in tools/m1-server/app.py tools/m1-server/errors.py \
         tools/m1-server/snapshot_store.py tools/m1-server/explanations_filter.py \
         tools/m1-mock/tool_server.py; do
  echo "$f wt=$(tr -d '\r' < $f | sha256sum | cut -c1-16) head=$(git cat-file blob HEAD:$f | sha256sum | cut -c1-16)"
done
```

- 每行两侧 16 位前缀必须相同；MANIFEST 的 `sha256` 应等于工作树文件的 sha256。
- **为什么用 `tr -d '\r'`**：Windows 工作树的 `errors.py` 是 CRLF（8,137 B），HEAD blob 是 LF（7,943 B），
  行数同为 194、LF 归一后 sha256 完全相同。直接比字节数会误判成「改过」。
- 参照值：`snapshot_store.py` 在 11-07 之后应为 **39,993 B**。若 MANIFEST 里还是 **37,506 B**，
  说明目录还是 `40e801f` 时代的旧件，TTL 两次修改都不在里面。

## 三、环境变量

| 变量 | 作用 | 不设的后果 |
|---|---|---|
| `PORT` | 监听端口 | 默认 8790 |
| `BIND` | 绑定地址 | 默认 `127.0.0.1`；部署时必须显式 `0.0.0.0` |
| `CHECKD_DEMO_TOKEN` | 业务口令 | **未设置则全部业务端点返回 503**（fail-closed） |
| `CHECKD_ADMIN_KEY` | 管理口令 | 未设置则 reset / evidence / state / demo confirm 整体禁用 |
| `CHECKD_DEMO_USER` | 口令通过后使用的演示身份 | 默认 `demo-token-alice` |

口令通过后，内部固定以演示用户身份调用工具。mock 自带的
`demo-token-alice/bob` 不出现在任何对外文案里。

## 四、端点

| 方法 | 路径 | 鉴权 | 用途 |
|---|---|---|---|
| GET | `/health` | 无 | 存活检查；只给配置指纹（不可逆），不给数据 |
| GET | `/tools` | 业务口令 | 7 个工具的 schema，供 Agent 配置 |
| POST | `/tools/<name>` | 业务口令 | 直接调用；body 是**四键请求信封**（见下） |
| POST | `/mcp` | 业务口令 | MCP JSON-RPC（无状态），供平台挂成工具 |
| GET | `/evidence` | 管理口令 | 工具调用记录：工具名/参数/结果/耗时 |
| GET | `/state` | 管理口令 | 演示数据规模与写入计数 |
| POST | `/admin/reset` | 管理口令 | 回到初始 fixture（重新加载模块） |
| POST | `/demo/confirm` | 管理口令 | **演示确认**，见下节 |

鉴权头：优先 `X-Demo-Token: <口令>`，也接受 `Authorization: Bearer <口令>`。

**`POST /tools/<name>` 的 body 必须是四键请求信封，不是裸的入参对象**（2026-11-05 修正，M3 独立复验指出的唯一 FAIL）：

```json
{
  "api_version": "checkd.agent.v1",
  "request_id": "req_0001",
  "timezone": "Asia/Shanghai",
  "input": { }
}
```

工具自己的参数全部放在 `input` 里。漏了信封会直接 400 `INVALID_ARGUMENT`。
`api_version` 的合法值只有 `checkd.agent.v1` 一个（写成 `1.0` 会报 `unsupported`）。
`GET /tools` 返回的 schema 是按这个形状写的，照 schema 填不会错。

**为什么优先 X-Demo-Token**：实测平台反代会注入/覆盖 `Authorization`，
只认这个头会永远 401。两个来源都收，逐个比对。

## 五、`/demo/confirm` 的定性（必须照这个说）

这是**演示确认**，不是真实审批。

- 真实审批链（G5）要求独立审批服务、私钥签发、撤销机制、外部确认页 —— **全部 BLOCKED**。
- 本端点只把一条待审记录置为 approved，让纵向闭环能在隔离演示数据上真的跑完。
- 响应里固定带 `"demo": true`，任何转述都必须保留这个标记。
- **不得**把它写成"审批通过"或"生产可用"。

## 六、接进 WorkBuddy（MCP）

`%USERPROFILE%\.workbuddy\mcp.json` 加一条：

```json
{
  "mcpServers": {
    "checkd-agent-tools": {
      "type": "http",
      "url": "https://checkd-agent-tools.app.workbuddy.host/mcp?sharecode=EH5AAYWLOT",
      "headers": {
        "X-Demo-Token": "<业务口令>"
      }
    }
  }
}
```

然后：连接器 → 自定义连接器 → MCP 服务管理 → 找到该条目 → **信任** → 新建任务对话。

信任是界面操作，必须由账号所有者在客户端点一次。这一步脚本做不了。

## 七、边界

- 无数据库。数据全在进程内存，重启即回到初始 fixture。
- 不支持 Dart，M2 引擎**无法**部署到这里；`generate_schedule` 当前用的是 mock 调度器。
- 单一实现、单一进程、串行可接受；无限流、无审计日志、无 WAF。
- 演示数据仅隔离环境，不写 Production / Dev。

## 八、快照库的两个身份（必须分开说，别混）

`tools/m1-server` 接快照库时涉及**两个不同的数据库身份**，它们的权限完全不同，
验收结论里混着写就是错的说法。

| 身份 | 谁在用 | 权限 | 能干什么 |
|---|---|---|---|
| `postgres`（库所有者） | M0 在 Supabase SQL Editor 执行 migration | 超级权限，`revoke` 对它无效 | DDL、建表、改约束 |
| `checkd_demo_app`（nologin 角色） | 应用运行时连接 | 只 `usage` + 四张表的 DML，**无** `create`/`delete`/`truncate` | 读写业务表，不能改结构 |

三条容易说错的：

1. **用 postgres 的 DSN 跑应用，等于最小权限没生效。** migration 里的 `revoke`/
   `grant` 对一个库所有者角色不构成限制，它本来就能做任何事。这种情况下权限段是
   **文档性约束**，不是运行时约束 —— 验收结论不得写「已按最小权限运行」。
2. **preflight 报「应用角色有权限」≠「应用真的用该角色连」。** 前者只证明权限位存在，
   后者要拿 `checkd_demo_app` 的 DSN 真连一次才能证明。两件事分开写。
3. **要真验最小权限**，得给 `checkd_demo_app` 开 login + 密码，用它的 DSN 跑一遍
   preflight（`CHECKD_DEMO_DSN` 换成该角色）。这一步需要 M0 单独授权，
   因为要新增一个有 login 的角色。

## 九、preflight 的只读边界（2026-11-07 事故后定稿）

`preflight_snapshot_db.py` **默认只读**：连接层 `default_transaction_read_only=on`、
语句守卫只放行 select/with/show/explain、连上后真去 `create temp table` 验证写被拒
（SQLSTATE 25006）。

写入型行为测试（唯一索引 / 复合 FK / TTL 实拍）走另一条命令，且必须显式授权：

```
python tools/m1-server/preflight_snapshot_db.py --behavior-tests --i-have-m0-approval
python tools/m1-server/preflight_snapshot_db.py --apply          --i-have-m0-approval
```

缺 `--i-have-m0-approval` 一律 `REFUSED` + exit 3。**不要**用「文件名/参数名看起来是只读」
当证据 —— 2026-11-07 就出过一版默认路径会 INSERT/DELETE 的脚本，注释写着只读。

### 9.1 唯一命令（macOS / Linux，M0 本机）

```bash
cd <仓库根> && CHECKD_DEMO_DSN="$CHECKD_DEMO_DSN" \
  python3 tools/m1-server/preflight_snapshot_db.py
```

- 结果路径**固定且与 cwd 无关**：先找 `<仓库>/../work/m1/`（本机工作区布局），
  干净 clone 下落到 `<仓库根>/preflight_snapshot_db_result.json`；脚本开头会打印
  `结果文件: <绝对路径>`，跑完照它取文件。要别的路径加 `--out /abs/path.json`。
- 退出码：`0` 无 FAIL／`1` 有 FAIL／`2` 拿不到库或缺 psycopg3／
  `3` REFUSED（写路径缺授权）／`4` BLOCKED（只读证明失败，后续检查一律未执行）。
- 只读证明失败（连接非只读，或探针临时表居然建成功）**立即 exit 4**，
  不再跑 schema/权限检查，也不会去「清理」探针表（只回滚事务）。

### 9.2 干净 Mac 首次安装与运行（2026-11-08 修正版）

适用：机器上没装过 psycopg3、也没建过虚拟环境。**逐行照抄，别改顺序。**

```bash
git clone -b demo/competition-11010 https://github.com/Tony2215/check-d.git
cd check-d
git rev-parse HEAD                    # 期望 1a426717… 之后的最新 head
python3 -m venv .venv
. .venv/bin/activate                  # 之后所有命令都在这个 venv 里
python -m pip install -U pip 'psycopg[binary]'
env -u DATABASE_URL CHECKD_DEMO_DSN='postgresql://用户:口令@主机:5432/库名' \
  python tools/m1-server/preflight_snapshot_db.py
cat ./preflight_snapshot_db_result.json
```

三处与 2026-11-08 之前的旧命令不同，都是 11-08 复核后改的：

1. **用 venv，不用 `pip install --user`**。macOS 上 python.org / Homebrew 的 3.11+
   是 PEP 668 externally-managed 环境，`--user` 会被 `error: externally-managed-environment`
   直接拒掉。venv 是唯一不需要动系统 Python 的做法。
2. **命令前加 `env -u DATABASE_URL`**。脚本取 DSN 的顺序是
   `CHECKD_DEMO_DSN` → `DATABASE_URL`（见 `preflight_snapshot_db.py` 的 `main()`）。
   `CHECKD_DEMO_DSN` 非空时不会读 `DATABASE_URL`，所以这是**纵深防御**、不是修 bug：
   万一 DSN 那串打错或为空，脚本会默默回退到你 shell 里别的 `DATABASE_URL`（可能是正式库）。
   剥掉它，就不会连错库。**别指望脚本自己发现连错了。**
3. **`psycopg[binary]` 不锁版本**。现网 3.3.8 已提供 cp315（Python 3.15）macOS 轮子，
   3.9–3.15 都装得上；锁版本反而会在新解释器上找不到匹配轮子。

跑完看三样：退出码（`0` 才算无 FAIL）、`结果文件:` 打印的绝对路径、JSON 里只出现
host/dbname/user 三项（**不含 DSN**）。退出码 2 = 没拿到库或缺 psycopg3，不是代码失败。


## 十、怎么核对「远端真的收到了」

我们的推送走 `work/push_via_api.py`：**逐 blob 在远端重建 tree，不推 git 历史对象**。
后果有两个，都很容易被误读成"没推上去"：

- 远端每个提交的 sha 都**和本地不同**（同一个 tree 内容，不同提交对象）；
- 远端的 `git log` 里**看不到**本地那些提交。

**所以不要用 commit sha 核对，用 tree 或文件 blob。**

| 层级 | 怎么比 | 证明了什么 |
|---|---|---|
| tree | `git rev-parse <本地提交>^{tree}` 与远端该提交的 tree | 整个仓库快照一致 |
| blob | `git rev-parse <本地提交>:<路径>` 与远端该路径的 sha | 单个文件逐字节一致 |

推送脚本结尾会逐文件打印 `remote=… local=… MATCH/DIFF`。
**全 MATCH + 出现 `ref updated` = 成功**，这是最省事的判据。

反例（2026-11-08 实际发生，M3 报的）：有人按 sha 去找 `e56f6dd` / `b25f262`，
在远端找不到，于是记成"这两个提交没推上去"。实际内容都在——
`e56f6dd` 的 tree `73938ff4` 对应远端 `79f79195`，`b25f262` 之后的所有改动都累积在
后续 tree 里。**按 sha 找必然找不到，这是通道特性，不是漏推。**

要判断"某个改动在不在远端"，就问一句：它在**当前 HEAD 的 tree** 里吗？
在，就已经推出去了。

## 十一、为什么公网永远测不到 `reason=missing`

M3 2026-11-09T12:56:42Z 报「缺口令没有按工单报 missing，不带头也返 invalid」。
**代码没错，环境使然**，这里把原因和判据一起写死，免得每次验收都重新争一遍。

`app.py` 的 `_auth_ok()` 里有 missing 分支：

```python
if not cands:
    self._fail(401, "APPROVAL_UNTRUSTED", "缺少访问凭证…",
               details=[{"field": "X-Demo-Token", "reason": "missing"}])
```

但 `_candidates()` **同时收集两个头**（代码注释原文：「平台反代会注入/覆盖这个头」）：

- `X-Demo-Token`
- `Authorization`（`Bearer xxx` 会去掉前缀后入列）

**平台反向代理会给每个请求注入 `Authorization`**，所以 `cands` 永远非空
→ 一定走到 `reason=invalid`，`missing` 分支在公网不可达。

| 访问方式 | 期望结果 | 说明 |
|---|---|---|
| 经公网网关，完全不带任何凭证 | 401 + `reason=invalid` | **这是正常现象，不是部署件旧** |
| 直连容器/本机，完全不带任何凭证 | 401 + `reason=missing`（约 301 B） | 不经反代才有 missing |
| 经公网，带错口令 | 401 + `reason=invalid` | 与上一行响应体不同处仅在 details |

**验收判据请按上表写**。要验 missing 分支，必须**绕过反代**直连；拿公网结果验 missing 永远验不到。

## 十二、输入校验与来源标注（2026-11-09 收 M3 P1-b / P2 后新增）

**参数校验在 `_call()` 最前面，先于任何副作用。**
`tool_server.SCHEMAS[name]` 描述的是 `input` 这一层，服务端现在**真的执行**它：

- `additionalProperties: false` → `input` 顶层出现未定义字段即 `INVALID_ARGUMENT`
- `required` 缺字段 → `INVALID_ARGUMENT`
- 例子：`generate_schedule` 的 `input` 里塞 `engine: "real"` → **400 / INVALID_ARGUMENT**，不进工具
- 例子：`get_approval_status` 传 `proposal_id`（schema 要 `approval_id`）→ **400 / INVALID_ARGUMENT**，
  不再报 `NOT_FOUND`（那个错法会让现场把「参数名写错」误诊成「状态丢了」）

**已知边界**：只校验 `input` 顶层，**不递归**校验嵌套对象（`date_range` 内部塞未知字段仍放行）。
两侧都在 `tests/test_input_schema_and_source.py` 里钉了用例，包括那条「嵌套未拦」的边界本身。

**来源标注**：所有工具响应顶层都带两个字段

| 字段 | 取值 | 含义 |
|---|---|---|
| `source` | `mock` / `real` | 数据是不是真实 App 数据。**当前所有路径均为 `mock`** |
| `data_source` | `builtin` / `snapshot` | mock 内部的细分：内置 4 条常量 / 库里的快照 |

为什么必须显式给：M0 2026-11-09T10:51 要求「必须清晰区分 REAL-READ / MOCK-SCHEDULE / REAL-WRITE」，
而 M3 实测 `generate` 载荷里 `mock` 出现 **0 次**，唯一可辨识痕迹是 `approval_url` 的域名——
靠域名去猜是不是假数据太脆，验收方不该做这种推断。

## 十三、REAL-READ（隔离开发件，2026-11-09 新增）

**默认全关。** 现网 `/mcp`、`/tools/*`、`/health` 四键档行为零变化。

### 两条路径，物理隔离

| 路径 | 数据源 | 鉴权头 | 工具数 |
|---|---|---|---|
| `/mcp`、`/tools/*` | MOCK（内置 4 条） | `X-Demo-Token` 或 `Authorization` | 7 |
| `/real/mcp`、`/real/tools/*` | M0 账号已同步的 Supabase 数据 | **只认 `X-Real-Token`** | 2（`list_tasks`、`get_calendar_events`） |

**反向隔离**：`X-Demo-Token` 开不了 REAL，`X-Real-Token` 也开不了 MOCK。
理由不是洁癖——`X-Demo-Token` 在 2026-11-08 已写进邮件、进过交付件、在多人手里，
若它能开 REAL，「两套凭证」就只剩命名区别。两个方向都有测试钉住
（`tests/test_real_path_http.py::TestReverseIsolation`）。

### 环境变量

| 变量 | 作用 | 未设时的行为 |
|---|---|---|
| `CHECKD_REAL_ENABLED` | `1` 才启用 | `/real/*` 一律 503 |
| `CHECKD_REAL_TOKEN` | REAL 访问口令 | 503（fail-closed） |
| `CHECKD_REAL_SUPABASE_URL` | 形如 `https://<ref>.supabase.co` | 调用时 503 |
| `CHECKD_REAL_ANON_KEY` | 公开 anon key（本来就要打进客户端） | 调用时 503 |
| `CHECKD_REAL_JWT` | 用户级 access_token | 调用时 401 `AUTH_REQUIRED` |
| `CHECKD_REAL_WINDOW` | 形如 `14:00-16:00`，留空不限 | 格式非法时**拒绝**（不当作未配置） |

### 令牌怎么更新（M0 手动，不是自动续期）

```bash
curl -X POST https://checkd-agent-tools.app.workbuddy.host/admin/real-token \
  -H "X-Admin-Key: <管理口令>" -H "Content-Type: application/json" \
  -d '{"access_token":"<本机取到的新令牌>"}'
```

- 只驻**内存**，进程重启后回到 `CHECKD_REAL_JWT` 的值（可能已过期）。
- 入口会拒掉：非 JWT 形状、载荷无 `exp`、已过期。收下这些只会让后续 401 被误判成配置错。
- 响应只回过期时刻，**不回显令牌本体或任何一段**。

### 学期锚点（M0 2026-11-10T02:04 派工后新增）

M0 在 App「编辑学期」页亲自核到：大二上学期 / 首周 **2026-08-31** / 18 周 / 已设为当前学期。
所以「学期缺失」不成立，读不到只能是读取链路没闭合。他的硬要求：
**不可写死 2026-08-31、不可凭当前星期猜、不可新建重复学期表**，缺记录或不明确就 fail-closed 上报。

`get_calendar_events` 的输出因此多两个字段：

| 字段 | 内容 |
|---|---|
| `semesters[]` | 全量学期：`semester_id` / `name` / `first_week_start_date` / `total_weeks` / `schedule_template_id` / `is_current` / `updated_at`。**原样透传**，不推算、不补时间 |
| `semester_blocked[]` | fail-closed 上报出口，空数组表示锚点明确 |

三种 blocked（码名与 M2 模块一致）：

1. `semesters` 一条都没有 → `MISSING_SEMESTER_ANCHOR`
2. 有记录但没有一条 `is_current` → `MISSING_SEMESTER_ANCHOR`
3. 同时多条 `is_current` → `MULTIPLE_CURRENT_SEMESTERS`

**不许猜**：不做「取 `updated_at` 最新那条顶上」这种兜底。猜错的后果是整学期课表错位，
比明确报错更糟。缺锚点**不阻断**整次调用（任务部分仍然有效），但必须在 `semester_blocked` 里出现。

### 已知边界（不得写成已实现）

1. **课程周次展开不在这里**。`get_calendar_events` 的 `events` 恒为空数组并带
   `events_unavailable_reason=week_expansion_not_implemented_here`。
   展开归 M2（M0 2026-11-09T14:08 派工原文）。
2. **不做 Task/Course → Agent 结构的语义转换**，同样归 M2。本层只做字段白名单 + 枚举规范化。
3. **一次性任务的预计耗时真实 schema 里没有**（只有 `long_term_tasks.target_duration_seconds`），
   因此 `duration_target_seconds` 可能为 `null`、`execution_mode` 随之是 `untimed`。**不估算、不补默认值。**
4. **读到的是云同步副本，不是设备实时状态**。未同步的改动看不到。这是本地优先架构的必然，不是缺陷。
5. **不设 `user_id` 条件**，隔离完全靠 RLS。若部署时误用 `service_role`，本模块自身察觉不到 ——
   防线在密钥选择上（这条已写进 M0 操作清单）。
6. **没有真实账号读取的 PASS 证据。** 全部证据来自构造数据 + 假 PostgREST。

### 跑测试（不需要任何真实凭证）

```bash
python -m unittest discover -s tools/m1-server/tests
```

### 一条命令出「可粘贴的实跑日志」（给复核人用）

```bash
python tools/m1-server/verify_real_isolated.py
```

起本地进程打七个场景（REAL 未启用／无凭证／错凭证／演示口令打 REAL／正确口令+源不可用／
真实口令打 MOCK／MOCK 回归），打印表格 + 判定，**全部符合预期 exit 0**。

这份东西的用途是：复核人的本机若被权限拦、跑不了动态测试，可以直接看这份日志，
或在他自己机器上跑出同样一份贴进核验件。它只证「两条路径鉴权互不串门、失败不回落 MOCK」，
**不证**真实账号数据读取。

其中与 REAL 相关的四份：

| 文件 | 项数 | 钉住什么 |
|---|---|---|
| `test_real_read.py` | 38 | 字段映射、白名单、错误码、空集不回落、不传 user_id、学期锚点不猜 |
| `test_real_path_http.py` | 23 | 反向隔离（含「两个口令同时带」）、工具面、失败不回落、窗口、现网回归 |
| `test_real_end_to_end.py` | 10 | 假 PostgREST 端到端：JWT 透传、信封形状、`data.tasks`、软删除过滤的适用范围 |
| `test_real_token_update.py` | 9 | 令牌注入入口：鉴权、形状校验、不回显 |
| `test_real_schema_columns.py` | 7 | **静态核对**：用到的每一列都真在 migration 里存在；端到端夹具的每个键也是真实列名（不连网） |

合计 **87 项**（REAL 五份）。整套（含 MOCK 与快照库）**284 项**。

### 列名必须对 migration 做静态核验（2026-11-09 实测踩到）

假 PostgREST **不校验列名**。所以列写错时，全部测试照旧绿，一到真实库就是
400 `column ... does not exist`，而外部看到的是「整个 `list_tasks` 失败」——
极容易被误诊成令牌或权限问题。

真实案例：`task_schedules` 建表（`202609020001`）时没有 `deleted_at`，
后续 `202609100001` 只加了 `weekdays_mask`，这张表的删除靠外键 `on delete cascade` 硬删。
而查询里带了 `deleted_at=is.null` → 真实库必 400。

规矩：

1. 改 `real_read.py` 的列白名单或 `filters`，**同时**改
   `tests/test_real_schema_columns.py` 的 `QUERIED` 映射，然后跑一次。它会解析
   `supabase/migrations/*.sql` 建表语句与 `add column`，逐列断言存在性。
2. 加软删除过滤前先确认那张表**真有** `deleted_at`。实测（静态解析 9 份 migration）：
   **有** 17 张（`tasks` / `tags` / `task_completions` / `plans` / `reviews` / `courses` /
   `course_schedule_rules` / `daily_item_overrides` / `timer_sessions` / `notifications` /
   `reminder_rules` / `alarm_rules` / `ad_hoc_timers` / `semesters` /
   `schedule_templates` / `schedule_template_segments` / `user_preferences`）；
   **没有** 11 张（含 `task_schedules`、`one_time_reminders`、`long_term_tasks`、
   `plan_tasks`、`devices`、`holidays`、`profiles` 等）。
3. 这条核验是**静态**的，只能证明列名对得上 migration；证明不了线上库的
   migration 已跑到哪一版。后者要靠 M0 在真库上跑一次。
