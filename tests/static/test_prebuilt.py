"""A prebuilt image already carries the packages: its nodes drop the package part of the user_data, and only that part."""

import pytest
import yaml

PACKAGE_KEYS = {"package_update", "package_upgrade", "package_reboot_if_required", "packages"}


@pytest.mark.parametrize("stock, prebuilt", [("server-bootstrap", "server-prebuilt"), ("agent", "agent-prebuilt")])
def test_prebuilt_only_drops_the_package_part(renders, stock, prebuilt):
    full = yaml.safe_load(renders[stock]["rendered"])
    launch = yaml.safe_load(renders[prebuilt]["rendered"])
    assert PACKAGE_KEYS <= full.keys()
    assert not PACKAGE_KEYS & launch.keys()
    # each render makes its own host key
    assert {k: v for k, v in full.items() if k not in PACKAGE_KEYS | {"ssh_keys"}} == {
        k: v for k, v in launch.items() if k != "ssh_keys"
    }
