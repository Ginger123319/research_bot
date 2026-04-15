#!/usr/bin/env python3
"""
Publish local evaluation results to shared NFS for team Dashboard visibility.

Usage:
  # 按模型名发布（推荐）：复制所有关联实验目录 + model 目录，更新共享 INDEX.yaml
  python3 scripts/publish_results.py --model xinghan-ziwei-32b-v1

  # 预览发布内容（不实际复制）
  python3 scripts/publish_results.py --model xinghan-ziwei-32b-v1 --dry-run

  # 直接发布指定目录（不更新 INDEX.yaml）
  python3 scripts/publish_results.py results/my_exp_20260401 results/my_exp_20260402

  # 列出本地 INDEX.yaml 中所有模型名
  python3 scripts/publish_results.py --list

Reads SHARED_RESULTS_DIR from .env.local (auto-written by setup.sh).
"""

import argparse
import os
import shutil
import sys
from pathlib import Path

try:
    import yaml
except ImportError:
    print("❌ pyyaml 未安装，请运行：.venv-serve/bin/pip install pyyaml")
    sys.exit(1)

_PROJECT_ROOT = Path(__file__).resolve().parent.parent
_LOCAL_RESULTS = _PROJECT_ROOT / "results"
_LOCAL_INDEX   = _LOCAL_RESULTS / "models" / "INDEX.yaml"

# ── env helpers ───────────────────────────────────────────────────────────────

def _load_env_local():
    env_path = _PROJECT_ROOT / ".env.local"
    if env_path.is_file():
        with open(env_path) as f:
            for line in f:
                line = line.strip()
                if line and not line.startswith("#") and "=" in line:
                    k, v = line.split("=", 1)
                    os.environ.setdefault(k.strip(), v.strip())

def _get_shared_dir() -> Path:
    _load_env_local()
    shared = os.environ.get("SHARED_RESULTS_DIR", "")
    if not shared:
        print("❌ SHARED_RESULTS_DIR 未配置")
        print("   请运行 bash setup.sh（自动检测），或在 .env.local 中手动添加：")
        print("   SHARED_RESULTS_DIR=/mnt/ai-infra/users/shared/benchmark-results/guofan/results")
        sys.exit(1)
    p = Path(shared)
    if not p.is_dir():
        print(f"❌ 共享目录不存在：{p}")
        print("   请确认 /mnt/ai-infra NFS 已挂载")
        sys.exit(1)
    # 防止把共享目录发布到自身（原开发机软链场景）
    if p.resolve() == _LOCAL_RESULTS.resolve():
        print("ℹ️  本地 results/ 已指向共享目录，无需发布。")
        sys.exit(0)
    return p

# ── INDEX.yaml helpers ────────────────────────────────────────────────────────

def _load_index(path: Path):
    """Return (data_dict, header_comment_str)."""
    if not path.is_file():
        return {"models": []}, ""
    raw = path.read_text(encoding="utf-8")
    # 提取文件头注释（# 开头的连续行）
    header_lines = []
    for line in raw.splitlines():
        if line.startswith("#") or line.strip() == "":
            header_lines.append(line)
        else:
            break
    header = "\n".join(header_lines)
    data = yaml.safe_load(raw) or {}
    if "models" not in data:
        data["models"] = []
    return data, header

def _write_index(path: Path, data: dict, header: str):
    """Write INDEX.yaml, preserving header comments."""
    path.parent.mkdir(parents=True, exist_ok=True)
    body = yaml.dump(
        data,
        allow_unicode=True,
        default_flow_style=False,
        sort_keys=False,
        indent=2,
        width=120,
    )
    content = (header.rstrip() + "\n\n" + body) if header else body
    path.write_text(content, encoding="utf-8")

def _merge_model_entry(shared_data: dict, entry: dict) -> str:
    """Insert or update model entry. Returns 'added' or 'updated'."""
    # Strip internal _source tag before writing
    clean = {k: v for k, v in entry.items() if not k.startswith("_")}
    models = shared_data.setdefault("models", [])
    for i, m in enumerate(models):
        if m.get("model_name") == clean.get("model_name"):
            models[i] = clean
            return "updated"
    models.append(clean)
    return "added"

# ── copy helper ───────────────────────────────────────────────────────────────

def _fmt_size(b: int) -> str:
    return f"{b/1024/1024:.1f} MB" if b >= 1024 * 1024 else f"{b/1024:.0f} KB"

def _copy_dir(src: Path, dst: Path, dry_run: bool) -> bool:
    if not src.exists():
        print(f"  ⚠️  源目录不存在，跳过：{src.relative_to(_PROJECT_ROOT)}")
        return False
    files = [f for f in src.rglob("*") if f.is_file()]
    size  = sum(f.stat().st_size for f in files)
    tag   = "[dry-run] " if dry_run else ""
    print(f"  {tag}📂 {src.name}/  ({len(files)} 文件, {_fmt_size(size)})")
    if not dry_run:
        if dst.exists():
            shutil.rmtree(dst)
        shutil.copytree(src, dst)
    return True

