"""Repository checks of ci-checks (design §6.3) that no off-the-shelf tool performs.

Deterministic, stdlib plus PyYAML and jsonschema. Each check returns a list of findings; any
finding fails the job. Run: uv run python scripts/ci_checks.py [repo_root]
"""

from __future__ import annotations

import json
import re
import sys
from pathlib import Path

import jsonschema
import yaml

PROVIDER_PINS = {
    "registry.terraform.io/hashicorp/google": "8.10.0",
}
DIGEST_RE = re.compile(r"@sha256:[0-9a-f]{64}$")


def tf_files(root: Path) -> list[Path]:
    return sorted(p for p in root.rglob("*.tf") if ".terraform" not in p.parts and "scratch_schema" not in p.parts)


def root_modules(root: Path) -> list[Path]:
    """Directories with a backend.tf: the stacks of this repository."""
    return sorted(p.parent for p in root.rglob("backend.tf") if ".terraform" not in p.parts)


def strip_comments(text: str) -> str:
    text = re.sub(r"/\*.*?\*/", "", text, flags=re.S)
    return "\n".join(re.sub(r"(^|\s)(#|//).*$", "", line) for line in text.splitlines())


def check_root_module_comparison(root: Path) -> list[str]:
    """The .tf files of one stack are identical across environments and across tiers."""
    findings = []
    for group in ("envs", "tiers"):
        base = root / group
        if not base.is_dir():
            continue
        dirs = [d for d in sorted(base.iterdir()) if d.is_dir() and (d / "backend.tf").exists()]
        if len(dirs) < 2:
            continue
        ref = dirs[0]
        ref_files = {p.name: p.read_text() for p in ref.glob("*.tf")}
        for other in dirs[1:]:
            other_files = {p.name: p.read_text() for p in other.glob("*.tf")}
            if ref_files.keys() != other_files.keys():
                findings.append(f"root-module comparison: {ref} and {other} declare different .tf files")
                continue
            for name, text in ref_files.items():
                if other_files[name] != text:
                    findings.append(f"root-module comparison: {other / name} differs from {ref / name}")
    return findings


def check_project_readers(root: Path) -> list[str]:
    findings = []
    for p in tf_files(root):
        if re.search(r'special_group\s*=\s*"projectReaders"', strip_comments(p.read_text())):
            findings.append(f"projectReaders: {p} declares the projectReaders special group (VA-90)")
    return findings


FORBIDDEN_RESOURCE = re.compile(
    r'resource\s+"(google_[a-z0-9_]*_iam_policy|google_[a-z0-9_]*_iam_binding|'
    r'google_bigquery_dataset_iam_[a-z]+|google_bigquery_table_iam_[a-z]+|'
    r'google_cloud_identity_group_membership)"'
)


def check_iam_ownership(root: Path) -> list[str]:
    findings = []
    for p in tf_files(root):
        for m in FORBIDDEN_RESOURCE.finditer(strip_comments(p.read_text())):
            findings.append(f"IAM ownership: {p} declares {m.group(1)} (design §6.15.3)")
    return findings


def resource_blocks(text: str, rtype: str) -> list[tuple[str, str]]:
    """(name, body) of every `resource "<rtype>" "<name>" { ... }` block, brace-matched."""
    out = []
    for m in re.finditer(rf'resource\s+"{rtype}"\s+"([^"]+)"\s*\{{', text):
        depth, i = 1, m.end()
        while depth and i < len(text):
            depth += {"{": 1, "}": -1}.get(text[i], 0)
            i += 1
        out.append((m.group(1), text[m.end() : i - 1]))
    return out


def check_dataset_access(root: Path) -> list[str]:
    findings = []
    for p in tf_files(root):
        text = strip_comments(p.read_text())
        for name, body in resource_blocks(text, "google_bigquery_dataset"):
            if not re.search(r"^\s*access\s*\{", body, flags=re.M):
                findings.append(f"dataset access: {p} google_bigquery_dataset.{name} has no explicit access list")
            if not re.search(r"ignore_changes\s*=\s*\[[^\]]*\baccess\b", body):
                findings.append(f"dataset access: {p} google_bigquery_dataset.{name} does not ignore changes to access")
    return findings


def check_local_execution(root: Path) -> list[str]:
    findings = []
    pattern = re.compile(r'provisioner\s+"local-exec"|data\s+"external"|data\s+"http"')
    for p in tf_files(root):
        if "data_domain_shim" in p.parts:
            continue
        if pattern.search(strip_comments(p.read_text())):
            findings.append(f"local execution: {p} uses local-exec, external or http outside data_domain_shim")
    return findings


