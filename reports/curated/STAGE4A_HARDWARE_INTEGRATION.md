> 阶段4C整理的发布副本：历史结论不变，用户目录/工具目录改用占位符，未入库的原始日志链接标为“仅本地”。原报告保留本地，SHA-256：`bdaa1f443912bb46bb965be03a9d1b050352f46df82650cef2a568179d9fb0d5`。归档索引见 [evidence_index.json](evidence_index.json)，精简验证数据见 [verification_summary.json](verification_summary.json)。

# KWT-1 阶段 4A：硬件工程接入与自动验证

日期：2026-10-17（Asia/Shanghai）。本阶段交付后停止，等待总控 AI 验收。

**结论：硬件模块测试已接入统一检查；本机 Icarus 12.0 真实复跑为 22 项中 16 PASS、6 FAIL，不能复现硬件原环境报告的 22/22。全部 22 项编译成功，六项在仿真中失败。SoC 包装顶层仅编译/展开 PASS；完整 FP32 阵列、完整 FFN1、E203 集成与 12 层连续任务均未验证，不能标 PASS。未修改硬件源码或软件数值模型，未合并、未推送、未安装工具。**

## 1. Git 状态、提交归属和工作保留

开始及结束均在 `codex/stage3a-synthesis-prep`，HEAD 为 `5b2fa0f297f03d2598bb79d7e59c93f974e144f5`。本地 `main` 与原 `origin/main` 为 `b05e081ea393dd3bc16d9a71fb9ae64cdaf9f9fe`。阶段 3A 的 17 个文件已在本分支提交，尚未合并；本轮没有切换、重置、暂存、提交或 stash。

开始时无已跟踪文件修改，有以下四个未跟踪报告，本轮全部保留，未删除或覆盖：

- `reports/STAGE2A_LOCAL_AUDIT.json`
- `reports/STAGE2A_LOCAL_AUDIT.md`
- `reports/basic_check_20261016_214831_212370_009413.json`
- `reports/basic_check_20261016_214831_212370_009413.md`

普通权限下 `git ls-remote --heads origin` 返回退出码 0：

```text
4448aee155f59dc895f83bec3968322160fd66a6 refs/heads/hardware
b05e081ea393dd3bc16d9a71fb9ae64cdaf9f9fe refs/heads/main
```

指定硬件提交属于远程 `hardware` 分支，父提交为上述 `b05e081...`，与综合准备分支分别从同一基础提交发展。GitHub 主站连接不稳定：沙箱首次查询 DNS 失败，后续三次 fetch 均因 github.com:443 连接超时失败，未取得本地硬件 Git 对象或远程跟踪分支；不能把 API 快照写成一次成功的 Git fetch。

随后通过 GitHub 官方 API、Git 已配置认证及固定提交归档成功取得同一版本；凭据只在内存使用，未输出或落盘。逐个计算归档内全部 **70 个 Git blob** 的 SHA-1，与 API tree 比较，0 不匹配。tree 为 `9c9d948a804dbb4e9da49147eea8f1e648d76562`。证据：commit（仅本地：`reports/stage4a/remote_commit.json`）、tree（仅本地：`reports/stage4a/remote_tree.json`）、[SHA-256 清单](../stage4a/hardware_manifest.json)、获取记录（仅本地：`reports/stage4a/acquisition.json`）。

固定快照保留在被忽略的 `tmp/stage4a_remote/snapshot/xgyyy21-KWT1-Accelerator-4448aee155f59dc895f83bec3968322160fd66a6/`，没有导入本工作区的 `rtl/`、`tb/`、`soc/` 或 `software/`。本轮集成代码和报告尚未提交；HEAD 不包含本轮修改，运行以记录的文件哈希追溯。

## 2. 只读审计及测试覆盖

依据硬件提交中的 `docs/HARDWARE_IMPORT_HANDOFF.md`、`rtl/files.f`、两个 PowerShell 脚本、RTL 和 Testbench 审计。交接称导入 46 个开发文件：21 个 RTL SV + 一个文件清单、22 个 TB、两个脚本。本适配器校验并复制 49 个输入（另含两份 `.gitkeep` 和硬件交接文档），每份输入 SHA-256 均记录，运行前后原快照及执行副本源码全部一致。

