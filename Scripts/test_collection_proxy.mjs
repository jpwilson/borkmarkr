import fs from "node:fs";
import vm from "node:vm";
import assert from "node:assert/strict";
let mode="ok", seen=[];
const c=vm.createContext({Request,Response,Headers,URL,console,fetch:async(url,opts)=>{
  seen.push({url,opts});
  if(mode==="throw") throw Error("offline");
  return new Response('<title>Real collection</title><meta property="og:title" content="Real collection">',{status:mode==="error"?502:mode==="missing"?404:200,headers:{"Content-Type":"text/plain","Cache-Control":"no-store","Content-Security-Policy":"sandbox"}});
}});
vm.runInContext(fs.readFileSync("cloudflare/collection-proxy.js","utf8").replace("export default","globalThis.worker ="),c);
const request=method=>new Request("https://bookmarker.lol/c/abcd1234",{method,headers:{Authorization:"secret",Cookie:"private", "User-Agent":"private-agent"}});
let res=await c.worker.fetch(request("GET"));
assert.equal(res.status,200); assert.match(res.headers.get("Content-Type"),/text\/html/); assert.match(await res.text(),/og:title/);
assert.equal(seen[0].opts.headers.Authorization,undefined); assert.equal(seen[0].opts.headers.Cookie,undefined);
assert.equal(seen[0].opts.headers["User-Agent"],"bookmarker-proxy");
res=await c.worker.fetch(request("HEAD")); assert.equal(await res.text(),"");
assert.equal((await c.worker.fetch(request("POST"))).status,405);
for(const failure of ["error","throw"]) { mode=failure; res=await c.worker.fetch(request("GET")); assert.equal(res.status,503); assert.equal(res.headers.get("Cache-Control"),"no-store"); assert.match(await res.text(),/temporarily unavailable/); }
mode="missing"; res=await c.worker.fetch(request("GET")); assert.equal(res.status,404); assert.equal(res.headers.get("Cache-Control"),"no-store");
console.log("Collection proxy: server HTML, HEAD, method gates, header privacy, uncached outages and missing links passed.");
