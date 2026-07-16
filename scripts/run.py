#!/usr/bin/env python3
# /// script
# requires-python = ">=3.10"
# dependencies = [
#     "python-hcl2>=4.3.0",
#     "ruamel.yaml",
# ]
# ///
"""Boot a built image with QEMU.

Usage:
    run.py <template> [--rebuild] [--no-build] [--writable] [--serial] [-- <qemu args>...]

Resolves the QEMU configuration straight out of the template's ``template.pkr.hcl``
(the same ``source "qemu"`` block Packer builds with), so a built image boots with
the machine type, firmware, NIC and disk interface it was installed against.

If the image has not been built yet it is built first (Packer). Pass ``--rebuild``
to force a rebuild even when a local image already exists, or ``--no-build`` to
fail instead of building.

By default the disk is opened read-only via ``-snapshot`` so running never mutates
the golden image the tests rely on. Pass ``--writable`` to persist changes.

Anything after a literal ``--`` is forwarded verbatim to QEMU.

A template's ``image.yml`` may carry a ``run:`` block to override or extend the
derived configuration (handy for the odd template whose QEMU setup can't be
reconstructed generically, e.g. ESXi). Recognised keys:

    run:
      qemu_binary: qemu-system-x86_64
      machine_type: q35
      cpu_model: host
      cpus: 2
      memory: 4096
      disk_interface: virtio
      net_device: virtio-net
      efi_boot: true
      efi_firmware_code: /usr/share/OVMF/OVMF_CODE_4M.fd
      efi_firmware_vars: /usr/share/OVMF/OVMF_VARS_4M.fd
      accel: kvm:hvf:whpx:tcg
      display: default
      args: ["-device", "..."]   # extra raw QEMU args
"""

import argparse
import re
import shutil
import socket
import subprocess
import sys
import tempfile
from pathlib import Path

import hcl2
from ruamel.yaml import YAML

REPO_ROOT = Path(__file__).resolve().parent.parent
TEMPLATES_ROOT = REPO_ROOT / "templates"

DEFAULT_ACCEL = "kvm:hvf:whpx:tcg"


def _unquote(value: object) -> object:
    """Strip the surrounding quotes python-hcl2 keeps on string literals."""
    if isinstance(value, str) and len(value) >= 2 and value[0] == '"' and value[-1] == '"':
        return value[1:-1]
    return value


def _resolve_expr(expr: str, variables: dict[str, str], template_dir: Path) -> str | None:
    """Resolve a single HCL expression, or None if we don't understand it."""
    expr = expr.strip()
    if expr == "path.cwd":
        return str(REPO_ROOT)
    if expr == "path.root":
        return str(template_dir)
    if expr.startswith("var."):
        return variables.get(expr[len("var.") :])
    match = re.fullmatch(r"basename\((.+)\)", expr)
    if match:
        inner = _resolve_expr(match.group(1), variables, template_dir)
        if inner is not None:
            return Path(inner).name
    match = re.fullmatch(r"dirname\((.+)\)", expr)
    if match:
        inner = _resolve_expr(match.group(1), variables, template_dir)
        if inner is not None:
            return str(Path(inner).parent)
    return None


def _resolve(value: object, variables: dict[str, str], template_dir: Path) -> object:
    """Unquote a value and expand the ``${...}`` interpolations we care about."""
    value = _unquote(value)
    if not isinstance(value, str):
        return value

    def repl(match: re.Match) -> str:
        resolved = _resolve_expr(match.group(1), variables, template_dir)
        return str(resolved) if resolved is not None else match.group(0)

    return re.sub(r"\$\{([^}]*)\}", repl, value)


def _parse_template(template: str) -> dict:
    """Return the resolved ``source "qemu"`` config for a template, or {} if none."""
    template_dir = TEMPLATES_ROOT / template
    hcl_path = template_dir / "template.pkr.hcl"
    if not hcl_path.is_file():
        raise SystemExit(f"no template.pkr.hcl for {template!r}")

    with hcl_path.open() as fh:
        data = hcl2.load(fh)

    variables: dict[str, str] = {}
    for block in data.get("variable", []):
        for name, body in block.items():
            name = _unquote(name)
            variables[name] = _resolve(body.get("default"), {}, template_dir)

    raw_cfg: dict | None = None
    for block in data.get("source", []):
        for kind, named in block.items():
            if _unquote(kind) != "qemu":
                continue
            for key, body in named.items():
                if key == "__is_block__":
                    continue
                raw_cfg = body
    if raw_cfg is None:
        return {}

    cfg: dict = {}
    for key, value in raw_cfg.items():
        if key in ("__is_block__", "qemuargs"):
            continue
        cfg[key] = _resolve(value, variables, template_dir)

    qemuargs = [[_resolve(item, variables, template_dir) for item in entry] for entry in raw_cfg.get("qemuargs", [])]
    cfg["qemuargs"] = qemuargs
    return cfg


