# Checkpoint 逐 PE 结果

这是 `fp32_array_checkpoint_tb.sv` 在实际 RTL 上产生的结果，不是软件模型生成的期望文件。

复现命令（工作目录为仓库根目录）：

```powershell
& 'D:\competition\.tools\iverilog\bin\iverilog.exe' -g2012 -s fp32_array_checkpoint_tb -o build\checkpoint_per_pe.vvp -f rtl\files.f tb\fp32_array_checkpoint_tb.sv
& 'D:\competition\.tools\iverilog\bin\vvp.exe' build\checkpoint_per_pe.vvp
```

工具版本：Icarus Verilog 14.0 (devel)。

实际结果：512 次保存写入、512 次读请求、512 次读响应；复位后恢复 128 个 PE；`checkpoint_result_per_pe.csv` 含 128 个唯一 `(row,column)`，每行记录 `cycle,row,column,result_bits`。本次复跑日志见 `compile.log` 和 `run.log`。

