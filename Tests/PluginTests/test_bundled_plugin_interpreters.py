"""Interpreter compatibility tests for all bundled Python plugins."""

import json
import os
import subprocess
import tempfile
import unittest
from pathlib import Path


PLUGIN_DIR = Path(__file__).parent.parent.parent / "Resources" / "BundledPlugins"
HOMEBREW_PREFIX = os.environ.get("HOMEBREW_PREFIX")
HOMEBREW_PYTHON = Path(HOMEBREW_PREFIX) / "bin/python3" if HOMEBREW_PREFIX else None


def expected_interpreters():
    interpreters = [Path("/usr/bin/python3")]
    if HOMEBREW_PYTHON is not None:
        interpreters.append(HOMEBREW_PYTHON)
    return interpreters


def available_interpreters():
    for interpreter in expected_interpreters():
        if interpreter.exists():
            yield interpreter


def plugin_environment(interpreter: Path, home_dir: Path) -> dict[str, str]:
    env = os.environ.copy()
    env.update({
        "HOME": str(home_dir),
        "PATH": str(home_dir / "bin"),
        "PYTHONIOENCODING": "utf-8",
        "LANG": "en_US.UTF-8",
        "LC_ALL": "en_US.UTF-8",
        "XDG_CACHE_HOME": str(home_dir / ".cache"),
        "XDG_CONFIG_HOME": str(home_dir / ".config"),
    })
    if HOMEBREW_PYTHON is not None and interpreter == HOMEBREW_PYTHON:
        env.update({
            "HOMEBREW_PREFIX": HOMEBREW_PREFIX,
            "HOMEBREW_CELLAR": os.environ.get("HOMEBREW_CELLAR", str(Path(HOMEBREW_PREFIX) / "Cellar")),
            "HOMEBREW_REPOSITORY": os.environ.get("HOMEBREW_REPOSITORY", HOMEBREW_PREFIX),
        })
    return env


class TestBundledPluginInterpreterCompatibility(unittest.TestCase):
    def test_missing_configuration_outputs_json_error(self):
        plugins = sorted(p for p in PLUGIN_DIR.glob("*.py") if not p.name.startswith("_"))
        self.assertTrue(plugins, "Expected bundled plugin scripts")

        interpreters = list(available_interpreters())
        if not interpreters:
            self.skipTest("No configured Python interpreters are available")

        for interpreter in interpreters:
            for plugin in plugins:
                with self.subTest(interpreter=str(interpreter), plugin=plugin.name):
                    with tempfile.TemporaryDirectory() as home:
                        home_dir = Path(home)
                        (home_dir / "bin").mkdir()
                        result = subprocess.run(
                            [str(interpreter), str(plugin)],
                            check=False,
                            capture_output=True,
                            text=True,
                            encoding="utf-8",
                            env=plugin_environment(interpreter, home_dir),
                        )
                    self.assertEqual(result.returncode, 0, result.stderr)
                    output = json.loads(result.stdout)
                    self.assertIn("error", output)
                    self.assertIsInstance(output["error"], str)
                    self.assertNotEqual(output["error"], "")


if __name__ == "__main__":
    unittest.main()