- `Run-Regression.ps1` 按文件名枚举 `tb/*_tb.sv`，每项用 `iverilog -g2012 -s <TB> -o build/<TB>.vvp -f rtl/files.f <TB路径>` 编译，随后用 vvp 运行，要求退出 0 且出现对应 PASS 标记。最后单独展开 `ai_engine_soc_adapter`；此步骤不计入 22 个 TB。
- `Generate-Fp32Vectors.ps1` 用 .NET `Single` 生成独立加法/乘法期望值，NaN 规范化为 `7fc00000`。21 个边界值两两组合 441 对，加固定 xorshift 种子 `0x12345678` 的 20,000 对随机输入，共 20,441 对。此参考不是完整网络数值模型。
- PE 和阵列是整数功能乘加；`DATA_WIDTH=32` 仍不代表 FP32。`fp32_mac_boundary` 是独立功能边界，未接入阵列，也未实现规定的 FP32 8 拍乘法 + 4 拍加法流水。
- core 由外部提供并行 tile 数据、装载完成和写回确认。寄存器可锁存配置和完成/错误，但 `ai_engine_soc_adapter` 内保存的地址、M/K/N 未驱动真实搬运和完整矩阵执行。`tile_dma` 只有地址/握手原型，没有总线数据请求/响应。缓存、调度、算术还不是完整 FFN1 数据链。
- 收集器已有单次快照排出机制，但没有下游 backpressure；通过独立收集器测试不证明真实总线写回可承受该流量。完整偏置、跨 K 块部分和、FP32 字拆装与缓存调度尚无整层验证证据。

## 3. 实际命令、环境、输入与证据

本机实测编译器、运行器均为 **12.0 (devel) (`s20150603-1539-g2693dd32b`)**；两个 `-V` 命令均退出 0。Windows PowerShell **5.1.26100.9711**，CLR **4.0.30319.42000**；Python **3.11.9**。Icarus 与 vvp 使用同一安装的真实 EXE：

```text
${ICARUS12}/bin/iverilog.exe
${ICARUS12}/bin/vvp.exe
```

从仓库根目录执行的统一入口：

```powershell
python integration/check.py --hardware-source tmp/stage4a_remote/snapshot/xgyyy21-KWT1-Accelerator-4448aee155f59dc895f83bec3968322160fd66a6 --hardware-iverilog ${ICARUS12}/bin/iverilog.exe --hardware-vvp ${ICARUS12}/bin/vvp.exe --context outside-sandbox
```

其在独立 scratch 根目录按交接顺序执行原脚本：先 `powershell -NoProfile -ExecutionPolicy Bypass -File scripts/Generate-Fp32Vectors.ps1 -OutputPath <scratch绝对路径>/build/fp32_vectors.txt`，再执行 `Run-Regression.ps1 -Iverilog <采集包装> -Vvp <采集包装>`。只在调用层固定 cwd、提前生成向量，未修改原脚本中的相对路径问题。命令采集包装直接调用同一 EXE，保存实际原生退出码后透传输出。

实际执行与日志：

