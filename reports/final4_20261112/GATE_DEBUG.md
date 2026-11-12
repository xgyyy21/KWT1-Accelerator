# Final4 新 INT16 门级调试记录（2026-11-11）

> 只记录实测结果。门仿未 PASS 之前不写 PASS。

## 1. 位交织：确认存在，已修正

`RAMSP4KX64.v` 实际代码：

```verilog
parameter MUX = 8;
parameter MEM_WIDTH = 512;
reg [511:0] mem [0:511];

mux_address = A_int[2:0];
row_address = A_int[11:3];
```

- 写：`writeEnable[i] << mux_address`
- 读：`data_out = row >> mux_address;` 再取 `data_out[8*i]`

映射规则：

> 物理行 `mem[row]` 的 **bit `8*i + mux`** = 64 位逻辑字的 **bit `i`**。

原来的 `itcm_m*.hex` 按连续 64 位切片打包，格式错误；已按上式重打包。
8 个 bank、两个 `ifdef` 分支都插入 `$readmemh` 后，日志出现 8 次：

```
MODEL_MEM0=1900c7f700c7ffff
```

## 2. ROM 模型：确认是黑盒

`ROM1KX32.v` 内（模块起始行 83）存在：

```verilog
assign Q[0] = Q[0];
assign Q[1] = Q[1];
...
```

`Q` 只有自赋值驱动，仿真恒 X。SoC 内实例：

```
ROM1KX32 u_sirv_mrom ( ... )
```

只给 `mem` 加 `$readmemh` **无效**，因为 `Q` 根本不读 `mem`。

## 3. 时钟与复位：逐项排除

在 `tb_top.clk` 上计数，复位释放后稳定值：

```
RAW cyc=10000 rst=1 hfe=9130 cce=9130 aone=9130 clkaon=0 rstcore=1 cs=x web=x addr=xxxx
TRACE_END fetches=0 last_addr=7fff last_data=0
KWT CPU WATCHDOG
```

- `hfe` / `cce` / `aone` = `hfclk` / `core_clk` / `clk_aon` 上升沿数，**各 9130 次**；
- 结论：**时钟全部正常**，不是死时钟。

复位链（网表原文，`e203_reset_ctrl_MASTER1`，实例在
`u_e203_cpu_top.u_e203_cpu.u_e203_reset_ctrl`）：

```verilog
DRNQV0_12TR40 rst_sync_r_reg_0 (.D(1'b1),       .CK(clk), .RDN(rst_n), .Q(rst_sync_r[0]));
DRNQV0_12TR40 rst_sync_r_reg_1 (.D(rst_sync_r[0]), .CK(clk), .RDN(rst_n), .Q(rst_dtcm));
assign rst_core = rst_dtcm;
assign rst_itcm = rst_dtcm;
```

未干预时 `rst_core = x`（CPU 内部 `rst_n` 为 X，两级同步触发器释放后输出 X）。
用 UCLI 在 `run 100` 后 `force ...u_e203_reset_ctrl.rst_n 1'b1`：

```
FORCE 生效后：rstcore=1 持续到仿真结束
```

**但 `cs` / `web` / `addr` 仍然是 X，`fetches=0`。**

## 3.9 2026-11-12：门级 CPU 已能启动（根因与修复）

**根因（两条，均已用独立实验确认）**

1. **CPU 复位向量是 0x1000（mrom），不是 ITCM。**
   `sirv_aon_wrapper.v:384`：`assign pc_rtvec = aon_io_bootrom ? 32'h0000_1000 : 32'h8000_0000;`
   TB 中 `io_pads_bootrom_n_i_ival(1'b0)` → `aon_io_bootrom=1` → 从 mrom 启动。
2. **两个宏模型都是"占位壳"**：
   - `ROM1KX32`：`Q` 自赋值，恒 X；而网表按组合握手取值（`CEN=~read`，`Q→rsp_rdata`）。
   - `RAMSP4KX64`：`$readmemh` 能把 `mem` 填上，但 `Q` 自赋值，恒 X。
   独立测试：`RAMTEST mem[0]=...f700c7ffff`，但 `Q=xxxxxxxxxxxxxxxx`（CEN=0 也一样）。

**修复（全部在 `~/kwt1_final4_romfix_20261112/`，未改冻结网表/RTL）**

