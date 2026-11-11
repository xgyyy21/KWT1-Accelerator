# 权重缓存 SRAM 映射修复交接

日期：2026-11-11

## 变更目的

综合侧发现二维 unpacked 数组

```systemverilog
logic signed [15:0] weight_cache [0:63][LANES];
```

在 DC 中没有被推断为存储器，导致整个权重缓存保留为未映射 GTECH 逻辑。此次改动将它替换为 `int16_weight_sram_16bank`，由 16 个独立的 128×16 单端口 bank 组成。每个 bank 对应一个输出列，地址为 K 维索引；K=64 只使用地址 0～63，剩余地址保留给宏深度。

## RTL 改动

- `rtl/int16_weight_sram_16bank.sv`
  - 正式宏编译时定义 `INT16_USE_RAMSP128X16`，生成 16 个 `RAMSP128X16` 实例。
  - 宏端口使用 `CLK/CEN/GWEN/WEN/A/D/Q/EMA/EMAW/RET1N`。
  - 当前静态配置为 `EMA=2`、`EMAW=3`、`RET1N=1`。
  - 未定义宏时提供一维 `mem[0:LANES*128-1]` RTL 功能模型，仅用于本地仿真。
  - 每个 bank 每拍最多一次读或写；32 位总线响应可同时写入两个不同 bank。

- `rtl/int16_accelerator_top.sv`
  - 删除二维 `weight_cache` 存储。
  - 增加缓存写入总线及 `S_CACHE_RD_REQ/S_CACHE_RD_WAIT` 状态。
  - 权重加载完成后，读请求在 SRAM 采样沿发出，下一拍等待 `cache_rd_valid` 后装载 `b_vector`，再进入 MAC。
  - 保留原有 `weight_cache_valid` 错误失效语义和最终 PE 结果事件锁存修复。

- `rtl/files.f`
  - 加入 `rtl/int16_weight_sram_16bank.sv`。

## 本地功能回归

工具：Icarus Verilog/VVP（`D:\competition\.tools\iverilog\bin`）。

- `tb/int16_accelerator_top_tb.sv`：K64、K256、连续任务及缓存重新装载，PASS。
  - `TRAFFIC_K64 W=576 BIAS=18`
  - `TRAFFIC_K256 W=2048 BIAS=16`
  - `TRAFFIC_K64_RELOAD W=512 BIAS=16 Y_WRITES=8`
  - `PASS CACHE_ERROR_INVALIDATION cache_valid=0`
- `tb/int16_software_handoff_tb.sv`：真实 layer00 `99×64×256`，PASS。
  - 输出 25344 个，写回 12672 次
  - System Bus 命令/响应 `71808/71808`
  - 权重读取 8192 次，bias 读取 256 次
  - `mismatches=0`，`first_bad=-1`
  - 仿真周期数 `735508`

Icarus 的 constant-select 提示和 testbench `$fatal` 综合提示仍为既有工具警告，不是本次改动导致的错误。

## 综合侧运行要求

服务器 DC 需要在宏模型/库文件可见的前提下，使用：

```text
INT16_USE_RAMSP128X16
```

作为 Verilog/SystemVerilog 编译宏，使 `int16_weight_sram_16bank` 进入真实 `RAMSP128X16` 实例路径。若服务器脚本不自动定义该宏，请在 compile/elaborate filelist 中增加对应 define；不能用本地一维 fallback 作为最终面积结果。

请按原口径重新运行：

1. K64 与 K256 RTL 仿真；
2. 真实 layer00 `99×64×256` RTL 仿真；
3. 使用真实 `RAMSP128X16` 库的 DC 综合和 unmapped logic 检查；
4. 如冻结网表已存在，再进行 RTL↔网表等价检查。

本地测试只能证明功能模型下的 RTL 数值和同步读时序；本次尚未生成目标工艺 DC 面积、时序或 PPA 结论。
