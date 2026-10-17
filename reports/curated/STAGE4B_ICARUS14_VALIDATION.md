> 阶段4C整理的发布副本：历史结论不变，用户目录/工具目录改用占位符，未入库的原始日志链接标为“仅本地”。原报告保留本地，SHA-256：`46cf20910056a4d5014cf1838543b9e10cd550cb433624981a97264023d2ea40`。归档索引见 [evidence_index.json](evidence_index.json)，精简验证数据见 [verification_summary.json](verification_summary.json)。

# KWT-1 阶段4B：Icarus Verilog 14.0 配置与硬件回归

日期：2026-10-17，Asia/Shanghai。硬件提交：`4448aee155f59dc895f83bec3968322160fd66a6`。

**结论：已从 YosysHQ 官方免费发行渠道独立配置 Icarus 14.0。真实最小编译/仿真通过，22/22 模块测试和 SoC 包装展开通过；阶段4A失败的六项全部通过。相同输入下，本轮12.0仍为16/22，原工具未改动并在新版本配置后再次通过基本编译/仿真。仅认定本阶段工具配置及模块回归复现通过，完整FP32阵列、完整FFN1和E203集成仍为BLOCKED。**

## 1. 空间、来源与安装路径

开始时 D 盘可用 `282,161,434,624` 字节，约262.8 GiB；用户已创建的 `D:/EDA-Tools` 为空，目标目录尚不存在，空间足够。没有移动或覆盖原工具。

