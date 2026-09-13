// LOCAL SYNTHETIC QA ONLY. No Supabase credentials, emails or writes leave this server.
// Visit the printed URL, choose email sign-in, fixture@example.test / 123456.
import http from "node:http";
import fs from "node:fs/promises";
import path from "node:path";
const root=path.resolve("docs"), port=4876, origin=`http://127.0.0.1:${port}`;
const owner="11111111-1111-4111-8111-111111111111", now=new Date().toISOString();
const tables={
  profiles:[{id:owner,display_name:"QA fixture",handle:"local_fixture"}],
  bookmarks:Array.from({length:60},(_,i)=>({id:`fixture-${i}`,owner_id:owner,url:`https://example.com/post/${i}`,title:i===59?"Needle: a saved breathing practice":`Synthetic saved post ${i+1}`,body_text:`Synthetic captured excerpt ${i+1}: a useful practice to return to.`,platform:i%2?"x":"instagram",kind:i%2?"thread":"reel",category_id:"fitness",subcategory:i%2?"Running":"Mobility",tags:["practice",i%2?"running":"hips"],image_url:null,note_text:i===0?"My private fixture note":null,saved_at:new Date(Date.now()-i*3600000).toISOString(),updated_at:now,deleted_at:null,enrichment_version:2})),
  missions:[{id:"fixture-quest",owner_id:owner,title:"Improve mobility",detail:"A synthetic goal",category_id:"fitness",bookmark_ids:["fixture-0"],todos:[],completed_days:[],is_archived:false,created_at:now,updated_at:now,deleted_at:null}],
  custom_topics:[],custom_subtopics:[],bookmark_opens:[],topic_art:[],collections:[]
};
const mime={".html":"text/html",".js":"text/javascript",".css":"text/css",".jpg":"image/jpeg",".png":"image/png",".svg":"image/svg+xml",".json":"application/json"};
http.createServer(async(req,res)=>{
  const url=new URL(req.url,origin);
  const send=(body,status=200)=>{res.writeHead(status,{"Content-Type":"application/json","Cache-Control":"no-store"});res.end(JSON.stringify(body));};
  try {
    if(url.pathname.startsWith("/fixture-api/")) {
      let raw="";for await(const chunk of req) raw+=chunk;const body=raw?JSON.parse(raw):{};
      const route=url.pathname.replace("/fixture-api","");
      if(route==="/auth/v1/otp") return send({});
      if(route==="/auth/v1/verify" || route==="/auth/v1/token") return send({access_token:"local-fixture-only",refresh_token:"local-fixture-only",expires_in:3600,user:{id:owner,email:"fixture@example.test"}});
      if(route==="/auth/v1/logout") return send({});
      if(route==="/functions/v1/quest-brief") return send({summary:null,steps:[],reason:"unavailable"});
      if(route.startsWith("/functions/")) return send({reason:"fixture_no_external_calls"});
      const name=route.replace("/rest/v1/","");
      if(!Object.hasOwn(tables,name)) return send({error:"Not supported by this synthetic fixture"},400);
      if(req.method==="POST") {
        const incoming=Array.isArray(body)?body:[body];
        for(const row of incoming){const at=tables[name].findIndex(r=>r.id===row.id);if(at>=0)tables[name][at]={...tables[name][at],...row};else tables[name].push(row);}
        return send(incoming);
      }
      if(req.method==="PATCH"){Object.assign(tables[name][0],body);return send([tables[name][0]]);}
      const offset=Number(url.searchParams.get("offset")||0);return send(tables[name].slice(offset,offset+1000));
    }
    const file=path.resolve(root,"."+(url.pathname==="/"?"/index.html":url.pathname));
    if(!file.startsWith(root+path.sep)){res.writeHead(403);return res.end();}
    let bytes=await fs.readFile(file);
    if(file.endsWith("index.html")) bytes=Buffer.from(bytes.toString().replace(/const SUPABASE_URL = "[^"]*";/,`const SUPABASE_URL = "${origin}/fixture-api";`).replace(/const ANON_KEY = "[^"]*";/,'const ANON_KEY = "local-fixture-only";').replace("<title>","<title>SYNTHETIC QA · "));
    res.writeHead(200,{"Content-Type":mime[path.extname(file)]||"application/octet-stream","Cache-Control":"no-store"});res.end(bytes);
  } catch {res.writeHead(404);res.end("Fixture resource not found");}
}).listen(port,"127.0.0.1",()=>console.log(`SYNTHETIC QA ONLY: ${origin} — sign in as fixture@example.test with code 123456. Nothing is sent to Supabase.`));
