# client-signals for JavaScript

JavaScript implementation of the shared `client-signals` contract.

## Distribution

This package is not published to npm. Downstream packages consume it by
vendoring this directory and referencing the vendored copy as a local
dependency. The package manifest is marked private to prevent accidental
publication.

Requires Node.js 20 or newer.

## Usage

```js
import { applyHeaders, detectOnce, userAgentSuffix } from "@fly/client-signals";

const signals = detectOnce();
const headers = {};

applyHeaders(headers, signals);
headers["User-Agent"] = `my-cli/1.0 ${userAgentSuffix(signals)}`;
```

Use a custom header prefix:

```js
applyHeaders(headers, signals, "Acme");
```

`applyHeaders` supports plain objects, `Map`, WHATWG `Headers`, and
Node-style objects with `setHeader`.

## API

- `detect()` computes fresh signals.
- `detectOnce()` computes and caches process-wide signals.
- `headersFor(signals, prefix = "Fly")` returns a header object.
- `applyHeaders(target, signals, prefix = "Fly")` writes headers to a
  target.
- `userAgentSuffix(signals)` returns the client-signals User-Agent token.
- `operator(signals)` returns `ci`, `agent`, `interactive`, or `unknown`;
  precedence is in that order.
- `sanitizeInvokedBy(value)` and `classifyParentName(raw)` are exported for
  tests and advanced consumers that need the shared contract helpers.

## Development

```sh
npm test
```
