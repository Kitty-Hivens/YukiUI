"""The display arrangement's geometry, core/functions/arrange.js, run in node.

Switching off the middle one of three displays left a gap that split the
layout, and the page refused it as displays that do not touch. Switching one
on put it at the corner of the whole layout, which could meet its neighbour
at a corner only.
"""

import json
import shutil
import subprocess

import pytest

from bench.bench import SHELL

ARRANGE = SHELL / "core/functions/arrange.js"

pytestmark = pytest.mark.skipif(shutil.which("node") is None, reason="needs node")


def run(script: str):
    source = f"const A = require({json.dumps(str(ARRANGE))});\n" \
             "const screen = (name, x, y) => ({ name, enabled: true, x, y, width: 1920, height: 1080, scale: 1, transform: 0 });\n" \
             f"console.log(JSON.stringify((() => {{ {script} }})()));"
    return json.loads(subprocess.run(["node", "-e", source], capture_output=True, text=True, check=True).stdout)


def test_switching_off_the_middle_display_closes_the_gap():
    result = run('''
        let plan = [screen("A", 0, 0), screen("B", 1920, 0), screen("C", 3840, 0)];
        plan = plan.map(entry => entry.name === "B" ? Object.assign({}, entry, { enabled: false }) : entry);
        const closed = A.closeGap(plan, "B");
        return { c: closed.find(entry => entry.name === "C").x, together: A.isContiguous(closed) };
    ''')
    assert result == {"c": 1920, "together": True}


def test_a_display_switched_on_meets_a_real_edge():
    result = run('''
        const plan = [screen("A", 0, 0), screen("C", 1920, 500), Object.assign(screen("B", 0, 0), { enabled: false })];
        const at = A.placeSwitchedOn(plan, "B");
        const placed = plan.map(entry => entry.name === "B" ? Object.assign({}, entry, { enabled: true, x: at.x, y: at.y }) : entry);
        return { at, together: A.isContiguous(placed) };
    ''')
    assert result == {"at": {"x": 3840, "y": 500}, "together": True}
