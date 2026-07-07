# AGENTS.md

Python-specific notes for agents working in `python/`.

## Package

This directory is the PyPI package `client-signals`, imported as
`client_signals`.

Runtime target: Python 3.9 or newer.

Key files:

- `client_signals/core.py` — runtime implementation and exported helpers.
- `client_signals/__init__.py` — public exports.
- `test_client_signals.py` — unittest suite, including shared fixture
  checks.
- `pyproject.toml` — package metadata.

## Constraints

- No runtime dependencies.
- Do not shell out for parent-process lookup.
- `detect_once()` must cache the first detected value.
- Keep `KNOWN_MARKERS` aligned with `../spec/markers.json`.

## Commands

```sh
python3 -m unittest
```
