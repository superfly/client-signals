import assert from "node:assert/strict";
import { mkdtempSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import test from "node:test";
import {
  KNOWN_MARKERS,
  applyHeaders,
  classifyParentName,
  detect,
  detectOnce,
  headersFor,
  isInteractiveFileForTest,
  loadJSONFixture,
  operator,
  resetCachedForTest,
  sanitizeInvokedBy,
  userAgentSuffix,
} from "../src/index.js";

const markers = loadJSONFixture(new URL("../../spec/markers.json", import.meta.url));
const sanitizeFixtures = loadJSONFixture(new URL("../../spec/sanitize-fixtures.json", import.meta.url));
const parentFixtures = loadJSONFixture(new URL("../../spec/parent-fixtures.json", import.meta.url));
const headerFixtures = loadJSONFixture(new URL("../../spec/header-fixtures.json", import.meta.url));
const operatorFixtures = loadJSONFixture(new URL("../../spec/operator-fixtures.json", import.meta.url));

test("known markers match the shared spec", () => {
  assert.deepEqual(KNOWN_MARKERS, markers);
});

test("sanitizeInvokedBy follows shared fixtures", () => {
  for (const fixture of sanitizeFixtures) {
    const [got, ok] = sanitizeInvokedBy(fixture.input);
    assert.equal(ok, fixture.valid, fixture.name);
    assert.equal(got ?? "", fixture.want, fixture.name);
  }
});

test("classifyParentName follows shared fixtures", () => {
  for (const fixture of parentFixtures) {
    assert.equal(classifyParentName(fixture.raw), fixture.want, fixture.raw);
  }
});

test("headersFor and userAgentSuffix follow shared fixtures", () => {
  for (const fixture of headerFixtures) {
    assert.deepEqual(headersFor(fixture.signals, fixture.prefix), fixture.headers, fixture.name);
    assert.equal(userAgentSuffix(fixture.signals), fixture.userAgentSuffix, fixture.name);
  }
});

test("operator follows shared fixtures", () => {
  for (const fixture of operatorFixtures) {
    assert.equal(operator(fixture.signals), fixture.want, fixture.name);
  }
});

test("applyHeaders writes to plain objects and Maps", () => {
  const signals = headerFixtures[0].signals;
  const objectHeaders = {};
  applyHeaders(objectHeaders, signals);
  assert.equal(objectHeaders["Fly-Client-Agent"], "claude-code");

  const mapHeaders = new Map();
  applyHeaders(mapHeaders, signals, "Acme");
  assert.equal(mapHeaders.get("Acme-Client-Agent"), "claude-code");
});

test("detectOnce caches the first detected value", () => {
  withCleanAgentEnv(() => {
    resetCachedForTest();
    process.env.FLY_INVOKED_BY = "cached-tool";
    const first = detectOnce();
    process.env.FLY_INVOKED_BY = "different-tool";
    const second = detectOnce();
    assert.deepEqual(second, first);
    assert.equal(second.agent, "cached-tool");
    resetCachedForTest();
  });
});

test("detect returns finite values", () => {
  const signals = detect();
  assert.equal(typeof signals.interactive, "boolean");
  assert.ok(["node", "python", "shell", "other"].includes(signals.parent));
  assert.equal(typeof signals.agent, "string");
  assert.equal(typeof signals.agentSource, "string");
  assert.equal(typeof signals.ci, "boolean");
});

test("regular files are not interactive", () => {
  const dir = mkdtempSync(join(tmpdir(), "client-signals-"));
  const file = join(dir, "not-a-tty");
  writeFileSync(file, "");
  assert.equal(isInteractiveFileForTest(file), false);
});

function withCleanAgentEnv(fn) {
  const saved = new Map();
  for (const name of ["FLY_INVOKED_BY", "AGENT", ...KNOWN_MARKERS.map((marker) => marker.env)]) {
    saved.set(name, process.env[name]);
    delete process.env[name];
  }
  try {
    fn();
  } finally {
    for (const [name, value] of saved) {
      if (value === undefined) {
        delete process.env[name];
      } else {
        process.env[name] = value;
      }
    }
  }
}
