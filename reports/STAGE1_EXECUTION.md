# 阶段 1 实际执行记录

日期：2026-10-16，Asia/Shanghai。执行范围：本地 Git、分类预留、简短规范、官方要求/提交清单、基础检查与临时工具冒烟。没有执行项目 RTL、真实模型、SoC、综合或 PPA，没有创建远程、推送、安装工具或冻结技术协议。

## 材料与保全

初始目录仅有下列三份文件，无 `.git`、软件、RTL、TB、SoC 工程。三份原文未移动/修改；创建工作前、完成后 SHA-256 相同：

| 原文件 | SHA-256 |
|---|---|
| 嵌赛题目.pdf | 354977bf737a6c21b1267fd96853ff6bdcb5c7fa82c240f8ff190845f980d719 |
| KWT-1_软件与硬件交接和并行安排.md | cd96b15c1487f7a72b93542a73bc1e4b5e7a13ed78478ab7ac9e59eb287dfe1c |
| 硬件侧回复_软件交接_2026-10-16.md | 0fa2e5cd5a6738c14ef83397332df767727db3b6f9fed55e83ba6ee8dd014723 |

扫描 PDF 无可提取文字，使用本地渲染逐页读完。物理 13 页对应印刷 2～14 页；缺印刷第 1 页及版本公告确认，未从互联网补充或假定完整。渲染图及额外探针只作临时材料，收尾清理；原始材料保留根目录。

## 执行与修正

1. `git init` 返回 0，在当前目录创建 `.git`；Git 2.55.0.windows.3，初始分支 master。未执行 git add/commit，尚无 HEAD 提交；`git remote` 为空。
2. 初版脚本第一次启动遇到第 249 行括号语法错误，当次未生成报告；已修正。该开发错误不计作最终工程功能结论。
3. 首次完整检查（21:18:17）输出 `PASS=22 | FAIL=2 | BLOCKED=19 | NOT_RUN=2`，退出码 1。报告目录当时尚未创建，清点 FAIL；脚本写报告时创建该目录。另一 FAIL 是 Icarus 编译异常。原报告 `basic_check_20261016_211817_710957_72225f.md/json` 保留。
4. 随后在短路径工作目录中用相对输入输出文件名复测 Icarus，仍未成功；最终脚本改为相对文件名，并在报告记录 Windows 十六进制返回码。未修改系统安装、未使用管理员权限，也未判断出异常根因。
5. 最终检查见下方和同名 JSON/Markdown。它已真实运行完成并输出报告，退出码 1 来自实际工具冒烟失败。临时模块仅含 `$display` 与 `$finish`，不属于队友/项目设计 RTL。
6. `git check-ignore` 验证临时目录、build、模型 h5、波形 vcd、工艺 lib 和 `.env` 被忽略；小型 `software/vector.mem` 及 `reports/example.json` 没有被忽略。上述忽略检查使用示例路径名，没有生成这些示例文件。

## 最终实际控制台输出

命令：`python integration/check.py`

```text
KWT-1 stage 1 basic checks
Time: 2026-10-16T21:20:34.152623+08:00
Stage1 basic: FAIL; Overall readiness: FAIL
PASS=23 | FAIL=1 | BLOCKED=19 | NOT_RUN=2
Commit: (no commit)
Markdown: D:\KWT1-Accelerator\reports\basic_check_20261016_212034_152623_8bcde9.md
JSON: D:\KWT1-Accelerator\reports\basic_check_20261016_212034_152623_8bcde9.json
Exit code: 1
```

报告中 PASS 只表示明确列出的清点/读取检查通过。文件存在不代表功能正确；项目功能/精度/综合由于缺依赖为 BLOCKED，创新和最终包生成为 NOT_RUN。报告 Git 快照采于报告生成前，当前执行记录也在该快照之后创建。

## 当前人工处理事项

- Icarus 12.0 的 `iverilog -V`、`vvp -V` 返回 0，但最小编译返回 3221225477（0xC0000005），无 stdout/stderr；实际模拟尚未运行。需工具维护人检查安装/环境，不能仅凭版本宣布仿真可用。
- PATH 未发现 Verilator、Yosys、dc_shell、genus、常见 riscv32/riscv64 unknown-elf GCC。未扫描整机或服务器，不等于这些工具绝对不存在。
- 补齐完整官方指南/最新公告、老师两份 txt、软件/RTL/TB 源码及日志、指定 E203/SDK、模型权重/合法数据、授权综合环境与标准单元/SRAM 库、宏面积及 PVT 资料、确认的约束和真实任务活动。
- FP32/INT16、寄存器/命令、总线、SRAM 连接/布局、创新均等待团队确认。硬件回复只作转述/自述，不能替代原始要求或实测。
- Git 已就绪但无首提交；由成员审阅暂存内容后建立首个提交。本阶段不配置远程。

仓库与交付入口已建立；环境工具存在一个真实 FAIL，其余工程依赖尚未齐全。交由你和总控 AI 验收，本阶段到此停止。

## 阶段 1 补充轮（同日，21:40 以后）

以上为首轮历史快照，保留原始失败信息。补充诊断见 [ICARUS_DIAGNOSIS](ICARUS_DIAGNOSIS.md)：同一安装在获准沙箱外编译/运行均返回 0，原检查程序无需修改；首提交前完整复查为 PASS 24、FAIL 0、BLOCKED 19、NOT_RUN 2。原始赛题/交接材料跳过入库，只审查并提交阶段一管理代码、文档及日志。实际首提交及提交后状态见 Git 历史和后续基础报告。
