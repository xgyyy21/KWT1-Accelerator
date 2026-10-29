# competition 本地 Verilator 环境

准备日期：2026-10-24。

## 安装位置与范围

- 工具链：`D:\competition\.tools\msys64`，使用 MSYS2 UCRT64。
- 启动脚本：`scripts/Run-Verilator.ps1` 和 `scripts/run-verilator.sh`。
- 安装脚本：`scripts/Setup-Verilator.ps1`。
- 下载/软件包配置：`scripts/verilator-pacman.conf`。
- 每次编译和运行的产物：`build/verilator/<testbench>_<时间戳>/`。
- 没有申请修改 Windows 系统 PATH，没有注册全局 Python；脚本仅临时设置并恢复进程的 MSYSTEM 和 CHERE_INVOKING。
- 保留已有 Icarus 环境，不修改项目 RTL，不自动提交或推送 Git。
- `.tools/`、`build/` 已在本地 `.gitignore` 中排除。

## 工具与下载验证

基础包为官方 `2026-09-27` 发布的 `msys2-base-x86_64-20260927.tar.xz`。

- 字节数：`42860696`。
- 官方发布 SHA-256：`ea2f31a0b6ade63914ce441ffb022f0f6aa96982bfefa2326460a26d5fb01322`。
- 通过北京外国语大学 MSYS2 镜像下载，安装前已与官方 GitHub 发布元数据中的哈希核对。
- 包管理器保留 `SigLevel = Required DatabaseOptional`，不关闭软件包签名验证。
- 工具版本：Verilator `5.050`、GCC `16.2.0`、GNU Make `4.4.1`；另安装 UCRT64 原生 Python，供 Verilator 构建脚本使用。不能仅使用 `/usr/bin/python3`，否则可能无法解释构建脚本中的 Windows 盘符路径。

安装脚本会更新本目录的 MSYS2 软件包；将来重新安装时版本可能变化，应保留当次 `tool_versions.txt` 和软件包版本清单，不能只依赖本文件描述复现。

## 使用方法

在 PowerShell 中进入 `D:\competition`，运行环境自检：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\Run-Verilator.ps1
```

这里的执行策略只作用于新建的 PowerShell 进程，不修改系统持久策略。

运行已固定的共享仓库中的缓存测试：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\Run-Verilator.ps1 -Top fp32_tile_cache_streamer_tb -SourceRoot D:\KWT1-Accelerator-shared
```

运行 8×16 阵列 K=64 测试：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\Run-Verilator.ps1 -Top fp32_pe_array_k64_tb -SourceRoot D:\KWT1-Accelerator-shared
```

项目测试必须显式传入 `-SourceRoot`。本机 `D:\competition\rtl` 与共享仓库的最新修复版并不完全相同，不能静默混用。

## 日志与边界

编译启用 `--binary --timing --assert`，不定义 `SYNTHESIS`，因此不会为了仿真关闭仿真专用检查。

本机 GCC 16.2.0 在 Verilator 默认的 C++ `-Os` 优化下遇到 `std::string` 移动构造函数链接失败。运行脚本通过 `-CFLAGS -O2` 为生成的 C++ 显式选择 `-O2`，不修改 RTL 或工具源码。对应上游问题：MSYS2/MINGW-packages 的 #30048、#31015；是否生效以本次实际编译结果为准。

每次生成独立目录，保留：

- `tool_versions.txt`：当次工具版本。
- `source_git.txt`：Git 工程的提交号与工作区状态（环境自检目录不是 Git 仓库时不生成）。
- `source_sha256.txt`：TB、filelist 及所列 RTL 的 SHA-256。
- `compile_command.txt`、`compile.log`、`compile_exit_code.txt`。
- 编译成功并实际运行时的 `simulate.log`、`simulate_exit_code.txt`。
- `obj_dir/`：生成的 C++、目标文件与仿真程序。

`-Wno-fatal` 使一般警告不会独自中止编译；所有警告仍记录在日志中，并不代表警告已修复。编译错误、RTL `$fatal` 和非零运行退出码仍按失败处理。

仿真工作目录是本次 `build` 子目录，避免 TB 将 CSV 写入源码目录。依赖相对路径输入或 plusargs 的测试，需要另行准备对应输入与调用参数；当前脚本不自动宣称支持完整层数据联调。

默认不生成 VCD/FST 波形，编译并行度默认为 2，可用 `-Jobs 1` 降低内存负担。

使用 `--output-groups 0` 禁止将很多生成的 C++ 文件合并为巨大的编译单元，以控制 8×16 阵列首次编译的内存和优化开销。首次默认分组编译尝试的日志保留，但被中止的尝试不计作测试通过。

环境自检只能证明工具链、延时和基本时序执行可用，不等于 PE、阵列、完整层、SoC、综合或 150 MHz 时序通过。测试 PASS 结论必须以当次日志与退出码为依据。

## 本次执行结果

工具链安装完成，支持不依赖系统 PATH 的本地启动。Python 实际使用 UCRT64 `3.14.9`。

使用最终脚本参数的本次测试：

| 测试 | 编译退出码 | 仿真退出码 | 结果 | 证据目录（位于 `build/verilator/`） |
| --- | --- | --- | --- | --- |
| 环境自检（时钟、非阻塞赋值、延时、计数检查） | 0 | 0 | PASS，counter=4 | `verilator_environment_smoke_tb_20261024_213806_704` |
| 缓存同步读与数据流 | 0 | 0 | PASS | `fp32_tile_cache_streamer_tb_20261024_213806_681` |
| 8×16 阵列、K=64 | 0 | 0 | PASS，128 个 PE 的结果均为 65.0 | `fp32_pe_array_k64_tb_20261024_213521_569` |

项目测试源码来自共享仓库提交 `0b04a55f8902f5969077fb376423b7c31853b9a3`，当次 `source_git.txt` 记录工作区为空。测试未定义 `SYNTHESIS`，不会跳过原有仿真检查。

阵列测试的首次完整编译耗时约 357 秒，其中构建约 348 秒；可执行程序的本次运行约 0.010 秒。这只是 K=64 阵列小测试的数据，不能据此预报完整 FFN1 的运行耗时。

源码仍有 `PINMISSING`、`TIMESCALEMOD`、位宽等警告，保存在 `compile.log`；本次不是无警告 lint 验收，也没有借环境安装修改这些 RTL。

准备期间的缺少 Python、Python 路径不兼容、默认 `-Os` 链接失败、PowerShell 日志类型问题和被中止的大分组编译尝试均已保留，不将失败或未运行目录解释为通过。最终判定只引用表中明确列出的实际运行目录。

本轮未开展完整 FFN1 数据对拍、E203/SoC 联调或综合时序验证，也不重写此前其他工具/版本的验收结论。