| 运行 | 结果 | 证据 |
|---|---|---|
| 初次沙箱模块回归 | 1 PASS / 21 FAIL，入口退出 1；21 次编译返回 `3221225477 / 0xC0000005`，仅 skew 编译/仿真成功；SoC 展开也受限 | 沙箱报告（仅本地：`reports/stage4a/runs/20261017_134001_2a063c3e/report.json`） |
| 普通权限统一入口 | 模块 16 PASS / 6 FAIL；22 次编译退出 0，16 次仿真退出 0、6 次退出 1；SoC 展开退出 0；模块原脚本和统一入口都退出 1 | 模块报告（仅本地：`reports/stage4a/runs/20261017_134122_b37baf18/report.json`）、逐原生命令（仅本地：`reports/stage4a/runs/20261017_134122_b37baf18/native_commands.jsonl`）、原 summary（仅本地：`reports/stage4a/runs/20261017_134122_b37baf18/logs/summary.txt`） |
| 不加采集包装，直接调用原脚本和 EXE | 同样 22 项、六项失败，原脚本退出 1；源文件和向量相同 | 直接复现（仅本地：`reports/stage4a/direct_reproduction/report.json`）、直接 summary（仅本地：`reports/stage4a/direct_reproduction/logs/summary.txt`） |
| 统一检查总览 | 基础检查 PASS；总览 FAIL：25 PASS / 1 FAIL / 18 BLOCKED / 2 NOT_RUN；此处计数是检查项，不能当作 TB 数 | 统一 JSON（仅本地：`reports/basic_check_20261017_134120_891775_2da6b4.json`）、统一 Markdown（仅本地：`reports/basic_check_20261017_134120_891775_2da6b4.md`） |

正式采用普通权限结果判断本机兼容性；沙箱异常单列，不把沙箱崩溃算成 21 个 RTL 设计缺陷。集成首次执行还发现参数名被旧循环变量覆盖，已在集成代码内改名；该次在硬件调用前退出，不计作硬件回归。

普通权限执行副本：`tmp/stage4a_runs/20261017_134122_b37baf18/`。向量实际路径为其 `build/fp32_vectors.txt`，**756,317 字节，20,441 行**；SHA-256：`b3a645b027dd3a1afddf9ca917f3df35fa4e2aa95222b85ba4c481de168b9dcb`。显式生成命令退出 0，FP32 TB 实际输出 `fp32_math_tb PASS pairs=20441`。其余测试刺激在对应 TB 内，TB/RTL/脚本均已按提交清单保存哈希；没有调用或修改软件组数值模型。

每项原始日志均已复制到 `reports/stage4a/runs/20261017_134122_b37baf18/logs/<TB>.compile.log` 和 `<TB>.sim.log`；SoC 为 `soc_elaboration.log`。实际命令、cwd、开始结束时间、返回码及 stdout/stderr 见上述 JSONL；外层命令及版本全文见 report.json 和同目录 commands.log。成功编译的原日志可以为空，退出码记录仍完整。直接复现日志保留在 `stage4a/direct_reproduction/logs/`。

## 4. 逐项结果与可声明范围

下表均来自普通权限真实运行；全部编译退出 0。PASS 仿真退出 0，FAIL 仿真退出 1。

| Testbench | 状态 | 实际覆盖 / 失败表现 |
|---|---|---|
| ai_engine_core_sequence_tb | FAIL | 3×5、K=4、8位整数，非法任务后两次不复位任务的测试；30,000 ns watchdog 超时，未完成该覆盖 |
| ai_engine_core_tb | FAIL | 8×16、K=4、16位整数、全1输入；20,000 ns 超时 |
| ai_engine_fsm_tb | PASS | 装载/计算/写回状态、启动脉冲、完成态再启动、错误恢复 |
| ai_engine_regs_tb | PASS | 配置读写、忙时启动/改配置、DONE/ERROR 保持与清除；不验证真实总线 |
| block_counter_tb | PASS | M=9/N=17/K=65、K_TILE=32，12块尾块与遍历结束 |
| block_descriptor_tb | PASS | 元数据装载、许可/有效标志、完成及重新装载 |
| fp32_mac_boundary_tb | PASS | 1×1+1×1=2，空闲清累加后结果为1；独立功能参考边界 |
| fp32_math_tb | PASS | 20,441 对独立 FP32 加/乘位级参考比较；不覆盖阵列或流水 |
| matrix_buffer_tb | PASS | 旧行为缓存读及无效读；不代表 SRAM 宏 |
| matrix_cache_manager_tb | PASS | 三缓存写/同步读、valid、越界无效；不代表完整端口压力或宏适配 |
| matrix_task_controller_tb | PASS | 12块坐标/尾块、配置锁存和空任务控制；完成由 TB 提供 |
| matrix_task_scheduler_tb | PASS | 99×64×256 的 416 个调度块；只计坐标，不计算完整矩阵 |
| pe_array_8x16_tb | FAIL | 实例参数2×2；`PE array mismatch x`，50 ns 失败 |
| pe_mac_signed_tb | PASS | 有符号负数乘积扩展、极值、无效首项标记及 busy |
| pe_mac_tb | PASS | 单 PE 整数 MAC 人工小样例，期望42和56 |
| systolic_array_8x16_tb | FAIL | 8×16、K=4、全1整数；10,000 ns 超时 |
| systolic_array_reference_tb | FAIL | 8×16、K=4、人工参考 K×(r+1)×(c+2)；10,000 ns 超时 |
| systolic_array_stress_tb | FAIL | 3×5、K=7、8位整数、3任务/气泡/忙时启动/多余拍；30,000 ns 超时，未完成该覆盖 |
| systolic_input_skew_tb | PASS | 3×4 错拍边界延迟、valid 和禁用 |
| tile_dma_tb | PASS | 地址原型普通/末拍停顿、忙时启动；不是总线数据 DMA 验证 |
| tile_result_collector_tb | PASS | 一次完成快照、3×5有效区、15元素顺序/last、配置锁存 |
| tile_stream_adapter_tb | PASS | 未启动屏蔽、start首拍、并行数据传播、stop同拍抑制 |

