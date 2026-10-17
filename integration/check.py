#!/usr/bin/env python3
"""Local inventory/tool smoke checks, with opt-in hardware module regression.

Default: no model, team RTL, SoC simulation, synthesis or PPA is executed.
--hardware-source runs the team's unchanged module regression in an isolated copy.
Exit codes: 0=no FAIL/BLOCKED; 1=FAIL; 2=BLOCKED without FAIL.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import platform
import shutil
import subprocess
import sys
import tempfile
from collections import Counter
from datetime import datetime, timezone, timedelta
from uuid import uuid4


ROOT = Path(__file__).resolve().parents[1]
STATUSES = ("PASS", "FAIL", "BLOCKED", "NOT_RUN")
CN_TIME = timezone(timedelta(hours=8), "Asia/Shanghai")
DIRECTORIES = (
    "software", "rtl", "tb", "soc", "synthesis", "integration", "docs", "reports"
)
DOCUMENTS = (
    "README.md", "CONTRIBUTING.md", ".gitignore", "docs/HANDOFF_TEMPLATE.md",
    "docs/PROJECT_STATUS.md", "docs/REQUIREMENTS.md", "docs/SUBMISSION_CHECKLIST.md",
    "integration/check.py",
)
MATERIALS = (
    "嵌赛题目.pdf", "KWT-1_软件与硬件交接和并行安排.md",
    "硬件侧回复_软件交接_2026-10-16.md",
)
SKIP_DIRS = {
    ".git", "__pycache__", ".venv", "venv", "node_modules", "tmp", "temp",
    "build", "dist", "external", "datasets", "checkpoints", "obj_dir", "work",
    "pdk", "techlib", ".codex", ".agents",
}


def execute(command: list[str], cwd: Path = ROOT, timeout: int = 15) -> dict:
    """Capture actual commands; never install, fetch, or use shell-built commands."""
    try:
        result = subprocess.run(
            command, cwd=cwd, capture_output=True, text=True,
            encoding="utf-8", errors="replace", timeout=timeout, check=False,
        )
        return {
            "command": command, "returncode": result.returncode,
            "windows_returncode_hex": (f"0x{result.returncode & 0xffffffff:08X}"
                                       if os.name == "nt" and result.returncode else None),
            "stdout": result.stdout[:16000], "stderr": result.stderr[:16000],
            "output_truncated": len(result.stdout) > 16000 or len(result.stderr) > 16000,
        }
    except (OSError, subprocess.TimeoutExpired) as exc:
        return {"command": command, "returncode": None, "error": str(exc)}


def files_under(directory: str, suffixes: set[str]) -> list[str]:
    base = ROOT / directory
    found = []
    if not base.is_dir():
        return found
    for current, dirs, files in os.walk(base):
        dirs[:] = sorted(d for d in dirs if d.lower() not in SKIP_DIRS)
        for name in sorted(files):
            path = Path(current) / name
            if path.suffix.lower() in suffixes and path.stat().st_size:
                found.append(path.relative_to(ROOT).as_posix())
    return found


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--hardware-source", type=Path)
    parser.add_argument("--hardware-manifest", type=Path,
                        default=ROOT / "reports/stage4a/hardware_manifest.json")
    parser.add_argument("--hardware-iverilog")
    parser.add_argument("--hardware-vvp")
    parser.add_argument("--context", default="unspecified")
    options = parser.parse_args()
    started = datetime.now(CN_TIME)
    checks: list[dict] = []

    def add(check_id: str, category: str, status: str, summary: str,
            evidence=None, missing=()) -> None:
        assert status in STATUSES
        checks.append({
            "id": check_id, "category": category, "status": status,
            "summary": summary, "evidence": evidence,
            "missing_dependencies": list(missing),
        })

    python_run = execute([sys.executable, "--version"])
    python_ok = sys.version_info >= (3, 11) and python_run["returncode"] == 0
    add("python_runtime", "stage1", "PASS" if python_ok else "FAIL",
        "当前解释器启动成功且版本至少为 3.11" if python_ok else "Python 启动或版本检查失败",
        {"executable": sys.executable, "version": sys.version, "probe": python_run})

    git = shutil.which("git")
    git_info = {"executable": git, "commit": None, "branch": None, "status_porcelain": None}
    if not git:
        add("git_repository", "stage1", "BLOCKED", "PATH 无 Git，无法检查仓库", missing=["Git"])
        add("git_commit", "readiness", "BLOCKED", "无法读取当前提交", missing=["Git"])
        add("git_worktree", "stage1", "BLOCKED", "无法读取工作区状态", missing=["Git"])
    else:
        probe = execute([git, "rev-parse", "--show-toplevel"])
        actual_root = probe.get("stdout", "").strip()
        correct_root = probe["returncode"] == 0 and Path(actual_root).resolve() == ROOT
        add("git_repository", "stage1", "PASS" if correct_root else "FAIL",
            "项目根目录为独立 Git 仓库" if correct_root else "仓库未初始化或根目录不匹配", probe)
        if correct_root:
            version = execute([git, "--version"])
            branch = execute([git, "symbolic-ref", "--quiet", "--short", "HEAD"])
            head = execute([git, "rev-parse", "--verify", "HEAD"])
            git_info["version"] = version
            git_info["branch"] = branch.get("stdout", "").strip() or "detached HEAD"
            if head["returncode"] == 0:
                git_info["commit"] = head["stdout"].strip()
                add("git_commit", "readiness", "PASS", "读取当前提交版本", head)
            else:
                unborn = execute([git, "symbolic-ref", "--quiet", "HEAD"])
                no_ref = (execute([git, "show-ref", "--verify", "--quiet", unborn["stdout"].strip()])
                          if unborn["returncode"] == 0 else None)
                is_unborn = no_ref is not None and no_ref["returncode"] == 1
                add("git_commit", "readiness", "BLOCKED" if is_unborn else "FAIL",
                    "尚无首个提交；未自动暂存或创建提交" if is_unborn else "HEAD 读取失败，需检查 Git",
                    {"head": head, "symbolic_ref": unborn, "reference_probe": no_ref},
                    ["人工审阅并创建首个提交"] if is_unborn else [])
            status = execute([git, "-c", "core.quotepath=false", "status", "--porcelain=v1", "--untracked-files=all"])
            git_info["status_porcelain"] = status.get("stdout", "")
            git_info["dirty"] = bool(git_info["status_porcelain"].strip())
            add("git_worktree", "stage1", "PASS" if status["returncode"] == 0 else "FAIL",
                "已读取工作区状态；存在未提交文件不等于设计失败", status)
            remote = execute([git, "remote"])
            add("git_remote_inventory", "stage1", "PASS" if remote["returncode"] == 0 else "FAIL",
                "仅记录远程名称；未新增或修改远程",
                {"names": remote.get("stdout", "").splitlines(), "returncode": remote["returncode"]})
        else:
            for check_id in ("git_commit", "git_worktree"):
                add(check_id, "readiness", "BLOCKED", "依赖有效的项目 Git 仓库", missing=["项目 Git 仓库"])

    for directory in DIRECTORIES:
        present = (ROOT / directory).is_dir()
        add("dir_" + directory, "stage1", "PASS" if present else "FAIL",
            f"目录清点：{directory}/；不表示工程功能通过", {"exists": present})
    for relative in DOCUMENTS:
        path = ROOT / relative
        present = path.is_file() and path.stat().st_size > 0
        add("file_" + relative, "stage1", "PASS" if present else "FAIL",
            f"非空文件清点：{relative}；不验证内容功能", {"exists_nonempty": present})

    material_hashes = {}
    for name in MATERIALS:
        path = ROOT / name
        present = path.is_file() and path.stat().st_size > 0
        if present:
            material_hashes[name] = {"sha256": sha256(path), "bytes": path.stat().st_size}
        add("material_" + name, "stage1", "PASS" if present else "BLOCKED",
            f"原始材料清点：{name}；文件存在不等于内容完整或代码已验证",
            material_hashes.get(name), [] if present else [name])

    known_pdf = material_hashes.get("嵌赛题目.pdf", {}).get("sha256") == (
        "354977bf737a6c21b1267fd96853ff6bdcb5c7fa82c240f8ff190845f980d719")
    add("official_version_completeness", "readiness", "BLOCKED" if known_pdf else "NOT_RUN",
        ("2026-10-16 人工逐页核对：本地 PDF 为印刷 2～14 页；完整官方版本尚未确认"
         if known_pdf else "官方 PDF 已变更或缺失，需重新人工核对完整性和版本"),
        {"manual_audit": "docs/REQUIREMENTS.md", "automatic_pdf_parsing": False},
        ["完整官方赛题（含印刷第 1 页）及版本/更正公告确认"])
    for name in ("硬件设计定义.txt", "硬件设计实现.txt"):
        found = (ROOT / name).is_file() and (ROOT / name).stat().st_size > 0
        add("teacher_" + name, "readiness", "PASS" if found else "BLOCKED",
            f"老师原始材料清点：{name}；现有硬件回复中的转述不等于原文",
            {"path": name, "exists_nonempty": found}, [] if found else [name])

    inventories = {}
    for directory, suffixes in (
        ("software", {".py", ".c", ".h"}), ("rtl", {".v", ".sv"}),
        ("tb", {".v", ".sv"}), ("soc", {".v", ".sv", ".c", ".h"}),
    ):
        found = files_under(directory, suffixes)
        inventories[directory] = found
        add("source_inventory_" + directory, "readiness", "PASS" if found else "BLOCKED",
            f"{directory}/ 源文件清点（不含 .gitkeep；不代表完整、可运行或通过）",
            {"files": found}, [] if found else [directory + " 实际工程源码"])

    for key, env_name, fallback, purpose in (
        ("e203", "KWT_E203_DIR", "external/e203", "指定 E203/SoC/SDK 平台"),
        ("techlib", "KWT_TECH_LIB_DIR", "external/techlib", "指定工艺标准单元库及 PVT/功耗资料"),
        ("sram", "KWT_SRAM_LIB_DIR", "external/sram", "指定 SRAM 宏仿真/时序/功耗/面积资料"),
        ("model", "KWT_MODEL_DIR", "external/model", "指定模型源码/权重/配置"),
        ("data", "KWT_DATA_DIR", "external/data", "合法 Speech Commands V2 数据及划分"),
    ):
        configured = Path(os.environ.get(env_name) or ROOT / fallback).expanduser()
        if not configured.is_absolute():
            configured = ROOT / configured
        try:
            present = configured.is_dir() and next(configured.iterdir(), None) is not None
            error = None
        except OSError as exc:
            present, error = False, str(exc)
        add("external_" + key, "readiness", "PASS" if present else "BLOCKED",
            f"{purpose}：仅非空目录清点，未核验版本/内容/许可/兼容性",
            {"path": str(configured), "environment_variable": env_name,
             "nonempty_directory": present, "error": error}, [] if present else [purpose])

    tools = {}
    for name, args in (
        ("iverilog", ["-V"]), ("vvp", ["-V"]), ("verilator", ["--version"]),
        ("yosys", ["-V"]), ("dc_shell", ["-version"]), ("genus", ["-version"]),
        ("riscv32-unknown-elf-gcc", ["--version"]),
        ("riscv64-unknown-elf-gcc", ["--version"]),
    ):
        executable = shutil.which(name)
        probe = execute([executable, *args]) if executable else None
        tools[name] = {"executable": executable, "probe": probe,
                       "startup_ok": probe is not None and probe["returncode"] == 0}

    icarus_ok = tools["iverilog"]["startup_ok"] and tools["vvp"]["startup_ok"]
    smoke = None
    if icarus_ok:
        try:
            with tempfile.TemporaryDirectory(prefix="kwt_tool_smoke_") as temporary:
                scratch = Path(temporary)
                source = scratch / "tool_smoke.v"
                target = scratch / "tool_smoke.vvp"
                source.write_text(
                    'module tool_smoke; initial begin\n'
                    '  $display("KWT_TOOL_SMOKE_OK"); $finish;\n'
                    'end endmodule\n', encoding="ascii")
                compile_run = execute(
                    [tools["iverilog"]["executable"], "-g2012", "-s", "tool_smoke",
                     "-o", target.name, source.name], cwd=scratch)
                simulation = (execute([tools["vvp"]["executable"], target.name], cwd=scratch)
                              if compile_run["returncode"] == 0 else None)
                passed = (simulation is not None and simulation["returncode"] == 0
                          and "KWT_TOOL_SMOKE_OK" in simulation.get("stdout", ""))
                smoke = {"compile": compile_run, "run": simulation,
                         "temporary_files_removed": True, "project_rtl_tested": False}
                add("verilog_tool_smoke", "stage1", "PASS" if passed else "FAIL",
                    ("Icarus 临时编译/运行冒烟通过；未使用项目 RTL，不是芯片功能验证"
                     if passed else "Icarus 版本可启动但临时编译/运行失败；详见实际返回码及输出"), smoke)
        except OSError as exc:
            add("verilog_tool_smoke", "stage1", "FAIL", "工具冒烟临时文件操作失败", {"error": str(exc)})
    else:
        installed_but_bad = any(tools[n]["executable"] and not tools[n]["startup_ok"] for n in ("iverilog", "vvp"))
        add("verilog_tool_smoke", "stage1", "FAIL" if installed_but_bad else "BLOCKED",
            "Icarus 编译/运行工具无法成对启动；Verilator 候选仅版本探测",
            {n: tools[n] for n in ("iverilog", "vvp", "verilator")},
            [n for n in ("iverilog", "vvp") if not tools[n]["startup_ok"]])

    for check_id, names, purpose in (
        ("synthesis_tool_startup", ("yosys", "dc_shell", "genus"), "逻辑综合工具启动"),
        ("riscv_toolchain_startup", ("riscv32-unknown-elf-gcc", "riscv64-unknown-elf-gcc"), "RISC-V 编译器启动"),
    ):
        available = [n for n in names if tools[n]["startup_ok"]]
        broken = [n for n in names if tools[n]["executable"] and not tools[n]["startup_ok"]]
        status = "PASS" if available else ("FAIL" if broken else "BLOCKED")
        add(check_id, "readiness", status,
            f"{purpose}：仅 PATH/版本启动检查，不证明指定平台/工艺支持或许可可用",
            {n: tools[n] for n in names}, [] if available else [purpose + "可用且获授权的指定工具"])

    sdc = files_under("synthesis", {".sdc"})
    filelists = files_under("synthesis", {".f"})
    add("synthesis_inputs_inventory", "readiness", "PASS" if sdc and filelists else "BLOCKED",
        "综合约束/RTL 清单清点；未创建最终脚本，不验证 SDC 有效性或 RTL 冻结",
        {"sdc_files": sdc, "filelists": filelists},
        ([] if sdc else ["经确认的 SDC/时钟复位/I/O/负载/时序例外依据"])
        + ([] if filelists else ["冻结 RTL、唯一顶层及编译顺序/宏清单"]))

    for check_id, summary, missing in (
        ("project_rtl_soc_verification", "项目 RTL/SoC 与 12 次连续任务验证",
         ["队友实际源码/测试入口", "冻结数值/布局/控制协议", "向量与指定 E203 平台"]),
        ("project_accuracy_verification", "真实 12 层精度与逐位一致性验收",
         ["指定真实模型/合法样本", "冻结数值参考", "RTL 实际输出及运行日志"]),
        ("project_synthesis_ppa", "正式逻辑综合、150 MHz 时序、面积与功耗评估",
         ["获授权的指定综合工具与工艺/宏资料", "冻结工程/SDC", "真实任务活动与计时事件"]),
    ):
        add(check_id, "project_validation", "BLOCKED", summary + "：缺少已核验依赖，本程序不执行", missing=missing)
    add("innovation_experiment", "future", "NOT_RUN", "创新方案未确定，本阶段未安排实验")
    add("final_submission_generation", "future", "NOT_RUN", "正式网表/截图/成绩及提交包未安排生成")

    hardware_report = None
    if options.hardware_source is not None:
        from hardware import run as run_hardware
        hardware_report = run_hardware(options.hardware_source, options.hardware_manifest,
                                       options.hardware_iverilog, options.hardware_vvp, options.context)
        add("hardware_module_regression", "hardware_modules", hardware_report["status"],
            "硬件组原脚本模块级回归；不代表完整 FP32 阵列、FFN1 或 E203 集成通过",
            {"report": hardware_report["report_path"],
             "commit": hardware_report.get("hardware_commit"),
             "test_count": hardware_report["test_count"], "counts": hardware_report["counts"],
             "failed_modules": hardware_report["failed_modules"]})

    counts = {s: sum(c["status"] == s for c in checks) for s in STATUSES}
    stage_counts = dict(Counter(c["status"] for c in checks if c["category"] == "stage1"))
    overall = "FAIL" if counts["FAIL"] else ("BLOCKED" if counts["BLOCKED"] else "PASS")
    stage_status = ("FAIL" if stage_counts.get("FAIL") else
                    "BLOCKED" if stage_counts.get("BLOCKED") else "PASS")
    exit_code = 1 if counts["FAIL"] else (2 if counts["BLOCKED"] else 0)
    finished = datetime.now(CN_TIME)
    report = {
        "schema_version": 1,
        "scope": ("inventory, environment smoke, and opt-in hardware module regression"
                  if hardware_report else "stage1 inventory and environment smoke only"),
        "started_at": started.isoformat(), "finished_at": finished.isoformat(),
        "timezone": "Asia/Shanghai (UTC+08:00)", "root": str(ROOT),
        "platform": platform.platform(), "git": git_info,
        "overall_status": overall, "stage1_basic_status": stage_status,
        "counts": counts, "exit_code": exit_code,
        "notes": [
            "PASS 仅对应单个检查的明确范围，文件清点不代表设计功能通过。",
            "缺失工具以当前 PATH 为界；未安装/下载任何工具或资产。",
            "Git 状态在本次报告写入前采集，报告本身及之后的文件变动不在该快照中。",
            "完整工程验证仍 BLOCKED；可选硬件模块回归单列，不替代整层/SoC/精度/综合验收。",
        ],
        "material_hashes": material_hashes, "source_inventory": inventories,
        "tool_probes": tools, "checks": checks,
        "missing_dependencies": sorted({d for c in checks for d in c["missing_dependencies"]}),
    }
    output_dir = ROOT / "reports"
    output_dir.mkdir(parents=True, exist_ok=True)
    stem = "basic_check_" + started.strftime("%Y%m%d_%H%M%S_%f") + "_" + uuid4().hex[:6]
    json_path = output_dir / (stem + ".json")
    md_path = output_dir / (stem + ".md")
    report["report_files"] = {"json": str(json_path), "markdown": str(md_path)}
    with json_path.open("x", encoding="utf-8", newline="\n") as stream:
        json.dump(report, stream, ensure_ascii=False, indent=2)
        stream.write("\n")
    lines = [
        "# KWT-1 阶段 1 基础检查", "", f"- 开始：{report['started_at']}",
        f"- 结束：{report['finished_at']}", f"- 根目录：`{ROOT}`",
        f"- Git 提交：`{git_info['commit'] or '无可用提交（尚未首提交或读取失败）'}`",
        f"- 分支：`{git_info['branch']}`；工作区变更：`{git_info.get('dirty', '未知')}`",
        f"- 阶段 1 基础入口：**{stage_status}**；工程准备总览：**{overall}**",
        "- 计数：" + " / ".join(f"{s}={counts[s]}" for s in STATUSES),
        f"- 退出码：{exit_code}", "",
        ("本次包含单列硬件模块回归，详见对应报告；未执行完整 FFN1/E203、精度、综合或 PPA。"
         if hardware_report else "本报告不执行项目 RTL/SoC、精度、逻辑综合或 PPA。")
        + "PASS 只覆盖所述检查范围。", "",
        "| 检查项 | 分类 | 状态 | 结论 |", "|---|---|---|---|",
    ]
    for check in checks:
        summary = check["summary"].replace("|", "\\|").replace("\n", " ")
        lines.append(f"| {check['id']} | {check['category']} | {check['status']} | {summary} |")
    lines += ["", "## 缺失依赖", ""] + ["- " + d for d in report["missing_dependencies"]]
    lines += ["", "## 原材料 SHA-256", ""]
    lines += [f"- `{name}`：`{data['sha256']}`（{data['bytes']} 字节）"
              for name, data in material_hashes.items()]
    lines += ["", "## 实际命令、输出与结构化证据", "",
              "详细工具版本、stdout/stderr、返回码、源码清单及每项证据见同名 JSON。", ""]
    for check in checks:
        if check["evidence"] is not None:
            lines += [f"### {check['id']}", "", "```json",
                      json.dumps(check["evidence"], ensure_ascii=False, indent=2), "```", ""]
    lines += ["## 边界", ""] + ["- " + note for note in report["notes"]]
    with md_path.open("x", encoding="utf-8", newline="\n") as stream:
        stream.write("\n".join(lines) + "\n")
    print("KWT-1 stage 1 basic checks")
    print(f"Time: {started.isoformat()}")
    print(f"Stage1 basic: {stage_status}; Overall readiness: {overall}")
    print(" | ".join(f"{s}={counts[s]}" for s in STATUSES))
    print(f"Commit: {git_info['commit'] or '(no commit)'}")
    print(f"Markdown: {md_path}")
    print(f"JSON: {json_path}")
    print(f"Exit code: {exit_code}")
    return exit_code


if __name__ == "__main__":
    raise SystemExit(main())
