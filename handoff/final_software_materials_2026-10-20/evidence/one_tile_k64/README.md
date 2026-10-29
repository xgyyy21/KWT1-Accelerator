# 单 tile K=64 真实 RTL 路径

该证据覆盖一个 8×16 输出 tile 的完整顶层路径，输入为 testbench 内固定的全 1 数据和 bias，目标是先确认阵列调度、FP32 计算和写回链路，而不是替代 99×64×256 整层验收。

复现命令：

```powershell
& 'D:\competition\.tools\iverilog\bin\iverilog.exe' -g2012 -s fp32_one_tile_k64_tb -o build\one_tile_k64.vvp -f rtl\files.f tb\fp32_one_tile_k64_tb.sv
& 'D:\competition\.tools\iverilog\bin\vvp.exe' build\one_tile_k64.vvp
```

工具版本：Icarus Verilog 14.0 (devel)。

实际结果：`PASS: one 8x16 tile K=64 outputs=128 writes=256 cycles=12634`。这不是完整 FFN1 通过；完整 FFN1 仍受 Icarus 仿真性能限制。

