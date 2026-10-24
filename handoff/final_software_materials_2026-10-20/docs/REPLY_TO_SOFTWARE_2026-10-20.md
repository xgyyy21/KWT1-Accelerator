# 给软件同学的回复：无 E203 条件下硬件材料交付

本轮硬件已整理交付包：`final_software_materials_2026-10-20.zip`。

## 可以直接使用的材料

1. 19 列阵列轨迹：`evidence/pe_trace.csv`，来源包为 `array_pe_trace_2026-10-20_v2.zip`。
2. 存储读回记录：`evidence/word_readback.csv`。
3. 阵列级部分和 SRAM 检查点：`evidence/checkpoint_trace.csv` 和 `evidence/checkpoint_result.csv`，完整包为 `partial_sum_checkpoint_2026-10-20_v4.zip`。
4. 内部存储布局：`docs/memory_layout_v1_internal.md`。
5. 内部控制接口：`docs/control_interface_v1_internal.md`。
6. 特殊值和错误策略草案：`docs/special_value_and_error_policy_v1.md`。
7. RTL、testbench、编译命令和仿真日志：`rtl/`、`tb/`、`evidence/regression_20261020/`。

## 本轮实际结果

- 阵列 4 组共 13,531 个事件：软件侧已逐位核验 13,531/13,531。
- 8×16 SRAM checkpoint：512 写、512 读请求、512 读响应，恢复 128 个 PE 后继续计算，128 个结果正确。
- 协议中立接口三次小任务：9 个输出正确，背压和 DONE 顺序通过。
- 关键回归 testbench 均已编译并通过；完整清单见 `evidence/regression_20261020_summary.json`。

## 需要暂缓标记的内容

- `tb/fp32_competition_ffn1_tb.sv` 已编译，但全尺寸 99×64×256 顶层在 Icarus 下运行过慢，本轮没有 PASS，因此不能作为整层通过证据。
- 真实 E203 NICE 指令映射、System Bus 物理地址、Cache/写缓冲规则、DONE 对 CPU 的可见性、平台 SRAM 宏时序尚未确定。
- NaN、Inf、溢出、总线错误、超时和故障恢复语义需要双方确认。
- 新增三组阵列向量是否加入正式共同黄金集，需要软件和硬件共同确认。

以上材料可用于软件侧继续编写内部原型驱动和验收脚本；正式平台驱动需等待 E203/平台接口资料。
