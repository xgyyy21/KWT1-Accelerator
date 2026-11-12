# 报告协作规范（队友必读）

目标：多人改同一份报告，**每一处修改都能追溯到人、时间、原因**，随时可回滚。

---

## 0. 一条铁律

**`main` 分支不直接改。** 所有修改走「分支 → 提交 → Pull Request → 合并」。

- `main` 永远是"已确认"的版本；
- 每个人的修改在独立分支上，互不覆盖；
- 合并后历史里保留完整 diff。

---

## 1. 第一次准备（每人一次）

```bash
git clone https://github.com/xgyyy21/KWT1-Accelerator.git
cd KWT1-Accelerator
git config user.name  "你的名字"
git config user.email "你的邮箱"
```

如果 `github.com:443` 连不上，改用 SSH（22 端口通）：

```bash
git remote set-url origin git@github.com:xgyyy21/KWT1-Accelerator.git
```

> 不要共用别人的 token。每人用自己的账号或自己的 SSH key。

---

## 2. 每次改报告

```bash
git checkout main
git pull
git checkout -b report/你的名字-改什么
# 例：git checkout -b report/lisi-quant-section
```

编辑 `reports/final4_20261112/` 下的文件，然后：

```bash
git add reports/final4_20261112
git commit -m "reports(quant): 修正 100 样本 NRMSE 表述 [lisi]"
git push -u origin report/你的名字-改什么
```

到 GitHub 上点 **Compare & pull request**，写清楚：
- 改了哪一节
- 依据是什么（日志/报告/数据）
- 有没有改变结论

---

## 3. 提交信息格式（必须）

```
reports(<章节>): <做了什么> [<名字>]

例：
reports(arch): 补充权重 tile 的 bank 映射 [lisi]
reports(timing): 把 hold 结论改为 DC STA 口径 [wangwu]
reports(evidence): 新增 100 样本 per_layer 表 [zhaoliu]
```

一章一提交，不要一次提交十个不相干的改动。

---

## 4. 哪些文件可以改

| 文件 | 说明 |
|---|---|
| `REPORT_PRELIMINARY.md` | 对外提交版，**只在这里定稿** |
| `REPORT_DRAFT.md` | 内部完整版（含失败记录） |
| `REPORT_QUANT_ARCH.md` | 量化/架构专题 |
| `HANDOVER.md` | 交接文档 |
| `GATE_DEBUG.md` | 门级调试记录 |
| `NRMSE_*.md` / `per_layer_100.csv` | 精度证据 |
| `KWT1_Final4_设计与验证报告.docx` | **导出产物，不要直接编辑** |

> `.docx` 是给人看的导出件；源文件是 `.md`。改内容请改 md，再统一导出。
> 如果必须在 Word 里改，请开「修订模式」，并在 PR 里说明改的是哪一版导出件。

---

## 5. 怎么查历史 / 怎么回滚

```bash
# 谁改了这一节
git log --oneline -- reports/final4_20261112/REPORT_PRELIMINARY.md

# 看某次具体改了什么
git show <commit>

# 看某一行是谁写的
git blame reports/final4_20261112/REPORT_PRELIMINARY.md

# 回到某次提交的版本
git checkout <commit> -- reports/final4_20261112/REPORT_PRELIMINARY.md
```

---

## 6. 冲突怎么处理

`git pull` 提示冲突时：

1. 打开冲突文件，搜索 `<<<<<<<`；
2. 保留正确内容，删掉标记；
3. `git add` + `git commit`；
4. 推送后在 PR 里说明"解决了与 xxx 的冲突"。

**不要**用 `git push -f`，除非确认只覆盖自己的分支。

---

## 7. 红线（改稿时不得引入）

1. 不写"官方 600 样本精度通过"；
2. 不写"Final4 门级 PASS / SDF PASS / LEC 通过"；
3. 不把 162.23 mW 当 Final4 功耗；
4. 不把 743,159 周期当吞吐；
5. 时序必须带 pre-layout / ideal clock / hold uncertainty=0，且 hold 为负；
6. 权重是 4 KB tile 级，不是整层驻留。

---

## 8. 推荐的章节分工（可调整）

| 章节 | 建议负责人 | 主要依据 |
|---|---|---|
| 一 性能窗口 |  | `REPORT_DRAFT.md` §1 |
| 二 量化格式 |  | `numeric_format_audit/` |
| 三 舍入饱和 |  | `int16_numeric.py` / 合同 |
| 四 架构与总线 |  | `REPORT_QUANT_ARCH.md` §3 |
| 五 权重 tile |  | `int16_weight_sram_16bank.sv` |
| 六 PE 阵列 |  | RTL |
| 七 综合/时序 |  | `area_hier.rpt`、`qor.rpt` |
| 八 验证 |  | `full_layer_test/` |
| 九 功耗 |  | `power_flow/`（待实测） |
