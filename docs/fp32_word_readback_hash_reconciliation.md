# FP32 缓存读回 CSV 指纹争议复核（2026-10-18）

> **阶段性核验，非硬件验收。**本报告比较两份不同的 CSV，不覆盖旧报告或原始文件。这里的 PASS 只表示现有 144 条**缓存读回记录**与本仓库软件镜像一致；软件没有重跑硬件仿真，也没有验证 PE 乘加、DMA、E203 或 SoC。

## 结论先行

- 10 月 17 日软件报告与 10 月 18 日硬件回复检查的**不是同一份 CSV**。旧仓库版相对当前软件镜像有 3 组错误的 `input_sha256`；新收到的本地版已改成与九个 `.bin` 一致的值。两边各自针对自己的文件所说的“3 组失败”和“9 组通过”均可复现。
- 两版都有 144 条记录。逐字段比较，只有 `input_sha256`（7 行，分属 3 组）和 `rtl_snapshot_sha256`（全部 144 行）不同；其余 18 列，包括 16 位读回字、重组的 FP32 字、地址、坐标和周期字段，逐行相同。换行方式也不同，但**换行不解释输入 `.bin` 哈希错误**。
- 九个当前 `.bin` 与 `db073056212677f8f3fe6df3b0bbb82bbcfa9202` 和当前软件 HEAD `22dafe84bddb5794d5368a4c2304e188dad0be5b` 中同路径 Git blob **逐字节一致**。因此在可取得的软件版本之间，没有“输入文件换版”证据。旧版三处更符合 **A：使用了旧 CSV；D：旧 CSV 的来源哈希字段有误**。无法仅凭现有材料追溯错误由谁、何时、如何写入。
- 新版 CSV 的 `mem_hex_file` 指向另一台机器的 `D:/competition/testdata/software_db073056/...`，本机不存在。硬件运行时究竟读取了哪份文件、改动后的 RTL 快照来自哪些源码，仍需仿真命令、filelist、输入镜像和日志佐证。新 CSV **尚不能宣称是已提交的正式硬件版本**。

## 文件版本与来源

| 版本 | 绝对路径/取得方法 | 文件 SHA-256 | Git/状态 | CSV 内 RTL 指纹 |
|---|---|---|---|---|
| 旧仓库版，10 月 17 日软件报告所用 | `C:\Users\Lenovo\Documents\Codex\kwt1-team-checkout-20261017` 内执行 `git show origin/hardware:handoff/word_readback.csv`；旧诊断副本 `C:\Users\Lenovo\Documents\Codex\_kwt1_temp\word_readback.csv` 与该 blob 逐字节一致 | `6d7de5bfb22f4b817921a47cc79982a23ef8a3d4c45f679d7d8344d76c463250`（LF） | 本地缓存 `origin/hardware` 提交 `acfae7282f2d16f6fe8df476efed147f23df4b71`；本轮远端 fetch 失败，故不能证明该 ref 仍是服务器最新状态 | `rtl_revision=6e0bd881b6acde166ea86636307ac5c69207a57d+dirty`；`rtl_snapshot_sha256=075343d2eedcf39baf237ca73b1bad7ca2f6113a51a32002e7f0262d8b532c93` |
| 新收到的硬件本地版，10 月 18 日复核对象 | `E:\大二上\实验室\芯片设计\word_readback.csv` | `d7ba2ee7ae5678552899008b292398df861a6da28d06fa13bfa28dd53e732a1b`（CRLF） | 目前只找到这份独立本地文件；未找到对应 Git commit，不能从软件工作区判断它在硬件仓库中是否已提交 | `rtl_revision` 仍为上面的 `6e0…+dirty`；`rtl_snapshot_sha256=7c42767dfe3a7be8b39a93d3dbb2e6322c3b3bf0b4fe48c99a2bb6b8fe2bd4fd` |

旧硬件进度文档给出的 CSV 哈希 `61adcaf0e057e060a945e5dca11c11746221950809013805988261674c46272b` 可由**旧仓库版**单纯将 145 个 LF 换成 CRLF 复现；它仍不是新收到文件的 `d7ba…`。旧 CSV 的 `rtl_revision` 包含 `+dirty`，两个 `rtl_snapshot_sha256` 均未经当前软件侧取得完整源码快照与 filelist 独立重算。两份文件不能只凭相同 `rtl_revision` 判为同一仿真。

## 九组输入逐字节核验