# ── publish modes ─────────────────────────────────────────────────────────────

def publish_by_model(model_name: str, shared_dir: Path, dry_run: bool):
    local_data, _ = _load_index(_LOCAL_INDEX)
    entry = next((m for m in local_data.get("models", [])
                  if m.get("model_name") == model_name), None)
    if entry is None:
        names = [m.get("model_name") for m in local_data.get("models", [])]
        print(f"❌ 未找到模型：{model_name}")
        print(f"   本地可用模型：{names}")
        sys.exit(1)

    print(f"\n📦 发布模型：{model_name}")
    print(f"   {'[dry-run] ' if dry_run else ''}来源：{_LOCAL_RESULTS}")
    print(f"   {'[dry-run] ' if dry_run else ''}目标：{shared_dir}\n")

    copied = 0

    # 1. 关联实验目录
    for exp_path in entry.get("linked_experiments") or []:
        if exp_path.startswith("results/"):
            rel = exp_path[len("results/"):]
            if _copy_dir(_LOCAL_RESULTS / rel, shared_dir / rel, dry_run):
                copied += 1

    # 2. models/<model_name>/ 目录（EVAL_REPORT.md、model-context.md）
    model_dir = _LOCAL_RESULTS / "models" / model_name
    if model_dir.exists():
        _copy_dir(model_dir, shared_dir / "models" / model_name, dry_run)

    # 3. 更新共享 INDEX.yaml
    shared_index = shared_dir / "models" / "INDEX.yaml"
    shared_data, shared_header = _load_index(shared_index)
    action = _merge_model_entry(shared_data, entry)
    if not dry_run:
        _write_index(shared_index, shared_data, shared_header)
        print(f"\n  ✓ 共享 INDEX.yaml：{action} [{model_name}]")
    else:
        print(f"\n  [dry-run] 将 {action} 共享 INDEX.yaml 中的 [{model_name}] 条目")

    status_icon = "✅" if entry.get("eval_status") == "completed" else "🔄"
    print(f"\n{status_icon} 发布完成：{model_name}  （复制 {copied} 个实验目录）")
    if not dry_run:
        print("   Dashboard 刷新后即可在 [共享] 区域看到该模型")

def publish_dirs(dirs: list, shared_dir: Path, dry_run: bool):
    print(f"\n📦 发布 {len(dirs)} 个目录（不更新 INDEX.yaml）")
    for d in dirs:
        p = Path(d)
        if not p.is_absolute():
            p = _PROJECT_ROOT / p
        # 目标路径：shared_dir / 相对于 _LOCAL_RESULTS 的部分
        try:
            rel = p.relative_to(_LOCAL_RESULTS)
        except ValueError:
            rel = p.name
        _copy_dir(p, shared_dir / rel, dry_run)
    print(f"\n✅ 完成（未更新 INDEX.yaml；如需注册，请使用 --model <name>）")

def list_models():
    data, _ = _load_index(_LOCAL_INDEX)
    models = data.get("models", [])
    if not models:
        print("本地 INDEX.yaml 中暂无模型")
        return
    print(f"\n本地 INDEX.yaml 模型列表（共 {len(models)} 个）：\n")
    for m in models:
        name   = m.get("model_name", "?")
        status = m.get("eval_status", "?")
        date   = m.get("eval_completed_date") or m.get("eval_started_date") or ""
        icon   = {"completed": "✅", "in_progress": "🔄", "pending": "⏳"}.get(status, "❓")
        print(f"  {icon}  {name:<45} {status}  {date}")
    print()

# ── main ──────────────────────────────────────────────────────────────────────

def main():
    parser = argparse.ArgumentParser(
        description="发布本地 results/ 到共享 NFS，让团队 Dashboard 可见",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=__doc__,
    )
    parser.add_argument("dirs", nargs="*",
                        help="要发布的 results/ 子目录路径（不更新 INDEX.yaml）")
    parser.add_argument("--model", "-m",
                        help="按模型名发布（同时更新共享 INDEX.yaml）")
    parser.add_argument("--list", "-l", action="store_true",
                        help="列出本地 INDEX.yaml 中所有模型名")
    parser.add_argument("--dry-run", "-n", action="store_true",
                        help="预览模式，不实际复制或写入")
    args = parser.parse_args()

    if args.list:
        list_models()
        return

    if not args.model and not args.dirs:
        parser.print_help()
        sys.exit(0)

    shared_dir = _get_shared_dir()

    if args.model:
        publish_by_model(args.model, shared_dir, dry_run=args.dry_run)
    else:
        publish_dirs(args.dirs, shared_dir, dry_run=args.dry_run)

if __name__ == "__main__":
    main()
