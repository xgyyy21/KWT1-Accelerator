# 阶段 3A：综合练习与报告入口

Python 3.11 标准库，无 Python 第三方依赖。当前没有可用综合工具；`run` 会留下 BLOCKED 报告并返回 2。Icarus 只用于仿真，不替代综合。正式工艺映射、STA 和功耗后端尚未实现。

## 命令

从仓库根目录的 PowerShell 执行：

```powershell
python synthesis/flow.py probe --context ordinary-powershell
python synthesis/flow.py run --label smoke-baseline
python synthesis/verify.py
```

`probe` 实际执行工具版本、Git/Python 功能、Icarus 编译/运行、WSL 状态及已有默认发行版 shell、Docker 引擎查询；不会安装、启动 Docker Desktop、拉镜像或改系统配置。仅检查 PATH、列出的六个常见 Yosys 路径和本地资产目录，不能据此断言整机或学校服务器没有工具。总状态表示本框架 Yosys 通用练习是否可用，各工具状态须分别读。

本机 Codex 沙箱会限制 Icarus、WSL 和 Docker；本轮普通权限环境实测可用，证据见阶段报告。在 Codex 中由工具权限机制处理沙箱外运行；脚本不自动提权。

`verify.py` 使用临时文件验证缺工具、无效顶层、非零退出、超时、SDC 元数据、比较表和实际 Icarus 仿真，保存 `validation.json`。缺少 Icarus 或执行受限时断言失败，不能称验证通过。验证不需要 Yosys；成功综合分支仍待装好工具后实测。

以后经批准配置现有 Yosys，可指定完整路径：

```powershell
python synthesis/flow.py run --tool 'C:/approved-tools/oss-cad-suite/bin/yosys.exe' --label smoke-baseline
```

该路径仅为用法示例，目前不存在。安装必须另外获得用户确认。

## 接收硬件组输入

给出唯一顶层和有序文件清单，用 `--top TOP --files FILELIST --label baseline` 接收；创新版本另用 `--label innovation`。本轮仅运行小例子，不读取正式加速器 RTL。

清单为 UTF-8，每行一个源文件，路径相对清单自身；允许空行和以 `#` 开头的注释。路径无需引号，带空格路径保留原样。当前不支持嵌套 `-f`、`+incdir`、宏定义和参数覆盖；`include` 及完整 SystemVerilog 支持需取得真实工程后扩展并验证。文件顺序、顶层、宏 wrapper 和黑盒必须由硬件组明确交付，不能通过自动扫描源码猜测。

`--sdc FILE` 只记录 SHA-256 作为约束版本，`applied=false`。没有 SDC 时版本为 null、状态 NOT_RUN。150 MHz / `1000/150 ns` 仅是目标元数据；脚本不读取 SDC、不进行时序分析。不得将此入口用于正式达标结论。

工具可用时，`run` 生成并执行 `run.ys`：`read_verilog -sv` → `hierarchy -check` → `synth` → `check -assert` → `stat -json` → `write_verilog`。成功必须同时满足进程返回 0、非空网表含指定顶层以及统计 JSON 可读。未做综合前后等价验证。只有实际成功时才保存通用逻辑单元统计；无 Liberty 映射，不换算 mm²。

## 每次运行的证据

`runs/<北京时间>_<类型>_<随机标识>/` 保存 `report.json` 和 `commands.log`，已有运行不覆盖。若实际完成综合，再增加 `run.ys`、`stat.json`、`netlist.v`。缺工具时不会生成占位网表。

记录 Git commit/分支/脏工作区、脚本与源文件/清单 SHA-256、工具版本探测、约束文件哈希、完整 argv/cwd、时间、返回码、stdout/stderr、综合状态和网表核验。Git 脏快照表示代码尚未提交；以文件哈希补充追溯，不能声称提交号已包含全部输入。

`ppa.area_mm2`、`timing_slack_ns`、`power_mw`、`critical_path` 各有 status/value/reason/evidence。本入口没有真实后端，固定为 BLOCKED/null；未执行的网表、资源统计等为 NOT_RUN。0 表示当前操作通过，1 表示失败，2 表示缺依赖。综合报告 PASS 也仅表示通用练习通过。

比较两份真实运行报告：

```powershell
python synthesis/flow.py compare synthesis/runs/20261016_234129_generic_5ec2762c/report.json synthesis/runs/20261016_234423_generic_1f576711/report.json
```

本例是同一 smoke 两次阻塞记录，不能作为基线/创新实验。以后替换为两版实际报告；比较器并列显示标签、提交、状态、通用单元及 PPA 字段，不自动认证可比性或计算收益。正式比较前人工核对同一工具/库/PVT/约束/任务窗口/统计范围；每个方案的网表、活动、吞吐和 PPA 均须来自自身同一冻结配置。

后续正式后端应在老师确认库、宏、SDC、工具及计量条件之后单独接入。受限库、许可和大型活动文件继续放在 Git 外；没有对现有忽略规则作修改。