def _load_run_overrides(template: str) -> dict:
    sidecar = TEMPLATES_ROOT / template / "image.yml"
    if not sidecar.is_file():
        return {}
    meta = YAML(typ="safe").load(sidecar) or {}
    return meta.get("run") or {}


def _disk_path(cfg: dict) -> Path | None:
    """The built disk path, taken straight from the template's output config.

    Uses the resolved ``output_directory`` + ``vm_name`` from the QEMU source (or a
    ``run:`` override) so the path always matches what Packer wrote. Returns None if
    the template doesn't declare both.
    """
    out_dir = cfg.get("output_directory")
    vm_name = cfg.get("vm_name")
    if out_dir and vm_name:
        return Path(out_dir) / vm_name
    return None


def _build(template: str) -> None:
    print(f"building {template} ...", file=sys.stderr)
    subprocess.run(["just", "build", template], cwd=REPO_ROOT, check=True)


def _accel(cfg: dict) -> str:
    for entry in cfg.get("qemuargs", []):
        if len(entry) == 2 and entry[0] == "-machine":
            match = re.search(r"accel=([^\s,]+)", entry[1])
            if match:
                return match.group(1)
    return DEFAULT_ACCEL


def _pflash_vars(template: str, source_vars: Path | None) -> Path:
    """Provide a per-run, writable EFI vars store, leaving the golden copy intact."""
    tmp = Path(tempfile.mkdtemp(prefix=f"qemu-vars-{template.split('/')[-1]}-")) / "efivars.fd"
    if source_vars and source_vars.is_file():
        shutil.copyfile(source_vars, tmp)
    else:
        raise SystemExit("no EFI vars store available")
    return tmp


def _carry_qemuargs(cfg: dict, disk: Path) -> tuple[list[str], bool, bool]:
    """Pick the template's own ``qemuargs`` to carry over to a run.

    Everything is carried verbatim except the install ISO (a cdrom drive), ``-serial``
    (we manage the console) and ``-machine`` (we reconstruct it with the accelerator).
    A ``-drive`` that points at the built disk image is carried over and reported so
    the caller skips its own auto-generated disk -- this preserves bespoke setups like
    ESXi's AHCI chain. Any ``if=pflash`` drive is dropped and reported instead, so the
    caller can override it with its own per-run EFI vars store (protecting the golden
    copy).

    Networking is dropped too: a template may override ``-netdev``/``-device`` to shape
    the *build* network (e.g. ``restrict=on`` to isolate the guest, or a Packer
    ``hostfwd=tcp::{{ .SSHHostPort }}-:22`` SSH forward). Those are build-only.
    The caller supplies its own plain user networking instead.

    Returns ``(carried_args, has_disk, has_pflash)``.
    """
    carried: list[str] = []
    has_disk = False
    has_pflash = False
    disk_str = str(disk)
    for entry in cfg.get("qemuargs", []):
        if not entry:
            continue
        flag = entry[0]
        value = entry[1] if len(entry) > 1 else ""
        if flag in ("-serial", "-machine"):
            continue
        if flag == "-netdev":
            continue  # build-time network backend -- caller adds its own
        if flag == "-device" and "netdev=" in value:
            continue  # NIC bound to the dropped netdev -- caller adds its own
        if flag == "-drive":
            if "media=cdrom" in value:
                continue  # install ISO -- not needed once built
            if "if=pflash" in value:
                has_pflash = True
                continue  # overridden with our own pflash below
            if disk_str in value:
                has_disk = True
        carried += entry
    return carried, has_disk, has_pflash


