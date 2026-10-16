# KWT-1 阶段 3A：综合环境调查与最小流程

日期：2026-10-16（Asia/Shanghai）。交付总控 AI 验收；本阶段结束后停止。

**结论：调查与最小报告框架已完成；实际通用综合 BLOCKED，正式综合/PPA 未开展。没有可用的 Yosys、Design Compiler 或 Genus 命令，未安装或下载任何工具。小例子通过 Icarus 仿真，但没有综合网表、逻辑资源统计、面积、时序或功耗实测成绩。**

## 1. 范围与仓库状态

- 工作分支：`codex/stage3a-synthesis-prep`，由 `main` 的 `b05e081ea393dd3bc16d9a71fb9ae64cdaf9f9fe` 创建。只作本地开发和本地保存，不推送、不合并。已有 origin 仅用 `git remote -v` 读取，未联网操作远端。
- 未修改 `software/`、`rtl/`、`tb/`、`soc/`、`integration/`、现有 docs、README、CONTRIBUTING 或 `.gitignore`。旧管理文档中“本阶段不编写综合脚本”指阶段 1；本次新增练习入口依据用户明确授权，不改写历史状态。
- 开始时已有四个未跟踪文件：两份 `STAGE2A_LOCAL_AUDIT.*` 和两份 `basic_check_20261016_214831_212370_009413.*`，原样保留，不纳入本阶段提交。
- 日志是在上述 HEAD 且有新增文件的工作区生成，均记录 dirty=true 和实际脚本/输入哈希；不把该 HEAD 描述为包含本轮脚本的版本。交付提交以本分支 `git log -1` 为准。

## 2. 本机工具实际检查

完整 argv、版本全文、返回码及输出见 `synthesis/runs/*environment*/report.json` 和同目录 `commands.log`。最终普通权限环境记录为 `20261016_234304_environment_2c069586`；首次受限沙箱记录为 `20261016_234108_environment_7a9e37f3`。中间复核 `20261016_234210_environment_9ab34613` 也保留。

| 工具 | 实际版本 / 命令 | 本轮结论 |
|---|---|---|
| Yosys | `yosys -V`：WinError 2；六个常见本地候选路径均无文件 | BLOCKED：当前 Windows 命令环境无可用工具；Ubuntu PATH 也报告 MISSING |
| Synopsys Design Compiler | `dc_shell -version`、`dc_shell-t -version`：WinError 2 | BLOCKED：当前 Windows 命令环境不可启动；Ubuntu 无 dc_shell；许可未核验 |
| Cadence Genus | `genus -version`：WinError 2 | BLOCKED：当前 Windows 命令环境不可启动；Ubuntu 无 genus；许可未核验 |
| Verilator | `verilator --version`：WinError 2 | BLOCKED：当前 Windows 和 Ubuntu PATH 未找到；不是已完成 lint |
| Icarus Verilog / vvp | 12.0 devel，`s20150603-1539-g2693dd32b`；`iverilog -V` / `vvp -V` | PASS（沙箱外）：实际编译、运行均 0，输出 `STAGE3A_ICARUS_OK`；仿真工具，不是综合器 |
| Git | 2.55.0.windows.3；`git --version`、`rev-parse --is-inside-work-tree` | PASS：实际读取仓库、提交和分支 |
| Python | 3.11.9，MSC v.1938 AMD64；版本及标准库导入命令 | PASS：实际执行脚本、子进程、JSON/哈希等功能 |
| WSL | 2.7.11.0；内核 6.18.33.2-2；`--status` / `--list --quiet` / `--exec sh -lc ...` | PASS（沙箱外）：默认 Ubuntu，WSL2，Ubuntu 24.04.1 LTS，shell 输出 Linux；另有 docker-desktop 发行版 |
| Docker | 客户端/Engine 29.6.2；Docker Desktop 4.85.0 (235549) | PASS（沙箱外）：`docker version`、`docker info --format ...` 返回 0，Server 为 linux/amd64；未拉镜像或运行新容器 |

Windows 已解析的主要路径：Icarus/vvp 为 WindowsApps 的 `.CMD` 包装，Git 为 `C:/Program Files/Git/cmd/git.exe`，Python 为 `C:/Users/pc/AppData/Local/Programs/Python/Python311/python.exe`，WSL 为 `C:/Windows/system32/wsl.exe`，Docker 为 `C:/Users/pc/AppData/Local/Programs/DockerDesktop/resources/bin/docker.exe`。完整绝对路径已在机器日志保留。

受限沙箱中 Icarus 编译返回 `3221225477 / 0xC0000005`，WSL 返回 `Wsl/E_ACCESSDENIED`，Docker 命名管道拒绝访问；版本命令成功不能替代功能检查。经获准的沙箱外复核通过后，结论是这些操作受执行环境影响，不要求重装。脚本不自行提权或改变权限。