以下“实际文件”共同目录为：`C:\Users\Lenovo\Documents\Codex\kwt1-team-checkout-20261017\software\examples\fp32_hand_image\`。文件对应关系同时由 CSV 的 `case/tensor/input_bin`、软件 `manifest.json` 中的形状、字数、`sha256_bin`、同名 `.mem` 重建的字节以及逐行读回字值核对，**不是只看文件名**。实际哈希直接对存在的 `.bin` 字节计算。表中“新登记”均等于“实际”；“旧登记”只有三处不同。

| 组 | 实际文件、字节数 | 旧 CSV 登记的 `input_sha256` | 新 CSV 登记 = 当前 `.bin` 实际 SHA-256 | 新版结果 |
|---|---|---|---|---|
| `hand_2x2/X` | `x.bin`，16 | `f8788ce138a2b6e54302c09bd3d5274cb2fc3ceca6425b02c788181d332edc6d` | `f8788ce138a2b6e54302c09bd3d5274cb2fc3ceca6425b02c788181d332edc6d` | 匹配 |
| `hand_2x2/W` | `w.bin`，16 | `9b4a9050f1cea2e3bcbb7e5fe240d352eeed38c80b57cd1c9b45a8f9f7c650d7a` | `9b4a9050f1cea2e3bcb7e5fe240d352eeed38c80b57cd1c9b45a8f9f7c650d7a` | 匹配；旧版失败 |
| `hand_2x2/BIAS` | `bias.bin`，8 | `a87f7282fda4eba58e73df7310253f02b521d912a9d040beb42c09dceae258fd` | `a87f7282fda4eba58e73df7310253f02b521d912a9d040beb42c09dceae258fd` | 匹配 |
| `rounding_nonfused/X` | `rounding_x.bin`，8 | `17075bc174311a170d9562e85cf701ae9f4d84a239863a42642554984dd267f2` | `17075bc174311a170d9562e85cf701ae9f4d84a239863a42642554984dd267f2` | 匹配 |
| `rounding_nonfused/W` | `rounding_w.bin`，8 | `c3ab17f29a1c4ba6387856faf4915c03dd5804974feb9ecfddd4fbcc6b41c3ea` | `c3ab17f29a1c4ba6387856faf4915c03dd5804974febb9ecfddd4fbc6b41c3ea` | 匹配；旧版失败 |
| `rounding_nonfused/BIAS` | `rounding_bias.bin`，4 | `df3f619804a92fdb4057192dc43dd748ea778adc52bc498ce80524c014b81119` | `df3f619804a92fdb4057192dc43dd748ea778adc52bc498ce80524c014b81119` | 匹配 |
| `k32_boundary/X` | `tile_x.bin`，256 | `2f20cd03c9cd392a406c56232b0ff93a15f6d6d7da79086bfa14f55d4a4031b0` | `2f20cd03c9cd392a406c56232b0ff93a15f6d6d7da79086bfa14f55d4a4031b0` | 匹配 |
| `k32_boundary/W` | `tile_w.bin`，256 | `5889666823c2bcf52f9cb08b572630a61cd0c2b5d3a7a1df11d6d81c0e8fe007` | `5889666823c2bcf52f9cb08b572630a61cd0c2b5d3a7a1df11d6d81c0e8fe007` | 匹配 |
| `k32_boundary/BIAS` | `tile_bias.bin`，4 | `75e253f50979177e2ba47b2d0805ad36038789108924514d2a761a70de057d16f` | `75e253f50979177eba47b2d0805ad36038789108924514d2a761a70de057d16f` | 匹配；旧版失败 |

旧版三处错误的具体形态：`hand_2x2/W` 多一个 `b`、`k32_boundary/BIAS` 多一个 `2`，两者是 **65 位**十六进制文本，根本不是合法 SHA-256 字符串；`rounding_nonfused/W` 为 64 位但与真实值有两个字符位置不同（旧版 `…4feb9…4fbcc…`，新版 `…4febb9…4fbc6…`）。这些是**CSV 字段文本差异**，不是 `.bin` 或换行发生变化的证据。

## 复现方法与实测结果

从上述仓库根目录执行；`python` 须是能导入 `software` 包的 Python 3。旧文件通过 `git show` 提取到**另一个临时位置**，不要改硬件原件：

```powershell
python -c "import pathlib,subprocess; pathlib.Path('old_word_readback_from_git.csv').write_bytes(subprocess.check_output(['git','show','origin/hardware:handoff/word_readback.csv']))"
python -m software.check_word_readback --csv old_word_readback_from_git.csv --image-dir software/examples/fp32_hand_image
python -m software.check_word_readback --csv 'E:\大二上\实验室\芯片设计\word_readback.csv' --image-dir software/examples/fp32_hand_image
```

本轮实际通过 `check_readback()` 执行同一严格核验逻辑：**旧版 FAIL，报 `input SHA-256 disagrees in 3 group(s)`，组名恰为上表三处；新版 PASS，`records_checked=144`、`groups=9`、返回 CSV 哈希 `d7ba…`**。校验器还核对 `.mem` 与 `.bin` 一致、144 个元素覆盖、低高 16 位字、地址、位模式及 CSV 声明的周期关系。它不能审计 CSV 是否真的由仿真器生成，也不能独立证明 RTL 的周期记录真实。

## 尚缺的原始证据与双方下一步

1. **硬件侧：**给新 CSV 一个可引用的仓库提交/文件路径和自身 SHA-256；附产生它的原始 `.bin/.mem` 或可获取的提交号、完整 filelist、仿真命令、仿真器版本和日志；说明新旧 `rtl_snapshot_sha256` 的生成算法及对应源码集合。特别是 CSV 的 `D:/competition/testdata/software_db073056/...` 本机不存在，现只能与已知软件镜像做交叉核对，不能证明硬件机当时确实打开那些文件。
2. **软件侧：**保留两份原始 CSV 和本报告；待硬件提交新版后从该**固定提交**重新抽取并核验，确认是否仍为 `d7ba…`。现有脚本已能完整复现争议，无须为通过而修改 CSV 或参考数据。
3. **共同：**先确认哪一份文件作为正式读回附件。即使选新版并核验通过，结论仍限于缓存读回；真实 FP32 PE trace、阵列和 SoC 验证分别另交证据。

旧记录中的“三组失败”是对旧版文件的真实检测，不应被直接删改为 PASS；新版的“九组通过”也不应倒写为旧版已通过。
