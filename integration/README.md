# 本地统一检查与硬件模块回归

默认 `python integration/check.py` 保留基础清点/工具冒烟行为。可选参数把独立硬件快照纳入同一结果表，完整 FFN1、E203、精度和 PPA 验收仍单列为 BLOCKED。

阶段4B已验证：Icarus `14.0 (devel) s20260301-583-g5d7612759-dirty` 模块回归22/22；原12.0构建16/22。两者输入一致，SoC包装仅展开通过。报告发布副本和逐项比较见 [阶段4A](../reports/curated/STAGE4A_HARDWARE_INTEGRATION.md)、[阶段4B](../reports/curated/STAGE4B_ICARUS14_VALIDATION.md)、[精简验证证据](../reports/curated/verification_summary.json)。原始机器报告/完整日志保留本地，默认忽略；发布副本已移除用户目录路径，并明确标注本地证据链接。

已核验硬件提交为 `4448aee155f59dc895f83bec3968322160fd66a6`，tree为 `9c9d948a804dbb4e9da49147eea8f1e648d76562`。源码来自独立硬件仓库/快照，未合并进本分支。新机器可在独立新目录取得固定版本（需要该仓库访问权限；以下是复现说明，阶段4C未执行clone或checkout）：

```powershell
$hardwareSource = Join-Path (Get-Location) 'tmp/hardware-4448aee'
git clone --config core.autocrlf=false --no-checkout --single-branch --branch hardware https://github.com/xgyyy21/KWT1-Accelerator.git "$hardwareSource"
if ($LASTEXITCODE -ne 0) { throw '硬件仓库获取失败；不要在已有目录上强制操作' }
git -C "$hardwareSource" checkout --detach 4448aee155f59dc895f83bec3968322160fd66a6
if ($LASTEXITCODE -ne 0) { throw '固定提交不可用' }
if ((git -C "$hardwareSource" rev-parse HEAD) -ne '4448aee155f59dc895f83bec3968322160fd66a6') { throw '提交不匹配' }
```

必须保持源码字节与清单一致，避免自动CRLF转换；禁止为通过哈希检查而改清单。已有固定提交归档快照也可直接作为 `$hardwareSource`。阶段4A本机归档在 `tmp/stage4a_remote/snapshot/xgyyy21-KWT1-Accelerator-4448aee155f59dc895f83bec3968322160fd66a6/`，它未入库，干净clone不能假定该目录存在。

配置好经过核验的工具后，从仓库根目录PowerShell复跑（Python 3.11标准库）：

```powershell
$icarus14Root = 'D:/EDA-Tools/iverilog-14'  # 按实际独立配置位置填写
$previousProcessPath = $env:Path
try {
    $env:Path = "$icarus14Root/bin;$icarus14Root/lib;$previousProcessPath"
    python integration/check.py --hardware-source "$hardwareSource" --hardware-iverilog "$icarus14Root/bin/iverilog.exe" --hardware-vvp "$icarus14Root/bin/vvp.exe" --context ordinary-powershell
} finally {
    $env:Path = $previousProcessPath
}
```

只跑硬件部分可用 `python integration/hardware.py --source <硬件快照根目录> --iverilog <编译器路径> --vvp <运行器路径> --context ordinary-powershell`。工具路径必须对应同一安装；省略时只查询PATH，不安装工具。14.0发行来源/官方归档校验值/实际构建见阶段4B发布副本；不能把任意名为14.0的构建视为已验证。

`--hardware-manifest`（独立入口为 `--manifest`）默认使用 `reports/stage4a/hardware_manifest.json`，绑定本轮提交。以后换提交必须重新取得并审阅对应清单；哈希不匹配会 BLOCKED，不运行旧清单下的新源码。快照不需要切换当前分支，不会把快照复制进主工作区的 `rtl/`、`tb/`、`software/` 或 `soc/`。

适配层先核对源码 SHA-256，然后复制到唯一的 `tmp/stage4a_runs/<编号>/`，按交接先显式生成 `build/fp32_vectors.txt`，再运行原 `scripts/Run-Regression.ps1`，cwd 固定为该副本根目录。两个硬件脚本、RTL、TB 不作修改。薄命令代理只采集原生 argv/cwd/stdout/stderr/退出码，测试枚举、编译顺序、刺激、判定和 SoC 展开均由硬件原脚本完成。适配层另要求仿真退出 0 且出现对应 TB 的 PASS 标记；单项失败会传递到统一入口。

每次输出到 `reports/stage4a/runs/<编号>/`：`report.json`、`commands.log`、`native_commands.jsonl`、原始 `logs/*.compile.log`、`*.sim.log`、`soc_elaboration.log`、`summary.txt`。原始日志采用 Windows PowerShell 的 UTF-8 BOM。空编译日志表示工具无诊断，退出码见 JSONL；不是缺失日志。临时向量与仿真产物保留在报告指明的 scratch 路径，记录输入哈希、20,441 对数量、生成器和种子。运行目录不覆盖，脚本不联网、不切分支、不合并、不推送。

退出码：0=对应检查范围PASS，1=FAIL，2=BLOCKED。统一检查中其他依赖BLOCKED时，即使模块全通过也不能把完整工程标为PASS。沙箱会影响本机Icarus，普通权限结果与沙箱结果须分开阅读。FP32函数参考通过不代表完整FP32阵列、FFN1或E203集成通过。