最终采用 [YosysHQ OSS CAD Suite 官方发布，2026-10-16](https://github.com/YosysHQ/oss-cad-suite-build/releases/tag/2026-10-16)。该发行包含开源 Icarus；[固定发布配方](https://github.com/YosysHQ/oss-cad-suite-build/blob/2026-10-16/default/rules/iverilog.py) 指向上游 `steveicarus/iverilog`。这是 YosysHQ 官方构建的上游软件，不将其写成 Icarus 上游发布的稳定版 Windows 安装器。获取和使用本次开源工具不收费，没有购买许可证或使用破解软件。

| 项目 | 实际记录 |
|---|---|
| 归档 | `oss-cad-suite-windows-x64-20261016.tgz` |
| 下载地址 | [官方 GitHub 发布资产](https://github.com/YosysHQ/oss-cad-suite-build/releases/download/2026-10-16/oss-cad-suite-windows-x64-20261016.tgz) |
| 下载位置 | `D:/EDA-Tools/downloads/oss-cad-suite-windows-x64-20261016.tgz`，Git仓库外 |
| 大小 | 603,907,603 字节（约576 MiB） |
| 官方发布 SHA-256 | `a9620d217a6cd796b38dad1f5acf9eae7fe931d193cd89a9dbe468d86f7cd052` |
| 下载计算 SHA-256 | 与官方发布资产 digest 完全一致 |
| 独立目标目录 | `${ICARUS14}` |
| 编译器 | `${ICARUS14}/bin/iverilog.exe` |
| 运行器 | `${ICARUS14}/bin/vvp.exe` |
| 两者实际版本/构建 | `14.0 (devel) (s20260301-583-g5d7612759-dirty)` |

版本是开发构建，不能写成“正式稳定14.0”。版本全文、编译器各后端版本及实际命令见 14.0基础验证（仅本地：`reports/stage4b/basic_icarus14/report.json`）。硬件交接只给出原portable路径和回归结果，没有具体构建号或原工具哈希；因此本轮复现了22/22，但不能声称与队友是完全相同二进制。

使用 Python 标准库流式读取官方归档，仅提取 Icarus EXE/后端/头文件/许可证、版本元数据及归档根层的原生运行库DLL，保持相对目录，共292文件、365,731,397字节。运行库集合包含发行归档的公共DLL，不声称已经裁剪成Icarus最小依赖集合。没有运行任何安装向导，也没有提取/配置Yosys、布局布线等其他工具的可执行程序。所有目标文件 SHA-256 见 installation.json（仅本地：`reports/stage4b/installation.json`），来源、校验值和固定发行构建配方见 official_download.json（仅本地：`reports/stage4b/official_download.json`）、official_build_recipe.json（仅本地：`reports/stage4b/official_build_recipe.json`）。

构建字符串中的 `dirty` 原样保留。发行方 [构建脚本](https://github.com/YosysHQ/oss-cad-suite-build/blob/2026-10-16/default/scripts/iverilog.sh) 包含交叉编译相关源码调整；本轮未自行编译或修改工具二进制，也不能仅凭这个字符串断定所有构建改动的范围。

没有写用户/系统全局PATH、注册文件关联或卸载注册。只在执行新工具的当前Python进程及子进程中临时把新目录的 `bin`、`lib` 放在DLL搜索PATH前部，完成后恢复该进程原PATH；旧版复核不带此前缀。用户/机器PATH前后快照完全一致。

## 2. 首个候选包的安全拦截与更换来源

最初取得的是 [Bleyer Windows发行维护页](https://bleyer.org/icarus/) 的 `iverilog-v14-20260804-x64_setup.exe`，并按 [Scoop主仓库清单](https://raw.githubusercontent.com/ScoopInstaller/Main/master/bucket/iverilog.json) 校验：27,004,916字节，SHA-256为 `5d65c90c269af75c12ba6e9af6ceb0d64511ea8913d0b2a28eb82e697521cf17`，清单与下载内容一致。这属于第三方Windows打包渠道，校验一致不代表安全。

Windows Defender 随后阻止读取该文件，报告 **`Trojan:Win32/Suschil!rfn`**，SeverityID=5；用户截图显示已隔离。检测记录 `DidThreatExecute=false`。本轮只下载并计算哈希，没有运行、解压或安装这个EXE；尝试只读格式/签名查询时已被系统拦截。没有把告警认定为误报，没有还原/允许该文件、添加排除、停用保护或更改安全设置。记录见 download.json（仅本地：`reports/stage4b/download.json`）、defender_detection.json（仅本地：`reports/stage4b/defender_detection.json`）、defender_threats.json（仅本地：`reports/stage4b/defender_threats.json`）。

依照用户的安全暂停要求，先停止该候选包的安装；用户随后明确要求改用官方免费渠道，才转向不同来源的YosysHQ官方归档。原被隔离EXE保持由Windows安全软件管理，没有借更换扩展名或其他方式提取它。

官方归档的整包 `Start-MpScan` 首次返回“尝试扫描你的设备时遇到错误”，**不计为扫描通过**。提取后，对 `${ICARUS14}` 的独立自定义扫描成功完成，执行前后该新包/目录没有检测记录；实时保护、反病毒与服务状态均启用。证据见 目标目录扫描（仅本地：`reports/stage4b/official_extracted_scan.json`）、执行前检测（仅本地：`reports/stage4b/official_security_detections.json`）、执行后检测（仅本地：`reports/stage4b/official_detections_after_tests.json`）、保护状态（仅本地：`reports/stage4b/defender_status.json`）。这表示本次检查未发现告警，不作绝对安全保证。

## 3. 真实基本运行验证与旧版保护

新旧版本均使用相同最小Verilog源码，实际编译后运行vvp：检查8位255加1得到9位256，失败调用`$fatal`，成功输出 `STAGE4B_ICARUS_SMOKE_PASS`。

| 检查 | 状态 | 实际证据 |
|---|---|---|
| 14.0编译器 `-V`、vvp `-V` | PASS | 均退出0，记录完整版本及构建 |
| 14.0真实编译与仿真 | PASS | 编译0、仿真0，出现正确PASS标记；报告（仅本地：`reports/stage4b/basic_icarus14/report.json`） |
| 原12.0版本与真实编译/仿真 | PASS | 版本/编译/运行全部0；本阶段首次复核（仅本地：`reports/stage4b/basic_icarus12/report.json`） |
| 新工具配置/回归完成后，再用12.0验证 | PASS | 移除子进程新版本PATH前缀后，两个版本命令、编译、仿真均0；再次复核（仅本地：`reports/stage4b/basic_icarus12_after14/report.json`） |

旧版路径保持：`${ICARUS12}/bin/iverilog.exe`、同目录 `vvp.exe`；两者版本仍为 `12.0 (devel) (s20150603-1539-g2693dd32b)`。对整个旧 `app` 安装目录的1228个文件执行前后SHA-256比较，0不匹配，不只是检查两个EXE存在。

## 4. 相同硬件提交、脚本与向量

继续使用阶段4A已按远程Git tree核验的固定提交快照和 `reports/stage4a/hardware_manifest.json`。没有修改RTL、TB、原回归脚本、FP32向量生成器或软件模型。

每次在新scratch目录复用原 `Generate-Fp32Vectors.ps1` 和 `Run-Regression.ps1`：固定cwd为副本根目录，依交接先显式生成FP32向量，再运行原回归。所有49份受检输入哈希在阶段4A、本阶段12.0和14.0之间完全相同，执行前后源码未变。

原脚本会重新生成向量，故不能仅凭“同一生成器”认定输入一致：实际比较三个版本运行及直接复现产生的文件SHA-256，全部为 `b3a645b027dd3a1afddf9ca917f3df35fa4e2aa95222b85ba4c481de168b9dcb`，20,441行、756,317字节；441对边界组合+固定种子 `0x12345678` 的20,000随机对。其余刺激在相同TB中。

| 运行 | 原脚本退出码 | TB结果 | SoC包装展开 | 证据 |
|---|---|---|---|---|
| 阶段4A历史12.0 | 1 | 16 PASS / 6 FAIL | PASS | 历史报告（仅本地：`reports/stage4a/runs/20261017_134122_b37baf18/report.json`），未修改 |
| 阶段4B重新运行12.0 | 1 | 16 PASS / 6 FAIL | PASS | 本轮12.0（仅本地：`reports/stage4a/runs/20261017_135525_78208404/report.json`） |
| 阶段4B官方14.0，逐命令采集 | 0 | 22 PASS / 0 FAIL | PASS | 本轮14.0（仅本地：`reports/stage4a/runs/20261017_140219_05b522e4/report.json`） |
| 官方14.0 EXE完整路径直接调用原脚本 | 0 | 22 PASS / 0 FAIL | PASS | 直接复现（仅本地：`reports/stage4b/direct_icarus14/report.json`） |

继续使用既有适配器，故两次新采集运行按原设计新增在 `reports/stage4a/runs/` 下的唯一目录；这不改写任何阶段4A历史文件。普通权限执行，未使用沙箱崩溃结果判断RTL正确性。

## 5. 22项逐项比较

所有本轮12.0和14.0的22次编译均退出0。12.0失败项仿真退出1，14.0全部22次仿真退出0；原PASS标记均存在。

| Testbench | 阶段4A 12.0 | 本轮12.0 | 本轮14.0 | 历史差异 |
|---|---|---|---|---|
| ai_engine_core_sequence_tb | FAIL | FAIL | PASS | 原30,000ns超时，本轮14.0完成 |
| ai_engine_core_tb | FAIL | FAIL | PASS | 原20,000ns超时，本轮14.0完成 |
| ai_engine_fsm_tb | PASS | PASS | PASS | 一致 |
| ai_engine_regs_tb | PASS | PASS | PASS | 一致 |
| block_counter_tb | PASS | PASS | PASS | 一致 |
| block_descriptor_tb | PASS | PASS | PASS | 一致 |
| fp32_mac_boundary_tb | PASS | PASS | PASS | 一致，独立参考边界 |
| fp32_math_tb | PASS | PASS | PASS | 一致，20,441对函数向量 |
| matrix_buffer_tb | PASS | PASS | PASS | 一致 |
| matrix_cache_manager_tb | PASS | PASS | PASS | 一致 |
| matrix_task_controller_tb | PASS | PASS | PASS | 一致 |
| matrix_task_scheduler_tb | PASS | PASS | PASS | 一致 |
| pe_array_8x16_tb | FAIL | FAIL | PASS | 原 `PE array mismatch x`，本轮14.0通过 |
| pe_mac_signed_tb | PASS | PASS | PASS | 一致 |
| pe_mac_tb | PASS | PASS | PASS | 一致 |
| systolic_array_8x16_tb | FAIL | FAIL | PASS | 原10,000ns超时，本轮14.0完成 |
| systolic_array_reference_tb | FAIL | FAIL | PASS | 原10,000ns超时，本轮14.0完成 |
| systolic_array_stress_tb | FAIL | FAIL | PASS | 原30,000ns超时，本轮14.0完成 |
| systolic_input_skew_tb | PASS | PASS | PASS | 一致 |
| tile_dma_tb | PASS | PASS | PASS | 一致，仅地址/握手原型 |
| tile_result_collector_tb | PASS | PASS | PASS | 一致 |
| tile_stream_adapter_tb | PASS | PASS | PASS | 一致 |

六项历史失败均在14.0消失；16项原通过项没有回退。同一输入下仅更换工具链及其运行库就改变了这六项结果，支持将差异定位到所测工具链构建/兼容性，而非输入向量变化或本轮修改RTL。没有进一步二分编译器提交、单独交叉替换编译器/vvp或制作最小缺陷例，故不宣称已经定位具体上游bug或证明任意14.0构建都可用。冻结实际通过的构建和文件哈希更稳妥。

逐项状态/退出码/哈希比较及11项证据核对见 comparison_final.json（仅本地：`reports/stage4b/comparison_final.json`），全部满足。早期 `stage4b/comparison.json` 是安全拦截期间14.0尚未运行时的中间快照，当前结论以本报告和 `comparison_final.json` 为准。

## 6. 实际日志及可复制命令

14.0的45条原生命令（22编译+22仿真+1展开）、实际cwd、开始结束时间、退出码及stdout/stderr见 native_commands.jsonl（仅本地：`reports/stage4a/runs/20261017_140219_05b522e4/native_commands.jsonl`）。原编译/仿真日志在同目录 `logs/<TB>.compile.log`、`<TB>.sim.log`；另外有 `soc_elaboration.log` 和 summary.txt（仅本地：`reports/stage4a/runs/20261017_140219_05b522e4/logs/summary.txt`）。空编译日志对应无诊断且退出0。

直接使用完整EXE路径执行的原脚本完整argv、退出码和输出见 direct_icarus14/commands.log（仅本地：`reports/stage4b/direct_icarus14/commands.log`），原始日志在该目录 `logs/`。没有用采集包装的结论替代直接原脚本复现。

后续从项目根目录PowerShell复跑采集入口，可临时设置当前进程的DLL搜索路径并恢复：

```powershell
$stage4bPreviousPath = $env:Path
try {
    $env:Path = "${ICARUS14}\bin;${ICARUS14}\lib;$stage4bPreviousPath"
    python integration/hardware.py --source tmp/stage4a_remote/snapshot/xgyyy21-KWT1-Accelerator-4448aee155f59dc895f83bec3968322160fd66a6 --iverilog ${ICARUS14}/bin/iverilog.exe --vvp ${ICARUS14}/bin/vvp.exe --context stage4b-icarus14-official
} finally {
    $env:Path = $stage4bPreviousPath
}
```

新工具配置位置、版本和子进程环境记录在 icarus14_run_pointer.json（仅本地：`reports/stage4b/icarus14_run_pointer.json`）。本轮未修改集成代码；沿用参数指定新旧路径。

## 7. 功能和工程阻塞仍保留

- FP32向量验证的是独立加/乘函数，`fp32_mac_boundary`只验证小功能边界。整数PE/阵列测试通过不代表完整FP32阵列或规定8拍乘法+4拍加法流水通过。
- 完整FFN1仍缺偏置、跨K部分和、完整缓存/搬运/写回链和正式数值/布局契约、完整99×64乘64×256逐位对拍与12层真实任务证据。
- SoC包装只有编译/展开，不是E203 CPU、NICE/System Bus、驱动、共享SRAM和真实事务集成。指定平台工程、SDK/内存图/协议和运行证据仍缺。
- 本轮不开展逻辑综合、150MHz达标、正式面积或功耗评估；库/PVT/SRAM宏/有效SDC/活动和获准后端等依赖沿用阶段3A、4A清单。没有因为下载归档包含其他EDA软件而自动扩展阶段任务。

## 8. 文件与Git保护、交付状态

分支仍为 `codex/stage3a-synthesis-prep`，HEAD仍为 `5b2fa0f297f03d2598bb79d7e59c93f974e144f5`，本地main仍为 `b05e081ea393dd3bc16d9a71fb9ae64cdaf9f9fe`。原阶段4A未提交的 `integration/check.py` 修改及其他未跟踪文件完整保留，没有reset、切分支、stash、暂存、提交、推送或合并。

本阶段新增：本报告、`reports/stage4b/`的来源/安全/版本/比较/保护证据、两个 `reports/stage4a/runs/` 唯一运行目录。临时源码副本/向量/仿真文件在被忽略的 `tmp/`，归档及工具在仓库外 `D:/EDA-Tools`。没有修改任何已有集成/综合脚本、队友源码、TB、软件模型或阶段3A/4A历史证据；没有把安装包、工具或临时产物提交GitHub。

对开始时177份已有项目文件和1228份旧工具文件执行前后SHA-256比较，全部一致。`git diff --check`通过。Git状态详见 preservation.json（仅本地：`reports/stage4b/preservation.json`），全局PATH对比见 path_validation.json（仅本地：`reports/stage4b/path_validation.json`）。

**阶段4B配置与模块回归复现已完成。停止，等待总控AI验收。完整FP32阵列、FFN1和E203集成状态不因本阶段22/22而升级。**
