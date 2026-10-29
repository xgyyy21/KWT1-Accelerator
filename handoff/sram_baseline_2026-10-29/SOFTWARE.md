# 给软件同学：本轮 Git 材料入口

## 主要结果

连续任务 `99×64×256`、`99×256×64` 在同一实际 RTL 仿真中执行，中间不复位、不清 SRAM。两组输入不同，X/W/bias 重新装载。共 31,680 输出及 63,360 次 16-bit 写回全部匹配参考；本轮尚待软件侧独立核验。

请从 [输出 CSV](evidence/sram_two_layers_verilator_2026-10-29_v1/outputs.csv)、[逐半字写回](evidence/sram_two_layers_verilator_2026-10-29_v1/writeback.csv)、[输入](evidence/sram_two_layers_verilator_2026-10-29_v1/inputs.csv)、[tile](evidence/sram_two_layers_verilator_2026-10-29_v1/tiles.csv) 和 [控制轨迹](evidence/sram_two_layers_verilator_2026-10-29_v1/control.csv) 开始。

- [实际仿真日志](evidence/sram_two_layers_verilator_2026-10-29_v1/simulation.log)
- [实际退出码与来源](evidence/sram_two_layers_verilator_2026-10-29_v1/status.json)
- [软件参考复算结果](evidence/sram_two_layers_reference_check_2026-10-29_v1/comparison_summary.json)
- [五组异常/控制回归结果](evidence/sram_exceptions_verified_2026-10-29_v2/status.json)

SRAM 最终测试计数：3091 写、3096 读请求、3093 读响应、3 次复位取消；覆盖 3072 words、127/128 与1023边界、单端口/低高半字、反压保持、standby、复位保留存储。控制 ERROR 的清除和重启由单元测试核查；未宣称在完整层任务中注入总线错误后自动恢复。超时保护只做独立原型，不是已接入的 E203 功能。

## 复算归档输出（不重新运行 RTL）

在仓库根目录，用 Python 标准库：

```text
python scripts/Check-SramTopEvidence.py --two-layers --evidence handoff/sram_baseline_2026-10-29/evidence/sram_two_layers_verilator_2026-10-29_v1 --output build/software_sram_recheck --reference handoff/sram_baseline_2026-10-29/reference/fp32_reference.py
```

`--output` 必须是新目录。输入每行代表一个 FP32 及其低半字 word 地址，写回每行才代表一个实际 16-bit 传输；内部地址不是 E203 物理 byte 地址。

## 重新运行 RTL

Icarus 的针对性回归：

```text
python scripts/Test-SramExceptionEvidence.py --output build/sram_exceptions_replay --icarus-bin <iverilog.exe和vvp.exe所在目录>
```

主 runner 面向 Windows Icarus。双完整任务在已有本机 MSYS2/UCRT64 Verilator 环境中：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/Test-SramFullLayerVerilator.ps1 -TwoLayers -OutputDirectory build/sram_two_layers_replay
```

需另备 `.tools/msys64`，工具不入库。其他平台可依据归档 `compile_command.txt`、`simulation_command.txt` 重建并传入 `+OUT_DIR=<输出绝对目录>`，不要依赖本机未上传二进制。

详细字段定义、检查覆盖和局限见 [原软件交接说明](docs/给软件同学_连续任务与16位SRAM联调材料_2026-10-29.md)；原 `build/...` 证据路径现映射至本目录 `evidence/...`。
