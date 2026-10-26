import test from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { Script } from "node:vm";

const read = (name) => readFileSync(new URL("../" + name, import.meta.url), "utf8");
const index = read("index.html");
const letters = read("letters.html");
const server = read("server.js");
const worker = read("sw.js");
const migration = read("supabase/migrations/20261026_anonymous_letters.sql");

function inlineScripts(html, file) {
  const blocks = [...html.matchAll(/<script\b([^>]*)>([\s\S]*?)<\/script>/gi)];
  const inline = blocks.filter((m) => !/\bsrc\s*=/.test(m[1]));
  assert.ok(inline.length, file + " must contain executable JS");
  return inline.map((m) => m[2]);
}

test("Both app HTML pages contain syntactically valid inline JS", () => {
  for (const [file, html] of [["index.html", index], ["letters.html", letters]]) {
    for (const js of inlineScripts(html, file)) {
      assert.doesNotThrow(() => new Script(js, { filename: file }));
    }
  }
});

test("Node server and service worker scripts parse", () => {
  assert.doesNotThrow(() => new Script(server, {filename: "server.js"}));
  assert.doesNotThrow(() => new Script(worker, {filename: "sw.js"}));
});

test("Letters HTML is routable but repo source remains private", () => {
  assert.match(server, /pathname==='\/letters\.html'/);
  assert.match(server, /if\(!isAppPage&&!isAsset\)/);
  assert.match(server, /res\.writeHead\(404/);
  assert.match(server, /pathname==='\/letters\.html'\)res\.setHeader\('Cache-Control','no-store'\)/);
});

test("PWA navigation is network-only for anonymous letters", () => {
  assert.match(worker, /url\.pathname === "\/letters\.html"/);
  assert.match(worker, /event\.respondWith\(fetch\(request\)\)/);
});

test("Main app shows event entry only after server-side event status", () => {
  assert.match(index, /id="lettersEventCard"[^>]*hidden/);
  assert.match(index, /db\.rpc\("event_status"\)/);
  assert.match(index, /card\.hidden=!Boolean\(state\?\.event_active\)/);
});

test("Event DB remains disabled until intentional launch", () => {
  assert.match(migration, /enabled boolean not null default false/);
  assert.match(migration, /values \(1,false\)/);
  assert.match(migration, /function public\.event_is_active/);
  assert.match(migration, /function public\.event_require_access/);
});

test("RPC authorization and anonymity protections are present", () => {
  assert.match(migration, /event_pair_allowed/);
  assert.match(migration, /event_letter_mutes/);
  assert.match(migration, /event_letter_reports/);
  assert.match(migration, /public\.legal_consents/);
  assert.match(migration, /pg_advisory_xact_lock/);
  assert.match(migration, /v_count<5/);
  assert.match(migration, /v_used>=3/);
  assert.match(migration, /interval '48 hours'/);
  assert.match(migration, /from public, anon, authenticated/);
  assert.match(migration, /to authenticated/);
  assert.doesNotMatch(letters, /\.innerHTML\s*=/);
});