额外的 `ai_engine_soc_adapter` 编译/展开 PASS，仅证明当前 Icarus 可以解析并展开该包装层。没有 E203 CPU、NICE/System Bus 事务、SDK/驱动或真实 SRAM 数据通路仿真。

## 5. Icarus 14.0 与本机 12.0 的兼容性

按本轮用户提供的信息，硬件原环境为 Icarus 14.0；提交内交接报告记载 portable Icarus 下 22/22、SoC 展开及 20,441 对函数测试通过，但未随附原环境完整版本输出和原始回归日志。本轮没有在 14.0 上独立复测。交接给出的 `D:/competition/.tools/iverilog/bin/iverilog.exe` 与配套 vvp 在本机均不存在，未下载或替换工具。

本机 12.0 通过全部编译，FP32 函数和独立 MAC 边界通过，故不能概括为“不支持 FP32”或语法整体不兼容。但 PE 阵列输出 X、其余阵列/core 超时，使其不能作为复现硬件原回归的等价工具环境。失败集中在涉及多维 unpacked 数组及层次连接的链路，**这只是定位线索，尚不足以断定是 Icarus 缺陷，更不能排除 RTL/TB 问题**；未改 RTL/TB 做归因实验。

保留硬件原 **14.0 环境要求**，不把它写成本轮已认证的最低支持版本；12.0 的 16/22 不视作全回归兼容。需要硬件组提供原 14.0 具体构建、相同提交/向量的原始日志，才能完成两版本归因。即使以后 14.0 复现22/22，也仍不能升级为完整 FP32 阵列或 FFN1/E203 PASS。

## 6. 统一检查接入与验证

新增 [integration/hardware.py](../../integration/hardware.py) 作为薄适配层；[integration/check.py](../../integration/check.py) 新增可选 `--hardware-source`、清单/工具/上下文参数，增加独立的 `hardware_module_regression` 检查项。默认入口仍做原基础检查，不自动取得远程分支。用法见 [integration/README.md](../../integration/README.md)。

复用原脚本枚举和执行测试，不新建测试系统、修改硬件脚本或生成替代 RTL。每次复制到唯一 scratch，记录输入哈希、Git/工具版本、向量、原生及外层退出码、完整日志与源码未变检查。源码与固定提交清单不符时 BLOCKED；日志不含 PASS 或仿真非零时 FAIL；SoC 展开单列。任一模块失败传播为统一入口退出 1，不能被 FP32 函数 PASS 遮盖。

