"""cloud-init schema on every rendered user_data and shellcheck on every script a node runs."""

from nodes import NODE_DIR, PROFILES, write_files


def test_cloud_init_schema(renders, tools, tmp_path):
    for name in PROFILES:
        (tmp_path / f"{name}.yaml").write_text(renders[name]["rendered"])
    script = "for f in /user-data/*.yaml; do echo \"== $f\"; cloud-init schema --config-file \"$f\"; done"
    tools(script, {tmp_path: "/user-data"})


def test_shellcheck(renders, tools, tmp_path):
    scripts = {}
    for name in PROFILES:
        for path, content in write_files(renders[name]["rendered"]).items():
            if path.endswith(".sh"):
                scripts[path.rsplit("/", 1)[-1]] = content
    assert {"install-or-upgrade-rke2.sh", "cloud-init-wait.sh", "setup-gpu.sh"} <= scripts.keys()
    for name, content in scripts.items():
        (tmp_path / name).write_text(content)
    tools("shellcheck --severity=warning /embedded/*.sh /node/*.sh", {tmp_path: "/embedded", NODE_DIR: "/node"})
