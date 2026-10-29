# KWT-1 `memory_layout_v1`（内部候选版）

版本：`memory_layout_v1.2-internal-2026-10-25`  
状态：**硬件内部原型约定，尚未冻结为 E203/SoC 物理地址合同**

## 1. 通道职责

- NICE：由 E203 发送配置、启动和状态访问。
- System Bus：搬运 X、W、bias 的数据半字，并将 Y 半字写回外部存储。
- 当前 RTL 的 NICE/System Bus 端口是协议中立端口，最终平台包装器仍需适配真实 E203 信号。

## 2. 数据格式与地址单位

- X、W、bias、Y 使用 IEEE-754 binary32 位模式。
- 内部地址单位是 **16 位字地址**，不是字节地址。
- 每个 FP32 占连续两个 16 位字，低字先、高字后：
  - `word[2*e] = bits[15:0]`
  - `word[2*e+1] = bits[31:16]`
- X、W、bias、Y 均按行主序计算逻辑地址。

## 3. 外部逻辑布局

设 `r` 为行、`k` 为 K 坐标、`j` 为列，所有 base 均为 16 位字地址：

| 数据 | 逻辑元素 | 低字地址 | 高字地址 |
|---|---|---|---|
| X | `X[r,k]` | `src_a_base + 2*(r*K+k)` | 低字地址 + 1 |
| W | `W[k,j]` | `src_b_base + 2*(k*N+j)` | 低字地址 + 1 |
| bias | `bias[j]` | `bias_base + 2*j` | 低字地址 + 1 |
| Y | `Y[r,j]` | `dst_base + 2*(r*N+j)` | 低字地址 + 1 |

当前竞赛层为 `M=99,K=64,N=256`。硬件 tile 为 `8×16`，K 分块使用 `K_TILE=32`。

## 4. Tile 内部布局

- A/X：当前块的 `8×32` 个 FP32。
- B/W：当前块的 `32×16` 个 FP32。
- bias：当前 tile 的 16 列 bias。
- result：当前 tile 的 `8×16` 结果。
- 逻辑 bank 中的每个 FP32 仍占两个 16 位字，低字地址在前。

## 5. K 分块与边界

- 每个 tile 最多执行两个 K 块（对 `K=64`）。
- 第一个 K 块从 `acc=+0` 开始，后续 K 块继续使用 PE accumulator 的部分和。
- bias 只在完整 K 累加完成后加入一次。
- 不足完整 tile 的行、列和 K 元素由 `rows_valid`、`cols_valid`、`k_valid` 屏蔽，不对无效元素执行乘加或 bias。
- 阵列 checkpoint 的 SRAM 保存/恢复证据独立存在，但当前正式计算路径默认由 PE accumulator 保持跨块部分和。

## 6. 必须由平台确认的字段

以下内容不能在没有 E203 资料时自行填写：

1. `src_a_base/src_b_base/bias_base/dst_base` 对应的物理地址窗口。
2. CPU 字节地址到 16 位字地址的转换、对齐、端序和 byte-enable。
3. Cache/不可缓存属性、写缓冲 drain/fence 和 DONE 后 CPU 可见性。
4. System Bus 的实际读延迟、写完成定义、错误返回和 outstanding 数量。
5. SRAM 宏容量、端口、读写时序和跨任务持久化策略。

