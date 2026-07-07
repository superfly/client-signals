# AGENTS.md

JavaScript-specific notes for agents working in `javascript/`.

## Package

This directory is the npm package `@superfly/client-signals`.

Runtime target: Node.js 20 or newer.

Key files:

- `src/index.js` — runtime implementation and exported API.
- `test/index.test.js` — Node test suite, including shared fixture checks.
- `package.json` — package metadata and scripts.

## Constraints

- No runtime dependencies.
- Keep the package ESM-only unless the user explicitly asks otherwise.
- Do not shell out for parent-process lookup.
- `detectOnce()` must cache the first detected value.
- Keep `KNOWN_MARKERS` aligned with `../spec/markers.json`.

## Commands

```sh
npm test
```
