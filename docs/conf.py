from __future__ import annotations

import sys
from pathlib import Path


PROJECT_ROOT = Path(__file__).resolve().parents[1]
SRC_DIR = PROJECT_ROOT / "src"
sys.path.insert(0, str(SRC_DIR))


project = "wss-py-wrapper"
author = "wss-py-wrapper contributors"

extensions = [
    "sphinx.ext.autodoc",
    "sphinx.ext.viewcode",
]

templates_path = ["_templates"]
exclude_patterns: list[str] = ["_build"]

html_theme = "alabaster"

autodoc_typehints = "description"
