# 硬件侧交付材料索引

本目录对应硬件分支本次提交，供软件和综合同学浏览。材料来源于 2026-10-20 的本地硬件快照；本次提交固定了源码、testbench、CSV、文档和日志，不包含仿真二进制、工具安装包或压缩归档。

## 可直接使用

- `handoff/final_software_materials_2026-10-20/evidence/pe_trace.csv`：19 列阵列轨迹。
- `handoff/final_software_materials_2026-10-20/evidence/word_readback.csv`：存储读回记录。
- `handoff/final_software_materials_2026-10-20/evidence/checkpoint_trace.csv`：512 写、512 读请求、512 读响应。
- `handoff/final_software_materials_2026-10-20/evidence/checkpoint_result.csv`：当前 checkpoint 汇总结果。
- `handoff/final_software_materials_2026-10-20/docs/memory_layout_v1_internal.md`：内部存储布局。
- `handoff/final_software_materials_2026-10-20/docs/control_interface_v1_internal.md`：内部控制接口。
- `handoff/final_software_materials_2026-10-20/docs/special_value_and_error_policy_v1.md`：特殊值和错误策略草案。
- `handoff/final_software_materials_2026-10-20/docs/test_and_acceptance_matrix.md`：测试状态矩阵。

## 当前验证边界

- 4 组阵列轨迹共 13,531 个事件已由软件侧逐位核验。
- 关键单 PE、阵列、K=256 小任务、checkpoint 和协议中立接口 testbench 已有回归日志。
- `tb/fp32_competition_ffn1_tb.sv` 已编译，但完整 `99×64 × 64×256` 仿真本轮没有完成，不能标记为整层 PASS。
- checkpoint 当前是阵列检查点实验，尚未接入正式 DMA/FSM/顶层执行链。
- 真实 E203 NICE、System Bus 物理地址、CPU 可见性、异常恢复和物理 PPA 仍待平台条件。

## 复现入口

RTL 文件列表：`rtl/files.f`。

关键 testbench：`tb/fp32_array_checkpoint_tb.sv`、`tb/fp32_tile_kblock_load_compute_k256_tb.sv`、`tb/interface_v1_top_tb.sv`、`tb/fp32_competition_ffn1_tb.sv`。

回归日志和结果：`handoff/final_software_materials_2026-10-20/evidence/regression_20261020/`、`regression_20261020_summary.json`。

本提交不代表 E203/SoC 已接入，也不代表完整 FFN1 已通过。
