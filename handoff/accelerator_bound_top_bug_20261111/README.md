# 给硬件同学的最终4加速器问题交接包

> 这是独立交接快照分支（orphan），只包含本目录；**只读，不要直接合并到 main/hardware**。
> 需要正式合入时，请把本目录拷到目标分支再提交。

先看 `BUG_REPORT.md`（结论 + 复现结果 + 怀疑位置）。

## 里面有什么

| 文件 | 用途 |
|---|---|
| `BUG_REPORT.md` | 问题结论、证据、怀疑的代码位置、需要修的点 |
| `REPRO.md` | 服务器 VCS 复现命令（通用顶层 PASS、绑定顶层 TIMEOUT） |
| `MESSAGE_TO_HW.md` | 可以直接复制到微信/群里的短消息 |
| `evidence/key_logs.txt` | 两次运行的关键日志原文 |
| `evidence/hashes_and_filesf.txt` | Final4 `files.f` 的 155–158 行与 RTL 哈希 |
| `tb/int16_accelerator_top_tb.sv` | 仓库自带 TB（通用顶层用例，已做 VCS ICPD 兼容改动） |
| `tb/repo_bound_tb.sv` | 同一 TB，DUT 换成 Final4 绑定顶层，`CTRL_BASE=0` |

## 核心结论

- 通用顶层 `int16_accelerator_top`（df45c9a）：**PASS**，K64 + K256，两个连续作业。
- Final4 绑定顶层 `int16_accelerator_top_32_11000000_0`：**TIMEOUT**，`S_RESULT`、`k=63`、`counts=560/560`、无 `accel_error`。
- 问题在顶层状态机/权重缓存收尾，不在 PE 数值逻辑。

## 边界

- 没有改冻结网表、DDC、SDC、工艺库。
- 只改了 TB 的一处 `always_ff → always`（VCS `ICPD` 限制），RTL 未动。
- 这包是 bug 交接，不是 Final4 功能 PASS 证据。