调查边界：检查 PATH、六个常见 Yosys 路径、Program Files/用户 Programs/D 盘顶层相关目录名、现有默认 Ubuntu PATH，以及 Docker 本地镜像清单。未找到名称表明为综合用途的本地镜像；没有进入无关应用镜像搜索，不断言其中完全没有 EDA 文件。没有全盘搜索、商业许可测试或学校服务器访问，不断言整机/远端一定未安装。Docker 可用性检查到引擎 API 响应为止。

## 3. 赛题材料与依赖缺口

已读 `docs/REQUIREMENTS.md`、`docs/PROJECT_STATUS.md`、`docs/SUBMISSION_CHECKLIST.md`，并核对根目录两份交接材料中的相关段落。本轮重新渲染核对赛题 PDF 的印刷 3、4、8、10、11、12 页；下列正式计量边界以赛题原文为准，交接自述不算工程已到位。

原始 PDF 共 13 个物理页，印刷页为 2～14，缺印刷第 1 页；SHA-256：`354977bf737a6c21b1267fd96853ff6bdcb5c7fa82c240f8ff190845f980d719`。本轮只核对本地赛题，不声称已验证最新公告或补充说明。

| 依赖 | 已有 | 缺失（BLOCKED） | 待老师/组委会确认 |
|---|---|---|---|
| 指定 E203 平台 | 已知须使用指定 E203、总线/外设、512 KB 共享 SRAM、分层装载；接入为 System Bus 或 NICE | `soc/` 无工程；`external/e203` 不存在，未设置替代目录；SDK/工具链、加载仿真环境、内存图未交 | 发布包/版本或 commit、获取授权、官方修改边界；不能用任意开源 E203 替代 |
| 标准单元库 / Liberty | 已知须按指定库映射 | `external/techlib` 不存在；无可用 `.lib/.db`、时序/功耗/面积库和单位依据 | 工艺节点、库名称/版本、PVT、电压/温度、支持格式与综合工具；本轮均不猜测 |
| SRAM 宏 | 已知内部可组合 16×128、16×1024、16×4096 单/双端口宏 | `external/sram` 不存在；缺模块名、端口定义、行为仿真模型、综合 blackbox/wrapper、Liberty/时序模型、官方宏面积、动静态功耗模型 | 宏具体型号、读延迟、读写冲突/掩码/使能行为、角点/单位、功耗查表/替代估算办法；三块 16×1024 只是老师要求转述，待两份 txt 原文核实 |
| 150 MHz / SDC | 正式统一频率与综合目标 150 MHz，周期 `1000/150 ns ≈ 6.666667 ns` | 没有正式顶层、时钟/复位端口或有效 SDC；本轮不制作猜测的 SDC | 主/生成时钟、低速域、uncertainty/transition、I/O delay、输出负载、复位处理、例外及依据、互连估计；有效完整约束不能隐藏违例 |
| 面积统计 | 已知新增加速器+接口+内部 SRAM ≤2.25 mm²；复用 E203、512 KB 共享 SRAM、固定总线/外设不计预算但单列 | 无映射网表、层次归属清单或官方宏面积，无法计数 | wrapper/新增桥接/缓冲等边界及报告模板；标准单元与 SRAM 单位换算和去重方式 |
| 功耗估计 | 同计时窗口 SAIF/VCD；相同库/角点/负载/时钟/互连条件；覆盖 E203+加速器+互连+SRAM 动静态功耗，模拟与片外不计 | 无真实任务/驱动/活动、功耗库、宏功耗和映射覆盖证据；不能把未标注逻辑或 SRAM 算零 | 活动层级/覆盖检查规则、RTL/门级活动与毛刺口径、未覆盖部分处理、宏功耗方法、统一条件和报告格式 |

团队还须交付冻结 RTL、唯一顶层、有序文件清单及宏实例清单；这些是队友后续输入，本轮不等待、不代写。老师《硬件设计定义.txt》《硬件设计实现.txt》原文未随附，FP32、阵列和缓存要求不擅自升级为本轮冻结配置。

功耗活动窗口应与性能一致：任务开始前清空数据/参数缓存，从输入和参数开始装载，到全部结果写回结束，包括装载、总线等待和 E203 调度；任务间平台复位不计。正式抽取的 12 个任务覆盖 12 层，12 次分别满足数值门槛。同一方案的吞吐、功耗和面积须来自同一冻结配置，不拼接不同配置的最优数字。

## 4. 最小实验与可执行流程

`synthesis/smoke/smoke.v` 是 8 位无符号加法后写入 9 位寄存器的小例子，含同步复位、使能及保持。不属于正式加速器、SoC 或数值模型，不规定队友接口。

