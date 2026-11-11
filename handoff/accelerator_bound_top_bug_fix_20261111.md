# Final4 绑定顶层 `S_RESULT` 超时候选修复

日期：2026-11-11  
基线：`d7329f200832697a4946bada5b72bf7db5b4ed7c`  
修复分支：`bugfix/accelerator-bound-result-latch-20261111`

## 问题

综合侧复现报告指出，Final4 服务器专用顶层
`int16_accelerator_top_bound.sv` 在 K=64 最后一个 `k=63` 后进入
`S_RESULT`，但没有观察到 `pe_result_valid`，最终不写回并超时。报告中总线命令/响应为 560/560，且没有 `ERROR`，所以问题位于顶层收尾状态机或权重缓存路径，而不是 PE 数值逻辑。

复现材料位于只读快照：

`handoff/accelerator_bound_top_bug_20261111/`

该快照没有提交服务器专用绑定顶层源码，只提供服务器文件路径、TB、日志和哈希清单。

## RTL 修改

修改文件：

`rtl/int16_accelerator_top.sv`

新增 `pe_result_seen_q`：

- 复位和新任务 START 时清零；
- 在 `S_MAC` 观察到 `pe_result_valid` 时置位；
- `S_RESULT` 接受当前 `pe_result_valid` 或已锁存事件；
- 进入写回时清除保持位。

这只保护 PE 结果有效事件，不改变 INT16 算术、RNE、饱和、权重缓存内容、System Bus 宽度、SRAM wrapper、网表、DDC 或 SDC。

## 本地回归

候选版本在独立工作副本中使用 Icarus/VVP 验证：

- K64 + K256 连续任务：PASS；
- 连续任务和缓存重新装载：PASS；
- layer00 `99×64×256`：PASS；
- layer00 输出：25,344 个，逐位匹配；
- layer00 写回：12,672 次；
- 命令/响应：71,808/71,808；
- mismatch：0；
- 行为级周期：529,456。

layer00 结果来自通用顶层，不是服务器专用绑定顶层的最终复核。

## 服务器侧必须完成

请将同样的 `pe_result_seen_q` 修改应用到服务器实际使用的
`int16_accelerator_top_bound.sv`，然后重新执行：

1. K64、K256 和连续任务 VCS 回归；
2. 真实 `99×64×256` layer00 回归；
3. 重新综合；
4. RTL 与冻结网表的 Formality/LEC 等价检查；
5. 回传修改后绑定顶层 SHA-256、filelist、命令、日志、退出码和新固定 commit。

在服务器结果返回前，本提交只能作为候选修复，不能表述为 Final4 已完成最终修复或已通过正式 PPA/等价签核。
