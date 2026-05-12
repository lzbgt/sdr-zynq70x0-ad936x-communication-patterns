#!/usr/bin/env python3
"""Patch a copied Pluto HDL tree with FieldMesh sidecar RTL file references."""

from __future__ import annotations

import argparse
import json
import shutil
from pathlib import Path

import fieldmesh_sidecar_plan as sidecar_plan


MAKE_BEGIN = "# FieldMesh sidecar overlay files: begin"
MAKE_END = "# FieldMesh sidecar overlay files: end"


def rel_rtl_name(rtl_path: str) -> str:
    return f"fieldmesh/{Path(rtl_path).name}"


def patch_system_project(text: str, rel_files: list[str]) -> tuple[str, bool]:
    if all(f'"{rel}"' in text for rel in rel_files):
        return text, False

    lines = text.splitlines()
    marker = '  "$ad_hdl_dir/library/common/ad_iobuf.v"]'
    try:
        idx = lines.index(marker)
    except ValueError as exc:
        raise SystemExit("system_project.tcl: expected ad_iobuf.v list terminator not found") from exc

    new_lines = lines[:idx]
    new_lines.append('  "$ad_hdl_dir/library/common/ad_iobuf.v" \\')
    for rel in rel_files[:-1]:
        new_lines.append(f'  "{rel}" \\')
    new_lines.append(f'  "{rel_files[-1]}"]')
    new_lines.extend(lines[idx + 1 :])
    return "\n".join(new_lines) + "\n", True


def patch_makefile(text: str, rel_files: list[str]) -> tuple[str, bool]:
    if MAKE_BEGIN in text and MAKE_END in text:
        return text, False

    anchor = "LIB_DEPS += axi_ad9361"
    try:
        idx = text.index(anchor)
    except ValueError as exc:
        raise SystemExit("Makefile: expected LIB_DEPS anchor not found") from exc

    block = [MAKE_BEGIN]
    block.extend(f"M_DEPS += {rel}" for rel in rel_files)
    block.append(MAKE_END)
    block.append("")
    patched = text[:idx] + "\n".join(block) + "\n" + text[idx:]
    return patched, True


def load_plan(repo_root: Path, variant_name: str, system_bd: Path) -> dict:
    return sidecar_plan.build_plan(
        [(variant_name, system_bd)],
        check_sidecar=True,
        repo_root=repo_root,
        check_rtl=True,
        check_hp_policy=True,
    )


def apply_patch(repo_root: Path, hdl_tree: Path, variant_name: str, apply: bool) -> dict:
    project_dir = hdl_tree / "projects" / "pluto"
    system_bd = project_dir / "system_bd.tcl"
    system_project = project_dir / "system_project.tcl"
    makefile = project_dir / "Makefile"

    for required in (system_bd, system_project, makefile):
        if not required.is_file():
            raise SystemExit(f"{required}: not found")

    plan = load_plan(repo_root, variant_name, system_bd)
    rel_files = [rel_rtl_name(path) for path in sidecar_plan.REQUIRED_RTL]
    copied_files = []
    for src_rel, dst_rel in zip(sidecar_plan.REQUIRED_RTL, rel_files, strict=True):
        src = repo_root / src_rel
        dst = project_dir / dst_rel
        copied_files.append(str(dst))
        if apply:
            dst.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(src, dst)

    project_text = system_project.read_text()
    patched_project, project_changed = patch_system_project(project_text, rel_files)
    make_text = makefile.read_text()
    patched_make, make_changed = patch_makefile(make_text, rel_files)

    if apply:
        if project_changed:
            system_project.write_text(patched_project)
        if make_changed:
            makefile.write_text(patched_make)

    return {
        "event": "fieldmesh_vivado_overlay_patch",
        "ok": True,
        "applied": apply,
        "variant": variant_name,
        "hdl_tree": str(hdl_tree),
        "system_bd": str(system_bd),
        "system_project_changed": project_changed,
        "makefile_changed": make_changed,
        "copied_rtl_files": copied_files,
        "sidecar_ok": plan["ok"],
    }


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repo-root", type=Path, default=Path.cwd(), help="repository root containing rtl/fieldmesh")
    parser.add_argument("--hdl-tree", type=Path, required=True, help="copied Pluto HDL tree to patch")
    parser.add_argument("--variant-name", default="fieldmesh", help="variant label for checks")
    parser.add_argument("--apply", action="store_true", help="write changes; default is dry-run JSON only")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    result = apply_patch(args.repo_root.resolve(), args.hdl_tree.resolve(), args.variant_name, args.apply)
    print(json.dumps(result, indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
