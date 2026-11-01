# 回复软件同学：Golden 复核与 DMA 版本冻结

日期：2026-11-01

## 对软件复核报告的回应

已收到软件侧对两组 Golden FFN1 RTL 结果的复核。软件侧签收的范围是归档源码快照下的功能数值、输出坐标、写回地址和半字数据；硬件侧不把该结果扩大解释为真实 SRAM 宏、E203/E302 SoC 或 150 MHz 物理时序验收。

## DMA 源码身份已冻结

报告中提到的 `fp32_tile_dma_sequencer.sv` 未提交修改已确认是有意的综合兼容性修复：删除 `always_ff` 中调用的 `advance_half_or_element` task，将状态转移逻辑内联到唯一时序块。

- 固定提交：[`3f6f3d3`](https://github.com/xgyyy21/KWT1-Accelerator/commit/3f6f3d36f6817d84bdcf4fc25eff5eb992ddd115)
- 硬件分支：[`hardware`](https://github.com/xgyyy21/KWT1-Accelerator/tree/hardware)
- DMA 源码：[`rtl/fp32_tile_dma_sequencer.sv`](https://github.com/xgyyy21/KWT1-Accelerator/blob/hardware/rtl/fp32_tile_dma_sequencer.sv)
- 源码 SHA-256：`8f25945b8f222fab45474915f61c3ea3171be1e76161c4472a182e59e254b61b`

该 SHA-256 与软件 Golden 复核报告记录的实际测试文件哈希一致。因此，两组 Golden 结果已经覆盖这份 DMA 修改后的源码字节，不是原始 `995a934` 中的 task 版本。`995a934` 仍保留为历史基线；`3f6f3d3` 是其后的 DMA 综合修复基线。

## 功能回归结果

在 `3f6f3d3` 提交前，使用 Icarus Verilog/vvp 14.0 devel 完成 9 项受影响回归，结果为 **9/9 通过、0 失败、编译和仿真退出码均为 0**。覆盖 DMA、连续任务、阵列 K 分块、SRAM/计算集成、写回和顶层端到端任务。

本地证据目录为 `build/dma_sequencer_inline_regression_2026-11-01_v1/`，该目录属于构建产物，未上传仓库。硬件侧未重新运行两组旧 Golden，因为软件侧已根据源码快照和文件哈希完成独立核验。

## 尚待平台侧提供

以下问题仍未由本提交解决：

1. 比赛实际采用 E203 还是 E302；
2. 固定 SoC 顶层和 CPU 控制通道；
3. 物理字节地址/指令编码、数据搬运方式；
4. DONE 后 CPU 读取结果的可复现证据；
5. 真实 RAMSP128X16 宏模型、E203/SoC 和 150 MHz STA 验收。

本提交没有改变数据布局、控制协议或 DONE 语义。若综合或平台验证发现这些内容需要调整，硬件侧会以新的提交号通知软件并重新评估受影响测试。