def build_command(
    template: str,
    disk: Path,
    cfg: dict,
    *,
    snapshot: bool,
    serial: bool,
    forwards: list[tuple[int, int]],
    extra: list[str],
) -> list[str]:
    binary = cfg.get("qemu_binary") or "qemu-system-x86_64"

    machine_type = cfg.get("machine_type") or "pc"
    cmd = [binary, "-machine", f"type={machine_type},accel={_accel(cfg)}"]
    cmd += ["-cpu", str(cfg.get("cpu_model") or "host")]
    cmd += ["-smp", str(cfg.get("cpus") or 2)]
    cmd += ["-m", str(cfg.get("memory") or 2048)]

    carried, has_disk, has_pflash = _carry_qemuargs(cfg, disk)

    build_dir = disk.parent
    if cfg.get("efi_boot") or has_pflash:
        code = cfg.get("efi_firmware_code")
        if not code:
            raise SystemExit(f"{template}: EFI boot needs efi_firmware_code")
        golden_vars = build_dir / "efivars.fd"
        source_vars = golden_vars if golden_vars.is_file() else cfg.get("efi_firmware_vars")
        source_vars = Path(source_vars) if source_vars else None
        vars_store = _pflash_vars(template, source_vars)
        cmd += ["-drive", f"if=pflash,format=raw,unit=0,readonly=on,file={code}"]
        cmd += ["-drive", f"if=pflash,format=raw,unit=1,file={vars_store}"]

    if not has_disk:
        disk_interface = cfg.get("disk_interface") or "virtio"
        fmt = cfg.get("format") or "qcow2"
        cmd += ["-drive", f"file={disk},if={disk_interface},format={fmt},discard=unmap,detect-zeroes=on"]

    net_device = cfg.get("net_device") or "virtio-net"
    netdev = "user,id=net0"
    for host_port, guest_port in forwards:
        netdev += f",hostfwd=tcp::{host_port}-:{guest_port}"
    cmd += ["-netdev", netdev, "-device", f"{net_device},netdev=net0"]

    cmd += carried

    if snapshot:
        cmd += ["-snapshot"]

    if serial:
        cmd += ["-nographic"]
    else:
        cmd += ["-display", str(cfg.get("display") or "default")]

    cmd += list(cfg.get("args") or [])
    cmd += extra
    return cmd


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("template", help="e.g. pinned/debian-12")
    parser.add_argument("--rebuild", action="store_true", help="rebuild even if a local image exists")
    parser.add_argument("--no-build", action="store_true", help="fail instead of building a missing image")
    parser.add_argument("--writable", action="store_true", help="persist disk changes (disables -snapshot)")
    parser.add_argument("--serial", action="store_true", help="boot headless on the serial console (-nographic)")
    parser.add_argument(
        "--forward",
        metavar="HOST:GUEST",
        action="append",
        default=[],
        help="forward HOST port to GUEST port (may be repeated)",
    )
    parser.add_argument("--dry-run", action="store_true", help="print the QEMU command without running it")
    parser.add_argument(
        "qemu_args",
        nargs="*",
        help="extra args forwarded to QEMU; put them after a literal -- to avoid clashing with run.py flags",
    )
    args, unknown = parser.parse_known_args()
    extra = [*args.qemu_args, *unknown]
    extra = [a for a in extra if a != "--"]

    cfg = _parse_template(args.template)
    cfg.update(_load_run_overrides(args.template))
    if not cfg:
        raise SystemExit(
            f"{args.template}: no QEMU source in template.pkr.hcl; add a run: block to image.yml to run it"
        )

    disk = _disk_path(cfg)
    if disk is None:
        raise SystemExit(
            f"{args.template}: template declares no output_directory + vm_name; set them in a run: block to run it"
        )

    if not disk.exists() or args.rebuild:
        if args.no_build:
            raise SystemExit(f"no local image at {disk} (and --no-build given)")
        _build(args.template)

    if not disk.exists():
        raise SystemExit(f"no image at {disk} after build")

    with socket.socket() as s:
        s.bind(("127.0.0.1", 0))
        ssh_port = s.getsockname()[1]
    print(f"SSH port: {ssh_port}", file=sys.stderr)

    forwards: list[tuple[int, int]] = [(ssh_port, 22)]
    for spec in args.forward:
        try:
            host_str, guest_str = spec.split(":")
            forwards.append((int(host_str), int(guest_str)))
        except (ValueError, TypeError):  # noqa: PERF203
            raise SystemExit(f"invalid --forward value {spec!r}: expected HOST:GUEST")

    cmd = build_command(
        args.template,
        disk,
        cfg,
        snapshot=not args.writable,
        serial=args.serial,
        forwards=forwards,
        extra=extra,
    )

    print(" ".join(cmd), file=sys.stderr)
    if args.dry_run:
        return

    subprocess.run(cmd, cwd=REPO_ROOT, check=True)


if __name__ == "__main__":
    main()
