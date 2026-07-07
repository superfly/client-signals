# client-signals for JavaScript

JavaScript implementation of the shared `client-signals` contract.

## Installation

```sh
npm install @superfly/client-signals
```

Requires Node.js 20 or newer.

## Usage

```js
import { applyHeaders, detectOnce, userAgentSuffix } from "@superfly/client-signals";

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
- `sanitizeInvokedBy(value)` and `classifyParentName(raw)` are exported for
  tests and advanced consumers that need the shared contract helpers.

## Development

```sh
npm test
```
