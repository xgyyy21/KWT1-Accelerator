# DC SRAM library link and macro-preservation check

2026-11-02 已在比赛服务器运行通过。这里只验证旧版三 bank 测试壳的库链接、结构编译和 24 个 RAMSP128X16 宏保留；不代表 INT16/完整加速器、150 MHz、STA、功能等价或 PPA 通过。

## 运行

在允许的服务器个人工作目录放置本目录，然后执行：

```sh
bash synthesis/dc_sram_link/run_dc.sh
```

服务器已有部署无需重新上传，可直接执行：

```sh
bash ~/kwt1_dc_link_jk9nlvtb/run_dc.sh
```

每次创建新的 `results_XXXXXXXX`，不覆盖历史运行。脚本使用现有 `dc_shell`、`timeout`、`sha256sum`。标准单元 DB 和 SRAM Liberty 均在服务器读取；本目录不包含工艺库或供应商 SRAM Verilog 模型。

## 两个 DC 进程

1. `prepare_sram.tcl`：在库读取前执行 `enable_write_lib_mode`，读原始 SRAM Liberty，只向个人结果目录写 DB。限 60 秒。
2. `check.tcl`：新进程读标准单元/SRAM DB，执行前后 link/check_design、结构 compile、宏计数和网表/DDC 输出。限 120 秒。

两个子进程继承 4 GiB 虚拟地址空间限制。外层检查工具退出码、诊断日志、24 个叶实例和输出非空，最后才打印 `DC_LINK_MACRO_PASS`。限制导致失败时保留日志，不写 PASS。

旧失败根因为 `UIL-91`：默认 DC 会话未启用 write_lib，DB 没有生成，随后出现无法读取 link_library 和未解析引用。独立的库操作进程遵从工具给出的模式要求；许可证仍由现有 EDA 环境正常管理。

## 输入和范围

- 标准单元候选：SMIC40 RVT TT 1.1 V 25°C basic DB。
- SRAM 候选：`RAMSP128X16_tt_1p10v_1p10v_25c.lib`。
- 默认服务器路径写在 Tcl 中；可通过 `KWT1_STD_DB`、`KWT1_STD_LIB_NAME`、`KWT1_SRAM_LIB` 指定其他路径。SRAM logical library 名目前固定为该 TT 候选，换角时须同步调整。
- `rtl/` 是自有测试壳及原有 bridge 的独立快照，不修改团队正式 RTL。名称仍含 fp32，但测试不包含 FP32 PE 运算。
- TT 候选可读不等于比赛最终 PVT 已指定；EMA/EMAW 合法配置也不由该链接检查证明。

## 证据

实际复核：[DC_SRAM_LINK_VERIFIED_20261102.md](../../reports/synthesis/DC_SRAM_LINK_VERIFIED_20261102.md)。

服务器结果入口：`~/kwt1_dc_link_pass_20261102/`。保存 prepare/run 日志、退出码、check_design/reference 报告、宏实例表、输入/输出 SHA-256、DB、DDC 和网表。

库功耗/retention 属性及结构 lint 警告仍存在，详见复核报告。仓库只发布自有脚本、测试 RTL 和人工复核记录，不发布受限库、原始服务器日志、网表、截图或凭据。
