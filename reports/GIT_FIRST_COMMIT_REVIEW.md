# 首次 Git 提交审查

日期：2026-10-16；范围：阶段一管理代码、文档、预留标记和实测日志。

用户明确授权首次本地提交；作者选为 Codex <codex@local.invalid>，通过单次命令参数设置。没有远程、推送或全局配置修改。

## 跳过的原始材料

- `嵌赛题目.pdf`：保留本地，精确忽略，不暂存；建议确认赛事/队友资料入库权限后再决定。
- `KWT-1_软件与硬件交接和并行安排.md`：保留本地，精确忽略，不暂存；建议确认赛事/队友资料入库权限后再决定。
- `硬件侧回复_软件交接_2026-10-16.md`：保留本地，精确忽略，不暂存；建议确认赛事/队友资料入库权限后再决定。

## 审查结果

- 候选均为 UTF-8 文本或空目录标记，无二进制、工具程序、模型、数据集、工艺库或波形；每文件小于 1 MiB。
- 已检查内容及高置信凭证签名，未发现实际凭证/私钥；诊断 JSON 已移除完整个人 PATH，仅保留相关运行信息与工具路径。未将原始材料全文加入日志。
- 忽略规则实测覆盖外部权重、数据、safetensors、工艺库、VCD/SAIF、缓存、个人配置、.env 和三份原始材料；小型向量 mem 与普通 JSON 报告仍可版本管理。
- 没有把安装程序、第三方原始模型/平台或队友代码加入候选；文档中的官方要求摘要属于本阶段工程管理文档。
- 旧失败日志按历史证据保留，不将其改写成通过。首提交前新报告 stage1 PASS，整体 BLOCKED 是缺少项目依赖。

## 全部暂存候选

| 文件 | 字节（本次审查时） | SHA-256 |
|---|---:|---|
| .gitignore | 1231 | 95491677e6a6a917b515070afaf80504a0bb3c11010ae28bc7e239923af5cabb |
| README.md | 3760 | 3b0ce4cb07c68966210bebefe0500a67be273c795fd794b43f8991f0be0c5b8a |
| CONTRIBUTING.md | 2060 | 838200a6586ecd3c1c5614baebbb92c306d99d1e2f090603a596c55410952518 |
| integration/check.py | 20250 | 598f90307669b9376d655e50e534f9be9f8979cc2f8e1396f19dfc23d4671af4 |
| docs/HANDOFF_TEMPLATE.md | 350 | a02a83662fa639e8aa9beb894032619819ba9e2bf69694a88aea9c7e267c98c8 |
| docs/PROJECT_STATUS.md | 5384 | 8c12e274e2324f5861b1e37f30b7d510d2f83d519a9c5c3f09c1ef367b0ed4b0 |
| docs/REQUIREMENTS.md | 5589 | b081fdf2e01d1dca913cea4e45dcb673ce74cd7b2c6629154eb352122cf44586 |
| docs/SUBMISSION_CHECKLIST.md | 3365 | 95239e9dd82eb95e7940087fd02c9e9f9729eaaf229cb673aac70fae2fe2d94e |
| software/.gitkeep | 1 | 01ba4719c80b6fe911b091a7c05124b64eeece964e09c058ef8f9805daca546b |
| rtl/.gitkeep | 1 | 01ba4719c80b6fe911b091a7c05124b64eeece964e09c058ef8f9805daca546b |
| tb/.gitkeep | 1 | 01ba4719c80b6fe911b091a7c05124b64eeece964e09c058ef8f9805daca546b |
| soc/.gitkeep | 1 | 01ba4719c80b6fe911b091a7c05124b64eeece964e09c058ef8f9805daca546b |
| synthesis/.gitkeep | 1 | 01ba4719c80b6fe911b091a7c05124b64eeece964e09c058ef8f9805daca546b |
| reports/basic_check_20261016_211817_710957_72225f.json | 28461 | 474e5efc9c56dd3147c2e0b95b02081f9a3534ec2d2c5037dbbe5c7e4978b560 |
| reports/basic_check_20261016_211817_710957_72225f.md | 14646 | 602cc0cf271100ed674da7a07ff697651a19120cde9179631a66697f20655612 |
| reports/basic_check_20261016_212034_152623_8bcde9.json | 28878 | b58df9d55eb9e6040522b72d5aea81ecacb4d179ae04201ada291cdc46e9ebb2 |
| reports/basic_check_20261016_212034_152623_8bcde9.md | 14787 | 82abfa7861c4ec9b17b52651dd27c848159311ebcbb285ed040723d5e5265e69 |
| reports/basic_check_20261016_214034_843451_1a32d2.json | 29596 | b3f980674a5011086dc249524434bef14cfb28bed77d39992f81d0e91f9f6f37 |
| reports/basic_check_20261016_214034_843451_1a32d2.md | 15263 | 0d27123d8d59bcdf62ac3bb1088048ef5ed45681342c9a628c6fedefc937e235 |
| reports/ICARUS_DIAGNOSIS.json | 43945 | cb05cb4515891668d6f1d40766dcbf867cfb8b6fd4b6cc47c85a6617c7906583 |
| reports/ICARUS_DIAGNOSIS.md | 4237 | 44196065da4f78cc5e9239cd1a7acfa477113376cab8cf32a7f5aae0958361a4 |
| reports/STAGE1_EXECUTION.md | 4858 | 462c14e580b3a3e3c0dba65737501cec078e6aa68edf0a6b10c7708a4a26a9a6 |
| reports/GIT_FIRST_COMMIT_REVIEW.md | 本审查文件 | 不记录自身哈希以避免递归 |

共 23 个候选文件；除本审查文件外共 226665 字节。

只按精确路径列表暂存，提交前复核 Git index 与此列表相同。提交后另行运行基础检查，生成的新报告保留工作区，不为使报告引用自身 commit 而循环修改提交。
