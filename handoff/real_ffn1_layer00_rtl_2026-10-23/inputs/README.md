# KWT-1 真实模型数据：第 0 层 FFN1 单层联调包

**用途：**用一条真实语音经过固定 KWT-1 模型后产生的第 0 个编码层数据，测试一次 `X[99,64] × W[64,256] + bias[256] → Y[99,256]`。这里交付的是**真实预训练权重与真实层输入**，不是全 1 或人为生成的非均匀矩阵；只有这一层、这一条音频。请在硬件产生实际结果后，再与 `expected` 做逐位比较。本包本身不代表 RTL 已通过。

## 1. 可追溯来源

| 对象 | 身份与本机核验 |
| --- | --- |
| 模型源码 | ARM `keyword-transformer` 固定提交 `237e4097afd4f6851e0b82f0a8d65c2dfe8eae30`。`kwt_runtime_blobs.json` 固定 30 个运行文件，其 SHA-256 为 `fadc11b6dc3e06f69bcf8fb8642e3ba3413db46db89b2882786503ecada3b5b2`。 |
| 预训练权重 | `models_data_v2_12_labels/kwt1/best_weights`：`.index` SHA-256 `5a60a0fa78a1855572084a42669768e2998d37e7d93c833962960fdb0db70fbc`，`.data-00000-of-00001` SHA-256 `ae993f6ed995938c1ab584b0857b35ca18f31f88001c7e17c7d7c3868bd33ad3`。本轮重新核对了原文件哈希；历史导出记录说明 12 层的 24 张 FFN1 权重/偏置张量与 checkpoint 相等。checkpoint 本体不在本包中，**本层所需的 W、bias 已包含**。 |
| 语音 | 历史提取记录将 `source_audio.wav` 标为 Speech Commands v0.02 归档成员 `eight/750e3e75_nohash_0.wav`；复制前后 SHA-256 均为 `d72dd7e4654e12b92a29c1bb247ef30886b632a7a14424ab4abb85e6272ae27a`。尚未用官方 `validation_list.txt` 核实划分，故本包一律标 **`split=unverified`**，不能作为正式验证集样本。 |
| 模型导出环境 | 历史 `model_export_manifest.json` 记录 Python 3.8.20、TensorFlow 2.4.0、TensorFlow Addons 0.12.1、NumPy 1.19.5；上游早期要求的是 TensorFlow `2.4.0rc1`。本轮复用已导出数据，**没有重新运行 TensorFlow 推理**。 |
| 层输入 | `layer_00.npz` SHA-256 `5be944c1d4816fdbefb2a4ff124ff7a62da6540cf74d2ab020bea4130e0e21ce`，与导出 manifest 相符。`x` 为注意力残差及第一处 LayerNorm 后、FFN 第一 Dense 前的 `(99,64)` 输入；`w=(64,256)`，`b=(256,)`。这些数组均为有限 `float32`，W 不转置。NPZ 内另有 TensorFlow 的 `y_float`，**不作为硬件逐位期望值**。 |

`model_export_manifest.json` 是历史模型提取证据；`pack_manifest.json` 是历史第 0 层 FP32 打包清单。两者保留原字段与 `DRAFT` 状态，不代表已冻结 E203 平台接口。`SHA256SUMS.txt` 列出本包每个文件的实际指纹。

## 2. 文件及数值规则

| 文件 | 内容 | 元素 / 16 位字 | `.bin` SHA-256 |
| --- | --- | ---: | --- |
| `x.bin`、`x.mem` | `X[t,k]`，行主序 `t=0..98, k=0..63` | 6,336 / 12,672 | `1036470843aa8096f110adc2a90a7b9888c3654189680510eaf6ac180ee505fc` |
| `w.bin`、`w.mem` | `W[k,j]`，行主序 `k=0..63, j=0..255` | 16,384 / 32,768 | `4c6a8f5171a0ddc5eab198c0acdc4d96d547918bbac97f3b3be8019d42bb188e` |
| `b.bin`、`b.mem` | 256 个 bias，`b[j]` | 256 / 512 | `b305b163000b217514ddfd8ede2745ec428922730f09d351749aa489848bda7e` |
| `expected.bin`、`expected.mem` | 软件计算的 `Y_expected[t,j]`，行主序 | 25,344 / 50,688 | `24c84d16792bd5ab10bedfce5ebfd84a6305495477672d3144044e1ce33a51c5` |

本轮从 `layer_00.npz` **用当前软件分支固定的** `software/fp32_reference.py` 与 `software/pack_fp32.py` 重新生成一次镜像。8 份 `.bin/.mem` 及打包 manifest 与已有层 0 文件**逐字节一致**。所用软件分支 HEAD 是 `d11d169ea6f7b8500d6a2186c803d0f1a5eba709`；两个工具的 SHA-256 分别是 `45daa2c620dcd512ffa2380141cf762477ea25846fc0328027827cfa3842fefb`、`d7b5854f1f8e4a4b0746af035c899c919ae72a3bcfe45cbcc2ae1318aa3a1f3a`。没有用 `y_float` 填充期望文件。

