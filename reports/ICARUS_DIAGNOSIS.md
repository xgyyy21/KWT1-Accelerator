# 阶段 1 补充：Icarus 诊断与运行边界

日期：2026-10-16（Asia/Shanghai）。仅临时最小模块，不是项目 RTL/SoC 验证。未下载、安装、修复安装文件、修改系统 PATH 或其他全局环境。底层异常未做调试器定位。

## 路径、安装和完整性清点

WindowsApps 中两份 CMD 内容均为 `@echo off` 后直接调用真实 exe 并转发 `%*`：

```text
C:\Users\pc\AppData\Local\Programs\iverilog\app\bin\iverilog.exe
C:\Users\pc\AppData\Local\Programs\iverilog\app\bin\vvp.exe
```

包装没有指向另一版本。PATH/Get-Command、当前用户 Programs、Program Files（可读部分）、常见 tools/msys/scoop/chocolatey/WinGet 安装位置中，仅发现这一套 Icarus；Program Files/WindowsApps 子目录扫描拒绝访问，未声称穷尽整机。没有可比较的第二安装。

| 文件 | 字节 | SHA-256 |
|---|---:|---|
| iverilog.exe | 88064 | 803b8844af2cc8ed70b5f08b07ffa749901280e81339617ca3e72cbbb852bd2b |
| vvp.exe | 945664 | e2f442f4d5aa76e55c85c3ff77e4446fbfdb9946b7cfe8a2dff87f275da17b62 |

两文件具有有效 PE 头；版本为 12.0 devel（s20150603-1539-g2693dd32b）。安装内 bin、lib/ivl、ivlpp、ivl、vvp.tgt、配置及相关 DLL 存在，文件清单/哈希见同名 JSON。没有发行方校验值，不能据本地哈希宣称分发包完整性或来源真实性已认证；但同一安装成功完成了编译与运行，没有证据要求重装或补 DLL。

## 差异对照

| 环境/动作 | 实际结果 |
|---|---|
| 受限沙箱：真实 exe 版本命令 | 0 |
| 受限沙箱：真实 exe 普通编译 | 3221225477 / 0xC0000005；无标准输出/错误 |
| 受限沙箱：CMD 普通编译 | 同上，排除仅为包装路径错误 |
| 受限沙箱：详细编译模式 | 直接调用有一次返回 0；CMD 调用仍异常，不能把 `-v` 当稳定修复 |
| 受限沙箱：缩短进程 TEMP/TMP；隔离进程 PATH | 编译仍异常；没有更改系统环境 |
| 受限沙箱：仅预处理 `-E` | 0 |
| 受限沙箱：对已生成 vvp 文件直接运行 | 0，输出 KWT_TOOL_SMOKE_OK；编译器非零退出仍判 FAIL，产物不能代替编译成功 |
| 获准沙箱外：同一真实 exe、同一临时源文件编译 | 0 |
| 获准沙箱外：真实 vvp 运行 | 0，输出 KWT_TOOL_SMOKE_OK |
| 获准沙箱外：完整原版 `integration/check.py`（经 PATH CMD） | stage1 PASS；24 PASS / 0 FAIL / 19 BLOCKED / 2 NOT_RUN（首提交前） |

这组结果把故障范围缩到受限沙箱与该安装的运行交互；不支持“CMD 路径错误”“仅 PATH 冲突”“必须重新安装”等结论。尚不能指出原生程序中的准确崩溃指令或沙箱内部原因。Windows 应用事件日志在沙箱内拒绝访问，获准沙箱外查询未得到匹配崩溃事件。

## 最小源文件与命令

源文件在工作区 `tmp/icarus_probe/tool_smoke.sv` 临时创建，未放入 rtl/ 或 tb/：

```systemverilog
module tool_smoke;
  initial begin
    if ((7 + 5) != 12) $fatal(1, "arithmetic failed");
    $display("KWT_TOOL_SMOKE_OK");
    $finish;
  end
endmodule
```

在该临时目录、获准沙箱外执行：

```powershell
& 'C:\Users\pc\AppData\Local\Programs\iverilog\app\bin\iverilog.exe' -g2012 -s tool_smoke -o outside_sandbox.vvp tool_smoke.sv
& 'C:\Users\pc\AppData\Local\Programs\iverilog\app\bin\vvp.exe' outside_sandbox.vvp
```

真实日志：

```text
COMPILE_EXIT=0
KWT_TOOL_SMOKE_OK
tool_smoke.sv:3: $finish called at 0 (1s)
RUN_EXIT=0
```

因此无需修改 `integration/check.py`：原来的 PATH/CMD 调用路径是有效的。普通 Windows PowerShell 使用 `python integration/check.py`；Codex 中需要获准的沙箱外执行。不要在脚本中自动提权、忽略 0xC0000005 或仅检查 vvp 文件存在。

## 版本管理边界

三份原始赛题/交接材料建议等待权限和团队版本策略确认，当前不提交；精确 `.gitignore` 规则仅防误加，原文件仍留本地。Git 作者按用户本轮选择：`Codex <codex@local.invalid>`，只在提交命令设置，不修改全局配置。首提交候选清单和审查见 `reports/GIT_FIRST_COMMIT_REVIEW.md`。首提交后再运行检查，版本以该报告及 `git log` 为准。
