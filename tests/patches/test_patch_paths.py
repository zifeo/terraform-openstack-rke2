"""Every key a patch sets must exist in the packaged chart values, otherwise it is a dead override (typo, renamed key)."""

import yaml

from helpers import extract_chart_values

# Keys absent from upstream values.yaml on purpose, with the reason. Empty or null upstream maps accept any child key.
INTENTIONAL_ADDITIONS = {
    "rke2-cilium": {
        # nodeSelector is a free-form label map; upstream only ships kubernetes.io/os
        "operator.nodeSelector.node-role.kubernetes.io/control-plane",
    },
}


def _leaf_paths(node, prefix=()):
    if isinstance(node, dict) and node:
        for key, value in node.items():
            yield from _leaf_paths(value, prefix + (key,))
    else:
        yield prefix


def _is_known(upstream, path) -> bool:
    node = upstream
    for key in path:
        if node is None or node == {}:
            return True
        if not isinstance(node, dict) or key not in node:
            return False
        node = node[key]
    return True


def test_patch_keys_exist_upstream(version, rendered_patches, charts_cache, tmp_path):
    dead = []
    for chart, patch_file in rendered_patches.items():
        values_path, chart_version = extract_chart_values(charts_cache[version] / f"{chart}.yaml", chart, tmp_path)
        upstream = yaml.safe_load(values_path.read_text())
        allowed = INTENTIONAL_ADDITIONS.get(chart, {})
        for path in _leaf_paths(yaml.safe_load(patch_file.read_text())):
            dotted = ".".join(map(str, path))
            if dotted not in allowed and not _is_known(upstream, path):
                dead.append(f"{chart}@{chart_version}: {dotted}")
    assert not dead, "patch keys missing from upstream values.yaml:\n" + "\n".join(dead)
