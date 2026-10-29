# 测试与验收状态矩阵

| 项目 | 当前状态 | 证据 |
|---|---|---|
| 单 PE 有限值/舍入/特殊边界 | 软件侧已独立核验 | 历史固定提交及软件报告 |
| 8×16 四组阵列轨迹 | 已仿真；软件侧 13,531/13,531 逐位核验 | `array_pe_trace_2026-10-20_v2.zip` |
| K=64 跨块寄存器延续 | 已仿真通过 | 阵列轨迹与 K64 TB |
| 阵列 SRAM checkpoint | 已仿真通过，限阵列检查点端口 | `partial_sum_checkpoint_2026-10-20_v4.zip` |
| 128 个 PE 逐项 checkpoint 结果 | 已由实际 RTL testbench 输出并核对坐标唯一性 | `evidence/checkpoint_result_per_pe.csv` |
| 协议中立接口三次小任务 | 已仿真通过 | `interface_v1_evidence_2026-10-20_run2.zip` |
| 单个 8×16 tile、K=64 完整顶层路径 | 已实际仿真通过 | `evidence/one_tile_k64/` |
| 99×64×256 全尺寸顶层 | 已编译；本轮未取得 PASS | `tests/fp32_competition_ffn1_tb.sv` 与 `evidence/full_ffn1/` |
| 真实 E203 NICE/System Bus | 尚未实现/验证 | 等待平台接口和代码 |
| 物理 SRAM 宏、150 MHz 时序、面积、功耗 | 尚未实现/验证 | 等待综合/平台条件 |
| NaN/Inf/溢出及故障恢复 | 等待双方确认 | `special_value_and_error_policy_v1.md` |
| 新增三组阵列向量是否纳入共同黄金集 | 等待双方确认 | 由软件和硬件共同决定 |

软件侧当前结论应写成“归档证据的软件独立数值核验通过”，不能写成“软件重新运行 RTL 仿真通过”。
