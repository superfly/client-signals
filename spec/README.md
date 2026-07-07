# Shared client-signals spec

This directory contains shared fixtures used by the language packages:

- `markers.json` is the known agent-marker table.
- `sanitize-fixtures.json` covers self-declared agent sanitization.
- `parent-fixtures.json` covers parent-process bucket classification.
- `header-fixtures.json` covers emitted headers and User-Agent suffixes.

Language packages may mirror the marker table in native source for
dependency-free runtime behavior, but tests should compare that mirror
against these fixtures.
