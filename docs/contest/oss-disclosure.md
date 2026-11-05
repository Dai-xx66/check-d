# 开源组件 / 平台 / 原创贡献披露表

> 主笔：M3（同学 C）· 2026-10-29
> 依据：方案原件第四节「原创与披露」——「允许使用开源组件与第三方服务，但须**披露底座模型、开发平台、第三方组件及团队原创内容**」；附件报名表填表说明第 2 条。
> 用法：提交材料时本表作为附件随大纲打包；表中「待确认」项在 11/06 冻结前必须清零。

---

## 1. 底座模型与开发平台

| 项 | 内容 | 状态 |
|---|---|---|
| 开发平台 | 腾讯 WorkBuddy AI 工作台（方案指定平台） | ✅ 确定 |
| 底座模型 | 待确认——需 A 从 WorkBuddy 平台设置页截图记录当前会话使用的模型名称与版本 | ⬜ 待 A |
| 平台内置能力 | 专家（人设）、知识库、工作流编排、MCP 工具调用 | ✅ 使用中 |
| 自建服务 | 腾讯云 CloudBase（CheckD 数据后端，见 §3） | ✅ 确定 |

> 诚实标注：底座模型由平台侧决定，团队不训练、不微调模型；本作品的原创部分为 §4 所列内容。此定位与方案「不要求提交模型内部思维链」一致。

## 2. CheckD 客户端第三方组件（来自 `pubspec.yaml`，逐条照录）

| 组件 | 版本 | 用途 | 许可证 |
|---|---|---|---|
| Flutter SDK | ≥3.9.0 | 应用框架 | BSD-3-Clause |
| drift / drift_flutter | ^2.34.0 / ^0.3.0 | 本地数据库（课表、任务、日程） | MIT |
| flutter_riverpod | ^3.0.0 | 状态管理 | MIT |
| go_router | ^16.0.0 | 路由 | BSD-3-Clause |
| supabase_flutter | ^2.9.1 | 云同步客户端 | Apache-2.0（实际后端为腾讯云 CloudBase，见 §3） |
| intl / timezone | ^0.20.2 / ^0.11.1 | 多语言与时区处理（边界用例 E05 对应） | MIT / Apache-2.0 |
| http | ^1.6.0 | HTTP 客户端 | BSD-3-Clause |
| uuid | ^4.5.1 | 标识生成 | MIT |
| flutter_local_notifications | ^22.3.0 | 提醒通知 | MIT |
| desktop_multi_window / window_manager / screen_retriever | — | 桌面端多窗口与窗口管理 | MIT |
| file_picker / qr_flutter / mobile_scanner | — | 文件导入、课表二维码分享与扫描 | MIT / Apache-2.0 |
| excel / csv / html | — | 课表批量导入导出 | MIT |
| syncfusion_flutter_pdf | ^33.2.13 | 课表 PDF 导出 | Syncfusion 社区许可（需确认条款合规性） |
| cupertino_icons | ^1.0.8 | 图标 | MIT |

> 许可证一列为常见结论，**冻结前逐个到 pub.dev 核对**，特别是 `syncfusion_flutter_pdf`（社区许可有年收入门槛条款，比赛用途通常可豁免，但须写明）。核对完成后把本表导出为提交材料附件。

## 3. 后端与数据服务

| 项 | 内容 | 披露要点 |
|---|---|---|
| 数据库 / 认证 / 存储 | 腾讯云 CloudBase（WorkBuddy 内置云服务） | 平台托管，团队不自行部署服务器 |
| 数据合规 | 演示数据全部为构造数据（`fixtures/education/`，336 项校验含 PII 扫描） | 方案要求「不得使用未脱敏个人信息」，已满足；真实课表入库前按 `needs-evidence-pack.md` §4 脱敏 |
| 参考项目 | Horolog（B 在 D0 调研的调度参考，MIT） | 仅借鉴调度思路，未复制代码；如后续复用任何源码，此行升级为「衍生自 Horolog，遵循 MIT」并列出文件 |

## 4. 团队原创内容（对应方案「团队原创内容」披露要求）

| 内容 | 位置 | 作者 |
|---|---|---|
| 教育场景输入数据（3 组）与 13 条边界用例 | `fixtures/education/` | C |
| fixture 自检脚本（336 项校验 + PII 扫描） | `fixtures/education/validate_fixtures.py` | C |
| 「计划前/后」差异展示规格与视觉稿 | `docs/demo/before-after-spec.md`、`before-after-preview.html` | C |
| 最小扰动重排规则（固定事件不可移、缺口显式返回、幂等写入） | `docs/demo/before-after-spec.md` §3 + M2 调度器实现 | C 定义 / M2 实现 |
| WorkBuddy 侧提示词与工作流编排 | WorkBuddy 平台（配置导出待 A 提供） | A |
| 接口契约 `agent-api-v1` | `docs/contracts/`（待 M0） | 队长 + M0 |
| 提交材料体系（清单、评分映射、隐私清单） | `docs/submission/` | C |

## 5. 冻结前检查（11/06）

- [ ] 「待确认」清零：底座模型名称（A）、syncfusion 许可结论（C）
- [ ] pub.dev 逐个核对许可证列
- [ ] Horolog 是否有实际代码复用（B 确认）
- [ ] 本表导出 PDF 并纳入提交包
- [ ] 与 `privacy-checklist.md` 一起做最后匿名扫描（本表不得出现成员姓名，只写代号）
