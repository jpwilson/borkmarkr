import fs from "node:fs";
import assert from "node:assert/strict";
import {PGlite} from "@electric-sql/pglite";
const db=new PGlite();
await db.exec(`create role anon;create role authenticated;create role service_role;
create table profiles(id text,display_name text,handle text,email text);
create table collections(id text,owner_id text,name text,note text,slug text,visibility text,deleted_at timestamptz,expires_at timestamptz,updated_at timestamptz);
create table bookmarks(id text,owner_id text,url text,title text,author text,platform text,kind text,category_id text,subcategory text,tags text[],image_url text,duration_seconds int,body_text text,note_text text,deleted_at timestamptz);
create table custom_topics(id text,owner_id text,name text,deleted_at timestamptz);
create table collection_items(collection_id text,bookmark_owner text,bookmark_id text,position int,added_at timestamptz);
insert into profiles values('owner','Fixture Person',null,'PRIVATE EMAIL');
insert into collections values('c','owner','Collection',null,'abcd1234','public',null,null,now());
insert into bookmarks(id,owner_id,url,title,category_id,subcategory,tags,note_text) values('a','owner','https://example.com','Post','custom.a','Subtopic',array['tag'],'PRIVATE NOTE');
insert into custom_topics values('custom.a','owner','Exact custom name',null);
insert into collection_items values('c','owner','a',0,now());`);
await db.exec(fs.readFileSync("supabase/migrations/0017_collection_taxonomy.sql","utf8"));
await db.exec("set role anon");
const fetch=async()=> (await db.query("select public.collection_by_slug('abcd1234') result")).rows[0].result;
let result=await fetch();
assert.equal(result.items[0].category_name,"Exact custom name"); assert.equal(result.items[0].subcategory,"Subtopic"); assert.deepEqual(result.items[0].tags,["tag"]);
assert.ok(!JSON.stringify(result).includes("PRIVATE"));
for(const change of ["expires_at=now()-interval '1 second'","expires_at=null,visibility='private'","visibility='public',deleted_at=now()"]) {
  await db.exec("reset role;update collections set "+change+";set role anon"); assert.equal(await fetch(),null);
}
await db.exec("reset role;update collections set deleted_at=null;update bookmarks set owner_id='someone-else';set role anon");
assert.equal((await fetch()).items.length,0);
await db.close();console.log("Public collection SQL: exact custom taxonomy, private-field exclusion, expiry/revoke/delete and cross-owner denial passed.");