真实执行：

```powershell
python synthesis/flow.py probe --context outside-sandbox-final
python synthesis/flow.py run --label smoke-baseline
python synthesis/verify.py
python synthesis/flow.py compare synthesis/runs/20261016_234129_generic_5ec2762c/report.json synthesis/runs/20261016_234423_generic_1f576711/report.json
```

- 最终 `run` 返回 2；记录在 `synthesis/runs/20261016_234423_generic_1f576711/`。实际尝试 `yosys -V` 失败，综合状态 BLOCKED，网表和通用资源 NOT_RUN。**未运行 synth，未生成 netlist.v 或 stat.json。** 初次尝试 `20261016_234129_generic_5ec2762c` 也保留；其旧状态标记为 NOT_RUN，后续版更明确标为 BLOCKED，不回写旧证据。
- `verify.py` 返回 0，7 项检查通过，证据 `synthesis/validation.json`：真实 Icarus 编译和运行均 0，输出 `STAGE3A_SMOKE_SIM_OK`；覆盖复位、255+255 的进位、使能保持、普通加法与复位优先。其余检查验证缺工具报告/空 PPA、Git 与源码哈希、SDC 元数据、非法顶层拒绝、非零退出/超时、两报告比较。负例输出与仿真均不是 PPA 实测。
- 成功综合、网表核验与资源解析分支因缺 Yosys 为 NOT_RUN；没有用模拟工具输出或伪造网表替代。尚未做综合前后等价检查。
- 当前可以执行环境复查、RTL 小例子仿真、缺依赖/失败记录和报告比较；安装/配置获准的综合工具后，才可执行 `read_verilog → hierarchy → synth → check → stat → write_verilog` 通用练习。未来成功输出只表示通用逻辑结果，不能认定官方面积或 150 MHz 达标。

## 5. 自动化框架和新增文件

采用 Python 3.11 标准库；无第三方依赖、CI 服务、数据库或许可证配置。

| 新增文件 | 用途 |
|---|---|
| `synthesis/flow.py` | `probe` 环境实测、`run` 通用 Yosys 入口、`compare` 并列报告 |
| `synthesis/smoke/smoke.v`、`files.f` | 独立小例子和有序文件清单 |
| `synthesis/verify.py`、`validation.json` | 可复跑的框架/仿真验证及最终真实证据 |
| `synthesis/README.md` | 命令、输入协议、输出字段和限制 |
| `synthesis/runs/20261016_234108_environment_7a9e37f3/{report.json,commands.log}` | 沙箱调查 |
| `synthesis/runs/20261016_234210_environment_9ab34613/{report.json,commands.log}` | 沙箱外中间复核 |
| `synthesis/runs/20261016_234304_environment_2c069586/{report.json,commands.log}` | 最终环境调查 |
| `synthesis/runs/20261016_234129_generic_5ec2762c/{report.json,commands.log}` | 首次通用综合阻塞记录 |
| `synthesis/runs/20261016_234423_generic_1f576711/{report.json,commands.log}` | 最终通用综合阻塞记录 |
| `reports/STAGE3A_SYNTHESIS_PREP.md` | 本报告及老师资料清单 |

PDF 渲染图和早期验证草稿在被忽略的 `tmp/` 中，仅供本地核对，不交付为设计证据。

每次 run 独立目录记录：Git commit/分支/dirty、执行脚本哈希、源文件及清单哈希、工具实际版本探测、约束文件 SHA-256 版本、实际 argv/cwd/开始结束时间/退出码/日志、综合和网表状态。面积 mm²、时序裕量 ns、功耗 mW、关键路径均预留 `status/value/reason/evidence`，当前全部 BLOCKED/null，不以 0 代替未知。

后续接收 `--top`、`--files` 和 `--label baseline/innovation`；清单按行列路径，相对清单目录解析并保持顺序。当前只支持直接源文件，不支持宏定义、include 搜索目录或完整商业 SystemVerilog 前端；取得工程后再按实际依赖扩展。`--sdc` 只留哈希，明确 `applied=false`，缺约束版本为 null/NOT_RUN；没有正式工艺映射、STA 或功耗后端。

比较器可以展示两版提交、综合状态、通用逻辑数量和 PPA 状态；本轮只比较同一小例子的两次阻塞记录，没有创新实验和收益结论。正式比较须人工审查工具、库、PVT、约束、活动与统计口径的可比性。

## 6. 向老师或组委会索取的简洁清单

### A. 缺少即不能开展对应正式综合/PPA 的关键材料

