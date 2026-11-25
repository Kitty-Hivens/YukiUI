"""The helper that changes the power saving of the PCI Express links and keeps it.

Built here and run as the person, which takes its files from the environment,
so nothing of the system is touched.
"""

import os
import subprocess

import pytest

from bench.bench import SHELL

REPO = SHELL.parents[3]
OFFERED = "default [performance] powersave powersupersave\n"


@pytest.fixture(scope="module")
def helper(tmp_path_factory):
    out = tmp_path_factory.mktemp("pcie") / "yuki-pcie"
    subprocess.run(["make", "-s", "-C", str(REPO / "helpers/pcie"), f"OUT={out}"], check=True)
    return out


@pytest.fixture
def files(tmp_path):
    policy, conf = tmp_path / "policy", tmp_path / "tmpfiles" / "yuki-pcie.conf"
    policy.write_text(OFFERED)
    return policy, conf


def run(helper, files, *args):
    return subprocess.run([str(helper), *args], capture_output=True, text=True,
                          env=dict(os.environ, YUKI_PCIE_POLICY=str(files[0]), YUKI_PCIE_CONF=str(files[1])))


def test_it_is_set_at_once_and_kept(helper, files):
    policy, conf = files
    done = run(helper, files, "set", "powersave")
    assert done.returncode == 0, done.stderr
    assert policy.read_text() == "powersave"
    assert conf.read_text().splitlines()[-1] == "w /sys/module/pcie_aspm/parameters/policy - - - - powersave"


def test_the_default_is_not_kept(helper, files):
    policy, conf = files
    run(helper, files, "set", "powersave")
    policy.write_text(OFFERED)
    assert run(helper, files, "set", "default").returncode == 0
    assert not conf.exists()


def test_what_the_kernel_does_not_offer_changes_nothing(helper, files):
    policy, conf = files
    policy.write_text("default [performance]\n")
    done = run(helper, files, "set", "powersave")
    assert done.returncode == 1 and "does not offer" in done.stderr
    assert policy.read_text() == "default [performance]\n" and not conf.exists()


@pytest.mark.parametrize("args", [("set", "performance; rm -rf /"), ("set", "../../etc"), ("set",), ("get", "default"), ()])
def test_nothing_but_the_four_names_is_taken(helper, files, args):
    assert run(helper, files, *args).returncode == 2
    assert files[0].read_text() == OFFERED and not files[1].exists()