固定软件参考的计算顺序：每个输出从正零开始，`k=0..63` 顺序累加；**每次乘法单独舍入到 binary32，再与部分和相加并单独舍入**；完成全部 K 后 bias 只加一次。不使用 FMA。有限值采用最近偶数舍入与渐进下溢。NaN、Inf、溢出不属于这一组数据及当前已确认的比较范围。`expected.bin` 是这一软件参考的位级期望，不要求与 TensorFlow `y_float` 逐位相同。

## 3. 装载：先确认入口宽度

**加速器内部 16 位字镜像：**`x.mem/w.mem/b.mem/expected.mem` 每行恰好 4 位十六进制，表示一个 16 位字；每个 FP32 元素依次为**低 16 位字、高 16 位字**。对应 `.bin` 文件每个 16 位字又是**低字节、高字节**。可用 `.mem` 初始化 16 位字 SRAM 模型，也可由 `.bin` 拆成 16 位总线写事务。`b` 即 bias。`expected` 只用于检查，不能当成待计算输入。

内部字地址公式（`h=0` 低字、`h=1` 高字）：

```text
X     : A_base    + 2*(t*64  + k) + h
W     : B_base    + 2*(k*256 + j) + h
bias  : bias_base + 2*j           + h
Y     : Y_base    + 2*(t*256 + j) + h
```

上述地址单位是**16 位字，不是字节**；基址应取自实际 testbench/接口配置，并留出互不重叠的窗口。本包**不指定真实 E203 物理地址、NICE 指令编码或 CPU 缓存可见性**。已有功能仿真采用过不同的内部示例基址，不应把示例直接写成平台地址。

**现有 varied FFN1 testbench 的 `+X_FILE/+W_FILE/+BIAS_FILE/+EXPECTED_FILE` 入口不同：**它对 32 位寄存器数组执行 `$readmemh`，要求每行 **8 位十六进制的一个 FP32 位模式**。为避免误把 16 位 `.mem` 塞给它，本包还提供 `x_fp32.mem/w_fp32.mem/bias_fp32.mem/expected_fp32.mem`。它们仅是相邻低、高半字的可核对文本重组，分别有 6,336 / 16,384 / 256 / 25,344 行；`make_tb32_mem.py` 可重新生成并核对。TB 随后会自行把 32 位元素拆成低字、高字写到内部 16 位存储模型。若使用别的 TB 或真实加载接口，先检查其文件行宽，不要将两种 `.mem` 混用。

## 4. 核对硬件结果

1. 固定本包 `SHA256SUMS.txt` 及硬件仿真实际读取文件的 SHA-256；记录 RTL/TB 源码指纹、仿真命令和日志。
2. 确认实际执行的是 **layer 00** 的单次 `99×64×256` 第一线性层任务。记录 208 个 8×16 输出 tile、每 tile 两个 K=32 块及最后 3 行的处理；这些是待核的硬件行为，**不是本包已验证的 RTL 结果**。
3. 对实际输出逐个 `(t,j)` 取原始 FP32 位模式。若输出为半字，按 `Y_base+2*(t*256+j)` 取低字、下一地址取高字，重组为 `low | (high << 16)`；须检查 **25,344 个坐标完整、无重复**。按相同 row-major 顺序与 `expected.bin` 中的 25,344 个 32 位位模式比较。对写回记录还应检查 50,688 个半字的地址、低高顺序和数据。不要只信硬件 CSV 自带的 `match` 栏。
4. 若有首个差异，请报告 `t,j,k`（若可追踪）、软件期望与 RTL 实际的 8 位十六进制位模式、源文件哈希。勿为获得 PASS 改写期望文件。

此样例只支持**真实模型数据的单层功能联调**。它不是 12 层完整推理、合法验证集精度结论、E203/SoC 端到端、物理 SRAM 或 150 MHz/PPA 验收。

## 5. 实际复核与复现命令

本轮在 `software` 工作区调用已有打包器，将层 0 NPZ 输出到**全新的隔离目录**；结果与本包的 8 份主镜像逐字节一致，没有重新下载或训练模型：

```powershell
& '<Python 3.8 + NumPy 1.19.5>' -B -m software.pack_fp32 `
  --input '<本包>/layer_00.npz' `
  --output-dir '<尚不存在的新目录>' `
  --source-id 'eight/750e3e75_nohash_0.wav' `
  --split unverified

& '<Python 3.8 + NumPy 1.19.5>' -B '<本包>/make_tb32_mem.py'
```

实际第一次复核使用的是本机原始 `layer_00.npz` 路径；本包是该文件的逐字节副本。若从本包路径重跑，`manifest.json` 的绝对 `input_file` 字段会改变，8 份数据文件的内容与哈希仍应相同。原始打包与模型导出清单已随包保存。

历史 TensorFlow 提取的**原始 shell 命令全文未保存在导出 manifest**；本轮没有补造一条“当时执行过”的命令。来源由固定模型提交、30 文件指纹、checkpoint 与音频哈希、导出 NPZ 哈希和历史一致性检查支撑。上面的打包命令属于**本轮实际复核流程**，与历史模型推理过程分开。
