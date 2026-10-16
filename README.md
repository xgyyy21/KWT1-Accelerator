# KWT-1 前馈线性层 AI 加速器

2026 年嵌入式芯片与系统设计大赛芯片设计赛道，本科生组。基于指定 E203 平台实现 KWT-1 第一前馈线性层 `Y=XW+b`：`X[99,64]`、`W[64,256]`、`b[256]`、`Y[99,256]`，支持依次切换 12 层参数。

## 当前状态

2026-10-16：阶段 1 仅建立本地工程仓库、交付规范和基础检查。输入材料只有根目录三份文件；交接提及的软件/硬件代码未随附，不能据此宣布功能通过。原始文件保留原位。官方 PDF 有 13 个物理页，对应印刷第 2～14 页，印刷第 1 页待补。

数值格式、地址、总线控制、SRAM 连接和创新方案均未冻结。硬件回复转述老师要求先做 FP32，软件 INT16 仍为原型；老师原始 txt 缺失。状态和依赖见 [PROJECT_STATUS](docs/PROJECT_STATUS.md)，官方边界见 [REQUIREMENTS](docs/REQUIREMENTS.md)，正式材料见 [SUBMISSION_CHECKLIST](docs/SUBMISSION_CHECKLIST.md)。

## 分工与目录

| 目录 | 用途 | 负责人 |
|---|---|---|
| software/ | 模型提取、数值参考、量化候选、向量、C 驱动 | 软件负责人 |
| rtl/ | PE、控制、搬运、缓存 RTL | 硬件负责人 |
| tb/ | RTL 测试与对拍 | 硬件负责人，软件协作 |
| soc/ | 指定 E203 集成及平台适配 | 硬件负责人，软件协作 |
| synthesis/ | 后续综合与 PPA；本阶段仅预留 | 项目统筹（你） |
| integration/ | 基础检查和工程汇总 | 项目统筹（你） |
| docs/ | 要求、交接及状态 | 项目统筹，三人共同维护 |
| reports/ | 真实检查、验证和综合报告 | 对应执行人 |

尚无工程内容的目录仅有 `.gitkeep`，它不代表模块已交付。项目总体规划与阶段验收由你和总控 AI 决定。

## 基本使用

Windows PowerShell，Python 3.11，无第三方 Python 依赖：

```powershell
Set-Location 'D:\KWT1-Accelerator'
python integration/check.py
```

脚本可从任意当前目录用绝对路径运行。每次在 `reports/` 新建一对带时间及唯一标识的 Markdown/JSON 报告；控制台给出计数、提交号、路径与退出码。退出码：0=已执行的基础检查无 FAIL/BLOCKED，1=存在 FAIL，2=无 FAIL 但有 BLOCKED。NOT_RUN 始终表示未执行，0 也不代表芯片验收通过。

检查范围为仓库/材料清点、PATH 工具启动和临时 Icarus 编译运行冒烟。项目仿真、精度、综合及 PPA 不在本阶段执行。工具不在 PATH 时仅报告本命令环境不可用，不断言整台机器未安装。

本机已实测：Icarus 真实程序及 WindowsApps 包装均可在普通 PowerShell/获准的沙箱外环境编译、运行最小模块；Codex 受限沙箱中编译进程曾异常退出 `0xC0000005`。不应忽略该退出码，也不需据此重装工具；在普通 PowerShell 运行上述命令。诊断对照与限制见 [ICARUS_DIAGNOSIS](reports/ICARUS_DIAGNOSIS.md)。

外部资产默认在被忽略的 `external/{e203,techlib,sram,model,data}/` 查找，也可设置 `KWT_E203_DIR`、`KWT_TECH_LIB_DIR`、`KWT_SRAM_LIB_DIR`、`KWT_MODEL_DIR`、`KWT_DATA_DIR` 指向已有本地目录。这里只做非空目录清点，库、许可、版本、角点与平台兼容性仍须后续核验。不要把凭证、许可或工艺库放进 Git。

提交前阅读 [CONTRIBUTING](CONTRIBUTING.md)，按 [交接模板](docs/HANDOFF_TEMPLATE.md) 提供实测信息。本轮仅对已审查的阶段一管理代码、文档和实测日志建立首次提交；提交版本以 `git log -1` 为准。没有配置远程或推送。三份原始赛题/交接材料留在本地，并以精确文件名忽略，待入库权限确认后再决定是否纳入；取得本仓库不代表自动取得这些材料。