1. 指定 E203 平台工程完整发布包、版本/commit、总线/外设/内存图、SDK/编译链、参数加载仿真环境及使用权限。
2. 指定/认可的综合、时序和功耗工具及版本；学校服务器入口或合法许可证使用安排。无需向团队传送许可证密钥。
3. 指定标准单元库：Liberty/所需工具格式、时序/面积/功耗信息、库版本、单位、PVT/电压/温度和授权获取方式。请明确工艺节点，不由团队猜测。
4. 指定 SRAM 宏完整套件：模块和端口/功能仿真模型、综合黑盒与 wrapper 用法、时序/功耗模型、官方面积表、宏版本/PVT/单位；确认无功耗模型时认可的建模方法。
5. 150 MHz 参考 SDC 或正式约束规则：时钟/复位/I/O/负载/不确定度/例外依据、低速与生成时钟、互连估计；面积层次计入/排除边界和功耗统一条件。
6. 完整最新版赛题/补充公告（含缺失第 1 页）、老师两份硬件 txt 原文，以及库/平台/网表/活动文件的允许共享与正式交付方式。

正式综合网表依赖平台、RTL、工具、库/宏和有效约束；正式功耗还依赖实际活动及模型。上述清单不意味着要等功耗波形生成后才可开始合法的基础映射。

### B. 可暂时用通用工具练习的内容

1. 请确认可否安装来自 YosysHQ 官方发布渠道的通用 Yosys，或直接提供已有可信可执行路径；用于小例子和流程练习。
2. 没有指定 Liberty/SRAM 时，可以先用本轮小例子验证语法、层次、通用综合、网表导出和逻辑计数。通用库/行为 RAM 不能替代正式库/宏，计数不能换算比赛面积。
3. 没有正式 SDC 时只做无时序结论的练习；仅有 150 MHz 数字不足以构造有效约束。不用假负载或随意 false path 生成达标报告。

### C. 可在后续开发阶段提供或按老师规则由团队生成

1. 正式评测/任务窗口、活动标注及覆盖核验的细化模板；随后由团队生成真实驱动/向量、SAIF/VCD、层级映射与起止事件。组委会抽取的正式任务按赛题时点获取，本轮不索要尚未发布的样本答案。
2. 综合前后功能一致性验证流程、最终报告与提交目录模板，以及基线/创新版本比较的统一条件。
3. 最终冻结阶段所需的工程、数值配置、镜像、库/宏、网表和脚本版本清单与受限大文件传递渠道。

## 7. 可选安装路径（仅方案，未执行）

| 方案 | 预计依赖和影响 | 使用边界 |
|---|---|---|
| YosysHQ OSS CAD Suite Windows x64 发布包 | Windows 10/11 x64、下载/解压空间及包内运行库；优先选无空格本地目录，按官方环境脚本仅作用于当前 shell；不需自行构建编译器，包包含多种工具，体积以选定发布资产为准 | 来源为 YosysHQ 官方发布；先由用户确认版本/位置/范围，再安装。可用本脚本 `--tool` 指定路径 |
| 已有 WSL Ubuntu 内的发行版 Yosys 包 | 现有 Ubuntu、可信发行版软件源、包管理权限及运行库/ABC 等随包依赖；具体包版本/空间需安装前查看包管理器计划；无需再装 WSL/Docker | 更轻的 Linux 练习选择；执行本脚本须另核对 Ubuntu Python ≥3.11 和路径；本轮未 apt update/install 或改软件源 |
| 学校已授权 EDA 服务器 | 老师提供账号入口、许可、工具版本、指定库/宏及数据传递规则；无需本机安装大型商业 EDA | 正式流程优先取得老师认可环境；不假定 DC 或 Genus 就是官方指定工具 |

安装渠道与依赖说明核对自 [Yosys 官方安装文档](https://yosyshq.readthedocs.io/projects/yosys/en/stable/getting_started/installation.html)、[Yosys 官方下载说明](https://yosyshq.net/yosys/download.html)、[YosysHQ OSS CAD Suite 安装说明](https://github.com/YosysHQ/oss-cad-suite-build#installation)。没有执行网页中的安装命令、下载包或脚本；不选陌生镜像/网盘分发。不自行安装 Design Compiler/Genus、配置许可或系统 PATH。

## 8. 下一步与验收边界

建议总控先验收本报告、运行证据及输入/报告接口，再由用户确认通用综合工具的可信来源和安装方案；取得后仅补跑本轮 smoke，检查真实网表和通用统计。并行向老师索取 A 类材料，明天接收硬件组的顶层/清单/宏/时钟复位说明。材料和功能条件齐全后另立正式综合阶段，先审查有效约束和统计范围，再做正式映射、时序/功耗及综合前后验证。

本阶段没有安装、修改系统配置、修复队友源码、开展正式加速器综合、生成虚构 PPA、推送或合并。独立本地分支保存本轮新增文件；等待总控 AI 验收，不自动进入下一阶段或安装工具。
