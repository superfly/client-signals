# Shared client-signals spec

This directory contains shared fixtures used by the language packages:

- `markers.json` is the known agent-marker table.
- `mcp-clients.json` is the MCP client rule table used by opt-in MCP request
  classification.
- `sanitize-fixtures.json` covers self-declared agent sanitization.
- `parent-fixtures.json` covers parent-process bucket classification.
- `header-fixtures.json` covers emitted headers and User-Agent suffixes.
- `operator-fixtures.json` covers the shared process-operator classification.
- `request-metrics.md` defines the server-side request metric contract.
- `request-classification-fixtures.json` covers bounded request classification.
- `mcp-client-fixtures.json` covers MCP client identity and MCP request
  classification.
- `route-fixtures.json` covers route-template labels and prefix filtering.

Language packages may mirror the marker table and the MCP client rule table
in native source for dependency-free runtime behavior, but tests should
compare those mirrors against these files.