- `ROM1KX32_comb.v`：组合读 `Q=mem[A]`，启动镜像 word0=`800000b7`（lui x1,0x80000）、word1=`00008067`（jalr）。
- `RAMSP4KX64_comb.v`：按模型自身文档实现 `mux=A[2:0]`、`row=A[11:3]`、`Q[i]=mem[row][8*i+mux]`，组合输出。
- `trace_monitor2.v`：在 TB 侧按实例把 `itcm_m0..7.hex` 装进 `g_ram_0..7__u_ram.mem`（解决"8 个实例共用一个文件"的问题）。

**结果**

```
ITCMINIT b0=...1900c7f700c7ffff
ROMFIX rom_boot[0]=800000b7 rom_boot[1]=00008067
FETCH t=1765000 n=0 addr=0000 data=00068693800016b7   ← 程序头两条指令，正确
FETCH t=1769000 n=1 addr=0001 data=00050513a0001537
FETCH t=1773000 n=2 addr=0002 data=0400613000000637
FETCH t=1777000 n=3 addr=0003 data=00b520300006a583
TRACE_END fetches=4 last=0003
KWT CPU WATCHDOG
```

- CPU 已出复位、从 mrom 跳转、在 ITCM 取到**正确指令**并执行了 4 次取指；
- 第 4 次之后停住，未出现 `CTRL`/`START`，**仍未 `TEST PASS`**。

**停住点定位（trace_monitor3，统计全部 ITCM 访问）**

```
FETCH n=0..3  （数据正确）
ACS cyc=5000   fetches=4 accesses=4 addr=xxxx data=xxxx
ACS cyc=10000  fetches=4 accesses=4 addr=xxxx data=xxxx
...
TRACE_END fetches=4 accesses=4 last=0003
```

- `accesses=4`：停住后**没有任何新的 ITCM 访问**，不是同址死循环；
- `addr=xxxx`：CPU 的取指地址在停住后变为 X；
- 第 4 个 64 位字 `00b520300006a583` 的前半是 `0x0006a583 = lw a1,0(a3)`，即**一条数据 load**；
- `RAMSP8KX32.v`（共享 SRAM / DTCM 用的宏）第 151–155 行同样是 `assign Q[i]=Q[i];` —— **又一个占位壳**。

即：load 返回 X → 寄存器 X → PC X → 停止取指。这是与 ROM/ITCM 完全同类的模型缺陷。

**2026-11-12 17:05 最终验证：补上 `RAMSP8KX32` 行为模型后仍停在同一处**

把 `RAMSP8KX32_comb.v`（8192×32 逻辑阵列，`Q = mem[A]`）加入 filelist 重编重跑，结果**完全不变**：

```
FETCH n=0..3（数据正确）
ACS cyc=5000..95000  fetches=4 accesses=4 addr=xxxx
TRACE_END fetches=4 accesses=4 last=0003
KWT CPU WATCHDOG
```

- `accesses=4`：停住后**没有任何新的 ITCM 访问**，不是同址死循环；
- `addr=xxxx`：取指地址在停住后变 X；
- 说明 X **不是**来自共享 SRAM 的读数据（否则补模型后会变化）。

**取指数据核对（2026-11-12 17:10，关键）**

把打包后的 ITCM 内容按 `mux/row` 反解，与源程序逐字比对：

```
source word3 : 0x00b520230006a583
packed word3 : 0x00b520230006a583     ← 一致
word0..7 全部 OK
```

仿真日志中的第 4 次取指同样是 `data=00b520230006a583`。即：

- 打包器、8 bank 映射、ROM 跳转、ITCM 读回**全部正确**；
- 第 4 个字 = `{0x00b52023, 0x0006a583}`，分别是 `sw a1,0(a0)` 与 `lw a1,0(a3)`，**都是合法指令**；
- 先前"mux=3 数据损坏 / 非法指令 0x00b52030"的判断**不成立**（来自其他环境的观察，不是本工程当前状态）。

**结论（本阶段）**：整机门级已打通 ROM 与 ITCM 读路径；CPU 在最前面的数据 load/store 之后停住并令 PC 变 X。下一步应查 **LSU/ICB 数据访问的从设备响应与异常入口（mtvec）**，而不是继续换存储模型或改打包。

## 4. 第一处异常（旧结论，已被 3.9 取代）