def check_images(root: Path) -> list[str]:
    findings = []
    images = root / "envs" / "images.json"
    if images.exists():
        for key, ref in json.loads(images.read_text()).items():
            if key.startswith("_"):
                continue
            if not DIGEST_RE.search(ref):
                findings.append(f"image reference: envs/images.json {key} is not referenced by @sha256: digest")
    for p in tf_files(root):
        for m in re.finditer(r'^\s*image\s*=\s*"([^"]+)"', strip_comments(p.read_text()), flags=re.M):
            if not DIGEST_RE.search(m.group(1)):
                findings.append(f"image reference: {p} declares image {m.group(1)} by tag")
    return findings


def check_lock_files(root: Path) -> list[str]:
    findings = []
    for module in root_modules(root):
        lock = module / ".terraform.lock.hcl"
        if not lock.exists():
            findings.append(f"lock file: {module} has no committed .terraform.lock.hcl")
            continue
        text = lock.read_text()
        for provider, version in PROVIDER_PINS.items():
            m = re.search(rf'provider\s+"{re.escape(provider)}"\s*\{{\s*version\s*=\s*"([^"]+)"', text)
            if m and m.group(1) != version:
                findings.append(f"lock file: {lock} pins {provider} {m.group(1)}, expected {version}")
        for tf in module.glob("*.tf"):
            body = strip_comments(tf.read_text())
            for m in re.finditer(r'source\s*=\s*"hashicorp/google(?:-beta)?"\s*version\s*=\s*"([^"]+)"', body):
                # Design §6.11 (OD-4): constraint ~> 8.10; the lock file fixes the exact version.
                if m.group(1) != "~> 8.10":
                    findings.append(f"provider pin: {tf} pins google {m.group(1)}, expected ~> 8.10")
    return findings


def check_workflows(root: Path) -> list[str]:
    findings = []
    wf_dir = root / ".github" / "workflows"
    for wf in sorted(wf_dir.glob("*.y*ml")) if wf_dir.is_dir() else []:
        text = wf.read_text()
        if re.search(r"id-token\s*:\s*write", text):
            findings.append(f"workflow: {wf} requests id-token: write")
        if "google-github-actions/auth" in text:
            findings.append(f"workflow: {wf} uses a Google Cloud authentication action")
        for m in re.finditer(r"uses:\s*([^\s@]+)@([^\s]+)", text):
            if not re.fullmatch(r"[0-9a-f]{40}", m.group(2)):
                findings.append(f"workflow: {wf} uses {m.group(1)} by tag, not by commit SHA")
    return findings


def check_infotype_rules(root: Path) -> list[str]:
    rules = root / "classification" / "infotype_rules.yaml"
    schema = root / "schemas" / "infotype_rules.schema.json"
    if not rules.exists():
        return ["schema: classification/infotype_rules.yaml is missing"]
    validator = jsonschema.Draft202012Validator(json.loads(schema.read_text()))
    data = yaml.safe_load(rules.read_text())
    findings = [f"schema: infotype_rules.yaml: {e.message}" for e in validator.iter_errors(data)]
    if not findings:
        seen = [r["info_type"] for r in data["rules"]]
        dupes = sorted({t for t in seen if seen.count(t) > 1})
        if dupes:
            findings.append(f"schema: infotype_rules.yaml has duplicate info_type rules: {dupes}")
    return findings


def check_aspect_types(root: Path) -> list[str]:
    """Field and enum indexes are unique and numbered 1..n in every record (design §5.11)."""
    findings = []
    src = yaml.safe_load((root / "aspect_types" / "cdmc_aspect_types.yaml").read_text())

    def walk(type_id: str, path: str, record: dict) -> None:
        fields = record.get("recordFields", [])
        indexes = [f.get("index") for f in fields]
        if sorted(i for i in indexes if isinstance(i, int)) != list(range(1, len(fields) + 1)):
            findings.append(f"aspect types: {type_id}{path} field indexes are not unique 1..{len(fields)}")
        for f in fields:
            values = [v.get("index") for v in f.get("enumValues", [])]
            if values and sorted(values) != list(range(1, len(values) + 1)):
                findings.append(f"aspect types: {type_id}{path}.{f['name']} enum indexes are not 1..{len(values)}")
            if f.get("type") == "record":
                walk(type_id, f"{path}.{f['name']}", f)

    for type_id, t in src["aspect_types"].items():
        walk(type_id, "", t["metadataTemplate"])
    return findings


CHECKS = [
    check_root_module_comparison,
    check_project_readers,
    check_iam_ownership,
    check_dataset_access,
    check_local_execution,
    check_images,
    check_lock_files,
    check_workflows,
    check_infotype_rules,
    check_aspect_types,
]


def run(root: Path) -> list[str]:
    findings: list[str] = []
    for check in CHECKS:
        findings.extend(check(root))
    return findings


def main(argv: list[str]) -> int:
    root = Path(argv[1]) if len(argv) > 1 else Path(__file__).resolve().parent.parent
    findings = run(root)
    for f in findings:
        print(f"FAIL {f}")
    print(f"{len(CHECKS)} checks, {len(findings)} findings")
    return 1 if findings else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
