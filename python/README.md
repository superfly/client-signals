# client-signals for Python

Python implementation of the shared `client-signals` contract.

## Installation

```sh
pip install client-signals
```

Import as `client_signals`.

Requires Python 3.9 or newer.

## Usage

```python
import client_signals

signals = client_signals.detect_once()
headers = {}

client_signals.apply_headers(headers, signals)
headers["User-Agent"] = f"my-cli/1.0 {client_signals.user_agent_suffix(signals)}"
```

Use a custom header prefix:

```python
client_signals.apply_headers(headers, signals, prefix="Acme")
```

## API

- `detect()` computes fresh signals.
- `detect_once()` computes and caches process-wide signals.
- `headers_for(signals, prefix="Fly")` returns a header dictionary.
- `apply_headers(target, signals, prefix="Fly")` updates a mutable header
  mapping.
- `user_agent_suffix(signals)` returns the client-signals User-Agent token.
- `operator(signals)` returns `ci`, `agent`, `interactive`, or `unknown`;
  precedence is in that order.
- `Signals` is the dataclass returned by detection.
- `sanitize_invoked_by(value)` and `classify_parent_name(raw)` are exposed
  for tests and advanced consumers that need the shared contract helpers.

## Development

```sh
python3 -m unittest
```
