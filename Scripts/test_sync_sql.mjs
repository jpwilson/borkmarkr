import { PGlite } from "@electric-sql/pglite";
import fs from "node:fs";
import assert from "node:assert/strict";
// An isolated PostgreSQL engine, never the production database.
const db = new PGlite();
const owner = "11111111-1111-4111-8111-111111111111";
const other = "22222222-2222-4222-8222-222222222222";
await db.exec(`
  create role authenticated;
  create schema auth;
  create function auth.uid() returns uuid language sql stable as
    $$ select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid $$;
  create table public.profiles(id uuid primary key);
  insert into profiles values ('${owner}'), ('${other}');
  create function public.touch_updated_at() returns trigger language plpgsql as
    $$ begin new.updated_at = now(); return new; end $$;
`);
for (const file of ["0006_missions.sql", "0013_quest_sync.sql"]) {
  await db.exec(fs.readFileSync("supabase/migrations/" + file, "utf8"));
}
await db.exec(`
  grant usage on schema public, auth to authenticated;
  grant select, insert, update, delete on missions to authenticated;
  set role authenticated;
  select set_config('request.jwt.claim.sub', '${owner}', false);
`);
await db.query(`insert into missions(id, owner_id, title, updated_at, bookmark_ids, todos)
  values ('quest', $1, 'Original', '2026-09-01', array['a','b'], '[{"id":"todo","text":"Do it","done":true}]')`, [owner]);
await db.query(`insert into missions(id, owner_id, title, updated_at) values ('quest', $1, 'Newer', '2026-09-03')
  on conflict(owner_id,id) do update set title=excluded.title, updated_at=excluded.updated_at`, [owner]);
await db.query(`insert into missions(id, owner_id, title, updated_at) values ('quest', $1, 'Stale', '2026-09-02')
  on conflict(owner_id,id) do update set title=excluded.title, updated_at=excluded.updated_at`, [owner]);
let row = (await db.query("select * from missions")).rows[0];
assert.equal(row.title, "Newer");
assert.deepEqual(row.bookmark_ids, ["a", "b"]);
assert.equal(row.todos[0].text, "Do it");
assert.equal(row.todos[0].done, true);
await db.exec("update missions set deleted_at='2026-09-04', updated_at='2026-09-04', is_archived=true");
await db.exec("update missions set deleted_at=null, updated_at='2026-09-02', is_archived=false");
row = (await db.query("select * from missions")).rows[0];
assert.ok(row.deleted_at);
assert.equal(row.is_archived, true);
await db.exec("update missions set brief_text='fixture', brief_bork_count=2, updated_at='2026-09-05'");
assert.equal((await db.query("select brief_text from missions")).rows[0].brief_text, "fixture");
await db.query("select set_config('request.jwt.claim.sub', $1, false)", [other]);
assert.equal((await db.query("select * from missions")).rows.length, 0);
await assert.rejects(db.query("insert into missions(id,owner_id,title) values ('attack',$1,'No')", [owner]), /row-level security/);
await db.query("select set_config('request.jwt.claim.sub', '', false)");
assert.equal((await db.query("select * from missions")).rows.length, 0);
await db.exec("reset role");
await db.exec(fs.readFileSync("supabase/migrations/0014_custom_taxonomy_sync.sql", "utf8"));
await db.exec("grant select, insert, update, delete on custom_topics, custom_subtopics to authenticated; set role authenticated;");
await db.query("select set_config('request.jwt.claim.sub', $1, false)", [owner]);
await db.query("insert into custom_topics values ($1,'custom.cafe','Café & ceramics',77,null,'2026-09-01','2026-09-01',null)", [owner]);
await db.query("insert into custom_subtopics values ($1,'fitness|breathing','fitness','Breathing','2026-09-01','2026-09-01',null)", [owner]);
assert.equal((await db.query("select name from custom_topics")).rows[0].name, "Café & ceramics");
await db.exec("update custom_topics set name='Renamed', updated_at='2026-09-03'; update custom_topics set name='Stale', updated_at='2026-09-02'");
assert.equal((await db.query("select name from custom_topics")).rows[0].name, "Renamed");
await db.query("select set_config('request.jwt.claim.sub', $1, false)", [other]);
assert.equal((await db.query("select * from custom_topics")).rows.length, 0);
assert.equal((await db.query("select * from custom_subtopics")).rows.length, 0);
await db.close();
console.log("Custom taxonomy PostgreSQL migrations: exact metadata, empty records, stale edits and RLS passed.");
console.log("Quest PostgreSQL migrations: LWW, tombstones, metadata, owner isolation and unsigned denial passed.");
