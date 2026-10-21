# memory_layout_v1：内部原型版（未冻结为 E203 地址合同）

版本：`v1.0-internal-2026-10-20`

## 已确定的内部规则

- 数据格式：IEEE-754 binary32 位模式。
- 每个 FP32 用两个 16 位字存储。
- 低 16 位字先存，随后存高 16 位字：
  - `word[2*e] = bits[15:0]`
  - `word[2*e+1] = bits[31:16]`
- X、W、bias、Y 均为行主序。
- X：`A_base + 2*(row*K + k) + half`
- W：`B_base + 2*(k*N + col) + half`
- bias：`bias_base + 2*col + half`
- Y：`Y_base + 2*(row*N + col) + half`
- `half=0` 表示低字，`half=1` 表示高字。

## 当前 tile 内部存储

- A SRAM：当前 K 块的 X，8×32 个 FP32。
- B SRAM：当前 K 块的 W，32×16 个 FP32。
- 第三 SRAM：当前 tile 的 bias。
- PE accumulator：跨 K 块保留部分和。
- `result_stage`：保存加入 bias 后的最终 tile 结果。

阵列 checkpoint 实验另外证明了“部分和写 SRAM—复位—读回—恢复”的阵列级路径，但该路径尚未接入正式 tile/FSM/DMA/top 执行链，因此不改变当前正式原型的 PE 寄存器方案。

## 必须由平台补充的字段

以下字段不能在没有 E203 资料时自行填写：物理地址窗口、CPU 字节地址到字地址的转换、Cache 属性、写缓冲 drain/fence、地址对齐、越界/重叠检查、SRAM 宏端口和时序。
