# AGENTS.md

Ruby-specific notes for agents working in `ruby/`.

## Package

This directory is the `client_signals` gem. It is not published to RubyGems;
consumers source it from git with `glob: "ruby/*.gemspec"`, the way
`javascript/` is `"private": true` and consumed without npm. If that changes,
add a publish workflow alongside `publish-python.yml` and stamp the version from
the tag, because `lib/client_signals/version.rb` ships a `0.0.0` placeholder.

Runtime target: Ruby 3.0 or newer.

Key files:

- `lib/client_signals.rb`: client-side detection, the `Signals` value, headers
  and User-Agent suffix, and the mirrored `KNOWN_MARKERS` table.
- `lib/client_signals/request.rb`: server-side classification and route
  selection, implementing `../spec/request-metrics.md`.
- `test/`: minitest suite, driven by the shared fixtures in `../spec/`.
- `client_signals.gemspec`: package metadata.

## Constraints

- No runtime dependencies. Standard library only, and no C extensions.
- Do not shell out for parent-process lookup. `/proc/<ppid>/comm` or nothing;
  platforms without `/proc` bucket as `other` on purpose.
- `ClientSignals.detect_once` must cache the first detected value.
- Keep `KNOWN_MARKERS` aligned with `../spec/markers.json`. The spec-contract
  test compares the mirror field by field, so a drifted copy fails loudly.
- Only bounded values leave `ClientSignals::Request`. A caller-supplied agent
  name becomes `other` unless the marker table already knows it, and a raw
  request path is never returned as a route label.

## Commands

```sh
rake test
```

Or without rake:

```sh
ruby -Ilib -Itest -e 'Dir["test/**/*_test.rb"].each { |f| require File.expand_path(f) }'
```