[适配层核验](../stage4a/adapter_validation.json) 记录12项证据完整性/一致性核对全部通过：22项全部计入、45条原生命令（22编译+22仿真+1展开）、失败传播、全部44份模块日志保存、直接原脚本与适配层 summary/退出码/向量一致、输入源码未变、运行脚本哈希一致、统一入口保留整层/SoC BLOCKED。这些是集成层核对，**不能加到22个硬件测试的通过数量中**。

## 7. 可先开展通用综合的模块及缺失依赖

本轮统一检查仍未找到可启动的 Yosys、Design Compiler、Genus。没有运行硬件综合，没有网表、单元统计、正式面积、150 MHz 时序或功耗结论。以下为依据源码结构和当前模块测试提出的接收顺序，不是综合 PASS：

| 范围 | 通用综合准备判断 | 仍需条件/边界 |
|---|---|---|
| ai_engine_fsm、ai_engine_regs、block_descriptor、block_counter | 可优先作为独立控制逻辑练习；对应 TB 本机通过 | 获准可用综合工具、顶层/参数/文件清单；不依赖真实 E203 即可做无 PPA 结论的通用逻辑综合 |
| pe_mac（整数）、tile_dma（地址原型）、matrix_task_scheduler/controller | 可先开展独立模块练习，保留功能原型标签；controller 依赖 scheduler | 冻结参数、有序源文件；DMA 未含真实数据总线，整数 PE 未达规定多周期流水 |
| matrix_buffer、matrix_cache_manager | 可研究行为存储推断和通用资源；不可算成正式 SRAM 实现 | 需审查前端存储/复位支持、读写冲突与宏替换；缺官方 SRAM wrapper、时序/面积/功耗模型 |
| skew、stream adapter、result collector | 独立 TB 已过，可在前端支持 unpacked 数组端口时尝试通用练习 | 收集器无反压；需硬件确认参数/接口及综合器 SV 支持，不修改 RTL 迁就前端 |
| PE阵列、systolic阵列、tile engine、core、SoC包装 | 当前不作为已验证综合基线；可只做后续明确标记的语法/层次诊断 | 先解决本机回归差异、确定支持工具；SoC包装被优化掉的未接配置不能当功能完成 |
| fp32_math_pkg、fp32_mac_boundary | 函数正确性的小范围证据，暂不作为正式 FP32 流水阵列综合方案 | package无独立硬件顶层；缺规定8+4流水、阵列接入和流水TB；功能组合函数的综合成本未验证 |

原 `rtl/files.f` 中路径相对硬件根目录，而阶段3A `synthesis/flow.py` 的清单路径相对清单自身；**不能直接把该文件当作阶段3A清单传入，否则会把路径解析成 rtl/rtl/...**。后续综合需根据经硬件确认的顶层/依赖在集成侧准备适配清单，不改原文件。本轮未自行选最终顶层、未生成正式 SDC 或改综合系统。

完整 FFN1 尚缺：规定 FP32 多周期 PE/阵列及其验证、偏置与跨K部分和、缓存与搬运实际连接、字布局/舍入契约、完整99×64乘64×256数据和逐位对拍、完整写回和12任务轨迹。E203 集成尚缺指定平台工程/版本、内存图、NICE或System Bus最终适配、SDK/工具链、真实驱动/镜像及事务验证。正式综合/PPA 还缺获授权工具、标准单元库/PVT、SRAM宏套件、有效SDC与层次统计口径、真实任务活动及功耗模型；详见阶段3A材料清单。此处缺口不由玩具数据或空壳平台替代。

## 8. 交付状态

交付包含本报告、集成适配代码/说明、固定提交来源及哈希清单、沙箱/普通权限/直接复现日志和统一检查报告。现有综合准备工作、四个原未跟踪报告、硬件快照源码、软件源码均保留；未合并远程分支、未推送、未删除未跟踪文件。最终保留检查见 preservation.json（仅本地：`reports/stage4a/preservation.json`）。

**阶段4A接入完成；硬件全回归复现 FAIL，完整FFN1/E203验收 BLOCKED。停止，等待总控 AI 验收。**
