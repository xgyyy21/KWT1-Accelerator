# DC 标准单元与 RAMSP128X16 库链接实际复核

日期：2026-11-02，Asia/Shanghai。

## 实际结论

通过用户提供的 VNC/RFB 客户端认证并操作比赛服务器，在个人新目录完成两次 DC 启动：第一进程准备 SRAM DB；第二进程读取标准单元/SRAM DB，执行 analyze、elaborate、link、check_design、小型结构 compile、再次 link/check_design，并写出网表与 DDC。

结果：`DC_LINK_MACRO_PASS`，外层退出码 0，DB 准备进程退出码 0，编译检查进程退出码 0。编译前后均有 24 个 RAMSP128X16 叶实例；读取后的库 cell 为 `RAMSP128X16_tt_1p10v_1p10v_25c/RAMSP128X16`。扫描编译日志，未解析引用及工具错误计数为 0。

该结果仅覆盖旧版三 bank 测试壳的库链接、结构编译及宏保留。尚未运行 INT16/完整加速器综合、150 MHz 约束验证、STA、功能等价或 PPA。

## 旧失败的根因

服务器旧日志：`~/kwt1_dc_run3/dc_sram_macro_check_20261102/results/run.log`。

- 第 72 行报 `UIL-91`：当前 DC 未启用 write_lib，提示在新会话启用 `enable_write_lib_mode` 或使用 lc_shell。
- 个人 SRAM DB 未生成。后续出现 `Can't read link_library file`、`LINK-5`、`LBR-1` 和 `UID-341`。
- 旧 Tcl 报错后仍继续执行，实例数量也只能证明名字存在，不能证明链接成功。
- 旧外层脚本已能打印 `DC_FAIL unresolved reference detected`，但 Tcl 内部的 PASS 标记依然不可靠。

原始 Liberty 能读入，失败依据并不支持“工艺库损坏”。

## 修复

1. 独立 DC 进程在任何库读取前执行 `enable_write_lib_mode`，只进行库操作并写入个人 DB。
2. 另起 DC 进程读取该 DB；标准单元放 target_library，SRAM DB 放 link_library。
3. Tcl 使用 catch/failure 文件及非零退出；检查 link/check_design/compile 返回值、库内宏 cell、24 个叶实例和输出非空。
4. Bash 保存工具/日志退出码、扫描真实错误诊断，最后才写 PASS。两进程分别限 60/120 秒，虚拟地址空间上限 4 GiB。
5. 原始 RTL、旧结果和公共库均保留；没有把工艺文件复制到 Windows，也没有调用第三方模型。

## 服务器证据

- 个人脚本目录：`/storage1/2026contest/server3/s3_30usr/kwt1_dc_link_jk9nlvtb/`
- 结果目录：`/storage1/2026contest/server3/s3_30usr/kwt1_dc_link_jk9nlvtb/results_admj3I3a/`
- 易用入口：`~/kwt1_dc_link_pass_20261102/`（已创建并核对目标的符号链接）。
- 原始证据：`prepare.log`、`run.log`、`prepare_exit_code.txt`、`dc_exit_code.txt`、`tee_exit_code.txt`、`checks.txt`、`summary.txt`、`loaded_libraries.rpt`、`check_design_pre.rpt`、`check_design_post.rpt`、`references_pre.rpt`、`references_post.rpt`、`macro_instances_pre.txt`、`macro_instances_post.txt`、`inputs.sha256`、`outputs.sha256`。
- 输出：`sram_macro_check.ddc`（ls 显示约 312 KiB）、`sram_macro_check_netlist.v`（约 476 KiB）。
- SRAM DB：`RAMSP128X16_tt_1p10v_1p10v_25c.db`，实测 52,224 bytes。
- 第二 DC 进程自报 elapsed 14 seconds，内存 547 Mbytes。不是独立 OS 采样的性能或峰值测量。

库候选：

```text
STD_DB=/storage1/2026contest/server3/s3_30usr/kwt1_smic40_lib/S40/smic/SCC40NLL_VHSC40_RVT_V0.1/SCC40NLL_VHSC40_RVT_V0p1/liberty/1.1v/scc40nll_vhsc40_rvt_tt_v1p1_25c_basic.db
SRAM_LIB=/storage1/2026contest/server3/s3_30usr/Desktop/admin_public_dir/SRAM_Lib_2025/RAMSP128X16/lib/RAMSP128X16_tt_1p10v_1p10v_25c.lib
```

这是已验证可读取/链接的 TT 候选组合，不代表比赛最终指定 VT/PVT。

## 仍存在的 warning

SRAM 库读入：NLPM 缺 internal_power_calculation（LDBB-366）；EMA[2]/EMAW[1] 缺 internal_power group（LDBB-607）；RET1N retention 属性不完整（LDBB-982）。库准备会话的 UIL-93 提示仅进行库操作，已通过分进程满足。

结构报告后编译计数：Shorted outputs（LINT-31）138；Constant outputs（LINT-52）288；Unloaded nets（LINT-2）144。存在网表 assign/tran 输出提示 VO-4。检查命令返回成功不等于零 warning；本轮只核对其类别，未逐条完成连接/功能审查，不能由本报告宣称这些项均无害。

## 可复现命令

服务器现有脚本可直接重用，不需重新上传：

```sh
bash ~/kwt1_dc_link_jk9nlvtb/run_dc.sh
```

每次写新的 results_XXXXXXXX。现有公共库与旧结果不被覆盖。

## 本地可复用脚本与身份核对

仓库可复用入口：`synthesis/dc_sram_link/run_dc.sh`，说明见 [README](../../synthesis/dc_sram_link/README.md)。本地原始实验目录仍保留为 `D:/KWT1-Accelerator/tmp/dc_sram_link_strict_20261102/`。

三份已部署脚本的服务器 sha256sum 与本地计算一致：

```text
a5f2f51edafce12b4835e61f4f46224bc3cab65ecc1c8129ef8c87013c62b67d  check.tcl
1b6fbb760e3f07bb01ee94ff05425d4144b6932e4a06c24aa674968cff83661b  prepare_sram.tcl
ecc2fe29d0079eb10566b25e9fc8138452d656f961fa7546475c6ebf23e2e25c  run_dc.sh
```

本地留存了 VNC 回读截图 `artifacts/vnc/dc-link-compile-pass-20261102.png` 和 `artifacts/vnc/dc-link-summary-20261102.png`，截图未发布到 GitHub。服务器原始日志保留在服务器，未下载工艺库/DB/网表；仓库内本报告是依据界面回读整理的记录，不是原始日志副本。完成后追加一次只读警告查询时本地 VNC 客户端断开；该次查询结果未被本报告用作证据，不影响此前已完成并保存的 DC 运行。
