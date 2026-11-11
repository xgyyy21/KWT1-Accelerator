# Final4 加速器绑定顶层功能问题（交接给硬件同学）

日期：2026-11-11

## 一句话

Final4 综合实际使用的加速器顶层 `int16_accelerator_top_32_11000000_0`（`int16_accelerator_top_bound.sv`，带权重缓存）**跑不完一个作业**：在 `k=63` 进入 `S_RESULT` 后一直等不到 `pe_result_valid`，不写回、不报错，最终超时。

同一份测试平台跑 df45c9a 的通用顶层 `int16_accelerator_top` 是 **PASS**，所以问题在顶层状态机/权重缓存这条路径，不在 PE 数值逻辑。

## 复现结果（服务器 VCS）

通用顶层：

```
PASS int16_accelerator_top_tb K64_and_K256 PE=16 bus=32 continuous_jobs=2
```

Final4 绑定顶层（同一 TB，仅换 DUT，CTRL_BASE 覆盖为 0 以匹配 TB 的 MMIO 偏移）：

```
TIMEOUT state=8 row=0 col=0 k=63 bus_cmd=0/1 rsp=0/0 rsp_pending=0
        master_outstanding=0 rspbuf=0 counts=560/560 last=0000107c/ffff0003
Fatal: "repo_bound_tb.sv", 148: int16_accelerator_top_tb: at time 5000000000 ps
```

`state=8` 是 `S_RESULT`；`counts=560/560` 说明总线命令和响应都配平了；没有 `accel_error`，就是结果有效信号没来。

## 怀疑位置

`int16_accelerator_top_bound.sv`（349 行，SHA-256 `2a966e36…`）：

| 行 | 内容 |
|---:|---|
| 35 | enum 里有 `S_TILE_A_REQ`，但 case 内没有对应分支 |
| 149 | `S_A_REQ`：非权重缓存路径 |
| 215–225 | `S_A_REQ` 奇偶 k 的分支 |
| 254–264 | `S_TILE_B_WAIT`：权重 tile 装载与 `weight_cache_valid` |
| 282–286 | `S_MAC`：`current_k+1>=matrix_k → S_RESULT` |
| 287 | `S_RESULT: if(pe_result_valid)` |
| 326 | `default: state<=S_ERROR` |

现象指向：**最后一个 k（63，奇数）没有真正走完一次带 `mac_last=1` 的 `S_MAC`**；或者走了 `S_MAC` 但 PE 的 `pending_valid → biased_valid → result_valid` 没有被触发。PE 自己在通用顶层同 TB 下是正常的。

## 需要确认/修的点

1. 奇数 k（尤其 k=63）在权重缓存路径下是否一定进入 `S_MAC`，且 `mac_last` 为 1。
2. `S_TILE_A_REQ` 是否是未完成状态；如果不用，应从 enum/路径里去掉，避免进入后无处理。
3. `weight_cache_valid` 在 tile 装载完成后是否稳定为 1；不要在最后一个 k 前被误清。
4. 修完后请先跑仓库 TB（K64 + K256，两个连续作业），再跑整层 99×64×256。

## 不要动的东西

- 不要改冻结网表 `kwt1_soc_mapped.v`、DDC、SDC、工艺库。
- 修 RTL 请在新分支/新目录，修完重新综合，再做 RTL↔网表形式等价（Formality/LEC）作为回归。

## 附件

- `REPRO.md`：服务器命令与文件清单
- `evidence/key_logs.txt`：两次运行的关键日志行
- `evidence/hashes_and_filesf.txt`：Final4 `files.f` 的 155–158 行与哈希
- `tb/int16_accelerator_top_tb.sv`：仓库自带 TB（通用顶层用例）
- `tb/repo_bound_tb.sv`：同一 TB，DUT 换成绑定顶层，`CTRL_BASE=0`

## 备注

仓库 TB 里 `memory` 数组同时被 `initial` 和 `always_ff` 驱动，VCS 会报 `ICPD`。把 TB 里那一处 `always_ff` 改成 `always` 即可编译；只改 TB，不改 RTL。`tb/` 下的两个文件已经包含这个改动。
