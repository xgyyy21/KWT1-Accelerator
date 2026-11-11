# 给硬件同学的短消息（可直接复制）

加速器顶层有个功能问题，麻烦你确认一下。

Final4 综合实际用的 `int16_accelerator_top_32_11000000_0`（`int16_accelerator_top_bound.sv`，带权重缓存）跑不完一个作业：在 `k=63` 进入 `S_RESULT` 后一直等不到 `pe_result_valid`，不写回也不报错，最终超时。关键日志：

```
TIMEOUT state=8 (S_RESULT) k=63 counts=560/560 rsp_pending=0 master_outstanding=0
```

用仓库自带的 `int16_accelerator_top_tb.sv` 做对照：换回 df45c9a 的通用顶层 `int16_accelerator_top` 是 **PASS**（K64 + K256，两个连续作业）。所以不是 PE 数值逻辑，也不是测试平台，问题在绑定顶层的状态机/权重缓存收尾路径，怀疑最后一个奇数 k 没有真正走完带 `mac_last=1` 的 `S_MAC`，或者 `S_TILE_A_REQ` 这条未完成分支被走到。

复现命令、失败日志、两个 TB 都在仓库的 `handoff/accelerator_bound_top_bug_20261111/` 里（`BUG_REPORT.md` / `REPRO.md`）。麻烦先按 `REPRO.md` 复现一次；确认后修 RTL，修完先跑仓库 TB 的 K64 + K256，再跑整层 99×64×256。

不要动冻结网表/DDC/SDC；修 RTL 请在新分支或新目录。修完重新综合后，再做 RTL↔网表形式等价作为回归。
