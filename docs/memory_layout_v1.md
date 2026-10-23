# KWT-1 内部存储布局 v1

版本：`memory_layout_v1.1-internal-2026-10-24`
状态：**硬件内部候选接口，未冻结为 E203/SoC 物理地址合同**

## 1. 范围

本文件描述已验收的 `fp32_accelerator_top` 原型使用的地址单位和 tile 内布局。E203 的真实物理地址窗口、缓存属性、System Bus 地址宽度和 SRAM 宏端口仍需平台负责人确认。

- 控制：E203 通过 NICE 适配器发送配置、启动和状态访问。
- 数据：矩阵数据由 System Bus 数据通道搬运，硬件 DMA/缓存模块完成 X、W、bias 的读入和 Y 的写回。
- 地址单位：内部均为 **16 位字地址**，不是字节地址。
- FP32 拆分：每个 FP32 占连续两个 16 位字，低字先、 高字后；字节序由最终 SoC 总线适配器决定，不能直接从本文件推断物理字节地址。
- 矩阵顺序：X、W、bias、Y 均按行主序计算地址。

## 2. 逻辑布局

设外部基地址均为 16 位字地址，`r=t`、`k`、`j` 为全局坐标：

| 数据 | 逻辑元素 | 16 位字地址（低字） | 高字地址 |
|---|---|---:|---:|
| X | `X[r,k]`，形状 `M×K` | `src_a_base + 2*(r*K+k)` | 低字地址 + 1 |
| W | `W[k,j]`，形状 `K×N` | `src_b_base + 2*(k*N+j)` | 低字地址 + 1 |
| bias | `bias[j]` | `bias_base + 2*j` | 低字地址 + 1 |
| Y | `Y[r,j]`，形状 `M×N` | `dst_base + 2*(r*N+j)` | 低字地址 + 1 |

本次真实 layer00 使用 `M=99,K=64,N=256`。计算 tile 为 `ROW_TILE=8,COL_TILE=16,K_TILE=32`；`row_base`、`col_base`、`k_base` 是当前 tile 的全局坐标，尾块通过 `rows_valid/cols_valid/k_valid` 屏蔽越界元素，不对无效输入或 bias 做运算。

## 3. Tile 缓存布局

单个 tile 的内部 16 位字地址从 0 开始：

- A/X：`((local_row*K_TILE)+local_k)*2 + word_high`。
- B/W：`((local_k*COL_TILE)+local_col)*2 + word_high`。
- bias：`local_col*2 + word_high`。
- result：`((local_row*COL_TILE)+local_col)*2 + word_high`。

当前实现用三组逻辑缓存 bank：A、B、result；bias 在加载/计算路径中按既定阶段提供。SRAM 宏的真实端口、容量、读延迟和跨任务持久化方式尚未冻结，不能把当前行为表述成已完成的物理 SRAM 验证。

## 4. K 分块与部分和

`K_TILE=32`。当 `K=64` 时执行两个 K 块：第一块从 `acc=+0` 开始，第二块继续使用第一块的 FP32 部分和；bias 只在完整 K 累加完成后加入一次。无效 K 元素按 0 处理。当前已验证的是 PE/阵列及原型缓存路径，真实 SoC SRAM 保存/恢复仍待平台联调。

## 5. 尚待平台确认

1. `src_a_base/src_b_base/bias_base/dst_base` 到 E203 物理地址的转换和对齐要求。
2. 16 位字地址与 E203 字节地址的转换、字节使能和端序。
3. 四个外部区域是否允许重叠、缓存/不可缓存属性及屏障/fence 规则。
4. System Bus 的 SRAM 宏接口、读响应延迟、写完成定义和错误返回。
5. DONE 之后 CPU 可见的写回排空保证。
