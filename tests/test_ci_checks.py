"""Golden tests of scripts/ci_checks.py: the repository passes, and each check catches its case."""

from __future__ import annotations

import shutil
import sys
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "scripts"))

import ci_checks  # noqa: E402


@pytest.fixture()
def repo(tmp_path: Path) -> Path:
    dst = tmp_path / "repo"
    shutil.copytree(ROOT, dst, ignore=shutil.ignore_patterns(".git", ".terraform", ".venv", "scratch_schema", "__pycache__"))
    return dst


def test_repository_passes():
    assert ci_checks.run(ROOT) == []


def test_iam_policy_resource_is_refused(repo: Path):
    (repo / "envs" / "dev" / "main.bad.tf").write_text('resource "google_project_iam_binding" "x" {}\n')
    assert any("google_project_iam_binding" in f for f in ci_checks.check_iam_ownership(repo))


def test_table_iam_is_refused(repo: Path):
    (repo / "envs" / "dev" / "main.bad.tf").write_text('resource "google_bigquery_table_iam_member" "x" {}\n')
    assert ci_checks.check_iam_ownership(repo)


def test_dataset_without_ignore_changes_is_refused(repo: Path):
    (repo / "envs" / "dev" / "main.bad.tf").write_text(
        'resource "google_bigquery_dataset" "x" {\n  access {\n    role = "OWNER"\n  }\n}\n'
    )
    findings = ci_checks.check_dataset_access(repo)
    assert any("does not ignore changes" in f for f in findings)


def test_project_readers_is_refused(repo: Path):
    (repo / "envs" / "dev" / "main.bad.tf").write_text('locals {\n  x = { special_group = "projectReaders" }\n}\n')
    assert ci_checks.check_project_readers(repo)


def test_image_by_tag_is_refused(repo: Path):
    (repo / "envs" / "images.json").write_text('{"evaluator": "example/evaluator:latest"}')
    assert ci_checks.check_images(repo)


def test_http_data_source_outside_shim_is_refused(repo: Path):
    (repo / "envs" / "dev" / "main.bad.tf").write_text('data "http" "x" {\n  url = "https://example.com"\n}\n')
    assert ci_checks.check_local_execution(repo)


def test_environment_drift_is_refused(repo: Path):
    shutil.copytree(repo / "envs" / "dev", repo / "envs" / "test")
    (repo / "envs" / "test" / "main.extra.tf").write_text("locals {}\n")
    assert ci_checks.check_root_module_comparison(repo)


def test_identical_environment_passes(repo: Path):
    shutil.copytree(repo / "envs" / "dev", repo / "envs" / "test")
    assert ci_checks.check_root_module_comparison(repo) == []


def test_bad_infotype_level_is_refused(repo: Path):
    (repo / "classification" / "infotype_rules.yaml").write_text(
        "version: 2\nrules:\n  - info_type: EMAIL_ADDRESS\n    level: SECRET\n    rationale: x\n"
    )
    assert ci_checks.check_infotype_rules(repo)


def test_reused_aspect_index_is_refused(repo: Path):
    p = repo / "aspect_types" / "cdmc_aspect_types.yaml"
    p.write_text(p.read_text().replace("shared_index: 2\n", "shared_index: 1\n", 1))
    assert ci_checks.check_aspect_types(repo)


def test_workflow_id_token_is_refused(repo: Path):
    wf = repo / ".github" / "workflows" / "ci.yml"
    wf.write_text(wf.read_text() + "\n# permissions:\n#   id-token: write\n")
    assert ci_checks.check_workflows(repo)
