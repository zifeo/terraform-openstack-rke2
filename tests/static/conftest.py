from __future__ import annotations

from typing import Dict

import pytest

from nodes import PROFILES, render_profile, tofu


@pytest.fixture(scope="session")
def renders(tmp_path_factory) -> Dict[str, dict]:
    try:
        tofu("init", "-input=false", "-backend=false")
        state_dir = tmp_path_factory.mktemp("tofu")
        return {name: render_profile(variables, state_dir / f"{name}.tfstate") for name, variables in PROFILES.items()}
    except RuntimeError as err:
        pytest.fail(str(err))