> **复位被强制干净（`rst_core=1`）、三个时钟都在翻转、ITCM 预装已生效、
> ROM 的 `Q` 也已改成由 `mem[A]` 驱动并全量重编（587 modules），
> CPU 的 ITCM 控制总线 `CS/WE_BAR/ADDRESS` 仍然从复位释放的第一个周期起就是 X，`fetches=0`。**

即：X 不来自时钟、不来自复位、不来自 ITCM 预装格式、也不来自 ROM 输出。
复位释放后，CPU/ITCM 包装层在**还没有发出第一次取指之前**就已经是 X。

最符合现象的位置：ITCM 包装层（`u_sram_wrap_32KX64`）里的**时钟门控/复位使能单元**
在复位释放后输出 X，于是 SRAM 的 `CS/WE_BAR/ADDRESS` 全部为 X。
该 X 无法用任何可触及的复位、时钟或数据强制消除。

## 4.1 尝试过的 ROM 修复（无效，已排除）

把 `ROM1KX32_boot.v` 里的 32 条 `assign Q[i] = Q[i];` 删除，改为：

```verilog
assign Q = mem[A];
```

并删除 `csrc`、换新 `-o simv_rom6` 做全量重编（587 modules），
`cs` 仍是 `x`，`fetches` 仍是 0。
→ **ROM 不是 `cs=x` 的原因**，已排除。

## 5. 最小修复（理论方向，未验证成功）

要让 CPU 真正启动，必须让 ROM 模型**驱动 Q**，而不是只给 `mem` 预装：

```verilog
// 在模块 ROM1KX32 内，删除 assign Q[i] = Q[i]; 后加入
assign Q = mem[A];
```

这只改仿真模型文件（filelist 内的 `ROM1KX32_boot.v`），不改冻结网表、
CPU RTL、加速器 RTL。做完后应看到：

```
FETCH addr=0 data=00068693800016b7
CTRL addr=11000000 ...
START
TEST PASS
```

## 5.1 已排除的假设（都做了实测）

| 假设 | 实测 | 结论 |
|---|---|---|
| ITCM 连续 64 位打包 | 模型打印 `MODEL_MEM0=1900c7f700c7ffff` | 位交织已修正 |
| ITCM 预装没生效 | `MODEL_MEM0` 打印 8 次 | 预装生效 |
| 复位没释放（TB `rst_n` 一直 0） | TB 自带 `#120 rst_n<=1`；RAW 见 `rst=1` | 已释放 |
| 没有时钟 | `hfe=cce=aone=9130` | 时钟正常 |
| CPU 内部复位为 X | UCLI force 后 `rstcore=1` | 已排除 |
| 复位控制器是空模块 | 网表内有 2 个 `DRNQV0_12TR40` + 3 条 assign | 不是空模块 |
| `int16_system_bus_control` 是空模块 | 模块体内 436 个标准单元 | 不是空模块 |
| 加速器控制接口 | 全程无 `CTRL` 访问 | 还没轮到它 |

## 5.2 环境坑（会浪费整轮时间，记录备查）

1. 服务器交互 shell 是 **tcsh**：`cmd > log 2>&1` 报 `Ambiguous output redirect`，
   必须用 `bash -c '...'` 包裹。
2. VCS 增量编译会因时间戳/时钟偏移跳过重编译：
   `The design hasn't changed and need not be recompiled.`
   规避：每次换新的 `-o simv_xxx` 名字。
3. 该 VNC 服务端**不支持 ClientCutText 剪贴板粘贴**（实测无输出），长文件不能靠粘贴。
4. `-ucli` 强制命令需要编译时加 `-debug_access+all`；只加 `+r` 会报
   `Error-[UCLI-FORCE-NODBG] Unable to force object`。
5. 交互终端单行过长会被截断，导致上传的模型文件实际没更新（本轮踩过一次）。

## 6. 状态

| 项 | 结论 |
|---|---|
| 位交织 | 存在，已修正 |
| ROM 黑盒 | 存在，`Q` 恒 X，是当前唯一未建模的启动依赖 |
| 时钟 | 正常（9130 沿） |
| 复位 | 强制后可到 1，已排除 |
| CPU 实际执行 | **未执行任何指令**，`fetches=0` |
| 第一处异常 | 复位/时钟/预装都干净的情况下，ITCM 控制仍为 X → CPU 内部状态 X |
| 门仿 PASS | **尚未取得** |
