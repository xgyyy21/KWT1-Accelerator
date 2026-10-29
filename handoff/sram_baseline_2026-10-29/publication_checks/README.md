# 推送前导入核查

本目录核查发生在独立发布 worktree，未覆盖 `D:\competition` 原工程。

1. `exceptions/status.json`：实际重新运行 Icarus 五组测试，5通过/0失败；编译与仿真退出码均为0。包含SRAM、故障guard候选模块、原bus adapter、控制寄存器和K-block FSM。目录保留源码与日志，省略可重新编译的`.vvp`；原manifest仍保留这些省略项。
2. `reference/comparison_summary.json`：导入后的固定归档CSV重新经过软件参考复算，31,680输出、63,360半字写回匹配，无首个差异。这**不是重新运行完整 RTL**，也不是软件同学独立验收。
3. `source_identity_check.json`：导入源码与本地原工程逐文件SHA一致，并与双完整任务仿真使用的主RTL快照一致。

本次没有新增算术功能，只固定既有成果；没有把通过范围扩大到真实SRAM宏时序、E203或正式综合PPA。
