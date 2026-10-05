"""Runs the real node/customize-chart.sh, as cloud-init does on every server, against the packaged rke2 charts."""

import shutil
from pathlib import Path

import yaml

from helpers import ROOT, chart_archive, extract_chart_values, merge_patch


def _helmchart_without_content(chart_file: Path) -> dict:
    doc = yaml.safe_load(chart_file.read_text())
    doc["spec"].pop("chartContent")
    return doc


def test_customize_chart(version, rendered_patches, charts_cache, tools, tmp_path):
    charts = sorted(rendered_patches)
    for run_dir in ("orig", "a", "b", "again", "patches"):
        (tmp_path / run_dir).mkdir()
    for chart in charts:
        shutil.copy(charts_cache[version] / f"{chart}.yaml", tmp_path / "orig" / f"{chart}.yaml")
        shutil.copy(rendered_patches[chart], tmp_path / "patches" / f"{chart}.yaml")

    # b runs after a full second so any timestamp leaking into the archive changes its bytes
    tools(
        f"""
        cd /w
        for c in {' '.join(charts)}; do cp orig/$c.yaml a/; /node/customize-chart.sh a/$c.yaml patches/$c.yaml; done
        sleep 1.1
        for c in {' '.join(charts)}; do cp orig/$c.yaml b/; /node/customize-chart.sh b/$c.yaml patches/$c.yaml; done
        for c in {' '.join(charts)}; do cp a/$c.yaml again/; /node/customize-chart.sh again/$c.yaml patches/$c.yaml; done
        """,
        {tmp_path: "/w", ROOT / "node": "/node"},
    )

    for chart in charts:
        orig, first = tmp_path / "orig" / f"{chart}.yaml", tmp_path / "a" / f"{chart}.yaml"

        assert first.read_bytes() == (tmp_path / "b" / f"{chart}.yaml").read_bytes(), (
            f"{chart}@{version}: two runs produced different bytes; servers would overwrite each other's HelmChart"
        )
        assert first.read_bytes() == (tmp_path / "again" / f"{chart}.yaml").read_bytes(), (
            f"{chart}@{version}: patching an already patched chart changed it; rke2 recopies data charts on start"
        )

        values_path, _ = extract_chart_values(orig, chart, tmp_path / "orig")
        expected = tmp_path / f"{chart}.expected.yaml"
        merge_patch(values_path, rendered_patches[chart], expected)
        before, after = chart_archive(orig), chart_archive(first)
        values_member = f"{chart}/values.yaml"
        assert yaml.safe_load(after[values_member]) == yaml.safe_load(expected.read_text()), (
            f"{chart}@{version}: values.yaml shipped to nodes differs from the merge the snapshots are built from"
        )

        before.pop(values_member)
        after.pop(values_member)
        assert after == before, f"{chart}@{version}: files other than values.yaml changed in the chart archive"
        assert _helmchart_without_content(first) == _helmchart_without_content(orig), (
            f"{chart}@{version}: HelmChart fields other than chartContent changed"
        )
