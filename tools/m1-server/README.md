# tools/m1-server

M1 服务端**接口骨架与原型的隔离目录**。

## 这个目录是什么，不是什么

**是**：契约语义在代码里的可执行表达，可以单测、可以在干净环境复现、可以被独立审查。

**不是**：
- 不是已经存在的生产服务；
- 不代表真实 HTTP、IdP、数据库或审批链已经实现；
- 没有接入 CI（本仓库没有 `.github/workflows`，本目录也不新增）。

M0 2026-11-05 09:41:14Z 裁定 §一.2 明确了这一定位，并批准使用 `tools/m1-server/` 与 `tools/m1-mock/` 并排。

## 当前内容

| 文件 | 对应 Decision Pack 项 | 状态 |
|---|---|---|
| `errors.py` | PR-A（DP-P3）21 码 → HTTP 映射 + retryable + 信封 | 已实现 |
| `tests/test_errors.py` | 同上，28 条断言 | 全过 |
| `requirements-dev.txt` | 开发依赖清单（pin 版本） | 运行时与测试均零依赖 |

后续会加入（各自独立 PR，不堆在同一分支）：
`snapshot.py`（PR-C，R4 未裁部分显式 skip）、`idem.py`（PR-D，内存实现）、
`authz.py` + `readonly.py`（PR-E/PR-F，骨架；真实验签 BLOCKED，无 IdP）。

## 怎么跑测试

零依赖，干净环境直接可跑：

```bash
python -m unittest discover -s tools/m1-server/tests -v
```

期望：`Ran 28 tests` + `OK`，退出码 0。

装了 pytest 也可以（`pip install -r tools/m1-server/requirements-dev.txt`）：

```bash
python -m pytest tools/m1-server/tests -q
```

**两种方式跑的是同一批 `unittest.TestCase`，不维护两套用例。**

## errors.py 的三层区分（读代码前先看这个）

容易混淆的是「契约怎么定」和「设计件怎么建议」，本模块刻意把它们分开：

1. `HTTP_BY_CODE` —— 21 码的 HTTP 状态。契约原文是**建议**，不是强制。
2. `HTTP_ENFORCED` —— 契约全文唯一写成「固定为」的那一条：
   `IDEMPOTENCY_IN_PROGRESS` = 409。
3. `RETRYABLE_CONTRACT`（2 码，契约明文）vs `RETRYABLE_SUGGESTED`（19 码，A1 §6.4 建议）。
   **M-3 尚未裁定**，所以后 19 项只能说「与设计件一致」，不得对外声称与契约一致。

`retryable_source(code)` 会告诉你某个码的取值是 `contract` / `suggested` / `unknown`，
对外汇报时必须照实区分。

## 已知的风险点（不要顺手改）

- `READBACK_MISMATCH` 的 `retryable` 必须是 `false`。此时 Proposal 是终态 `failed`，
  标 true 会让调用方对终态重复发起写入，与契约 §6.7「终态不允许再次写入」直接冲突。
- 未知 code 的 `retryable` 一律 `false`。未知失败不该被重试。
- 未知 code 的 `http_status` 返回 500 而不抛异常：这一层只做映射，拒绝由调用方用
  `is_known_code()` 判定，避免把「映射不到」和「非法输入」混为一谈。
