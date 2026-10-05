"""Every server applies its own copy of the auto-deploy manifests to the same objects.

Any per-server difference (node IP, bootstrap flag, timestamps) makes servers overwrite each
other's HelmChart on every deploy cycle, which triggers a helm upgrade each time.
"""

from nodes import write_files

SHARED_PREFIXES = ("/opt/rke2/manifests/", "/usr/local/bin/customize-chart")


def _shared(rendered: str) -> dict:
    return {p: c for p, c in write_files(rendered).items() if p.startswith(SHARED_PREFIXES)}


def test_servers_ship_identical_manifests(renders):
    bootstrap = _shared(renders["server-bootstrap"]["rendered"])
    join = _shared(renders["server-join"]["rendered"])
    assert bootstrap, "no shared files found in server user_data"
    assert bootstrap.keys() == join.keys()
    differing = sorted(p for p in bootstrap if bootstrap[p] != join[p])
    assert not differing, f"files differ between servers: {differing}"
