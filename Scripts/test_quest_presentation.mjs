import fs from "node:fs";
import vm from "node:vm";
import assert from "node:assert/strict";
const c = vm.createContext({});
vm.runInContext(fs.readFileSync("docs/quest-presentation.js","utf8") + ";globalThis.q=QuestPresentation",c);
for(const [title,category,path] of [
  ["Breathing","health","topics/health"], ["Breathing",null,"topics/wellness"],
  ["Making OFS profitable",null,"quests/business"], ["Start a new chapter",null,"quests/compass"],
  ["Improve mobility",null,"quests/run"], ["Go down the rabbit hole",null,"quests/rabbit"],
  ["Get on top of anxiety",null,"topics/mentalhealth"]
]) assert.equal(c.q.art(title, category, "", {health:true}), `/img/${path}.jpg`);
const rows=Array.from({length:60},(_,i)=>({id:String(i),title:`Save ${i}`,category_id:i%2?"a":"b",tags:[i===59?"needle":"tag"]}));
assert.equal(c.q.candidates(rows,[],null,"needle",s=>s.toLowerCase())[0].id,"59");
assert.equal(c.q.candidates(rows,["59"],null,"needle",s=>s.toLowerCase()).length,0);
assert.equal(c.q.candidates(rows,[],"b","needle",s=>s.toLowerCase()).length,0);
const html=fs.readFileSync("docs/index.html","utf8");
const elements=Object.fromEntries(["quest-save","quest-title","quest-detail","quest-topic","quest-err","quest-dialog"].map(id=>[id,{value:"A goal",disabled:false,textContent:""}]));
let closed=0;
Object.assign(c,{$:id=>elements[id],missions:new Map(),questDraft:{id:"one"},questFromAdd:false,closeDlg:()=>closed++,toast:()=>{},track:()=>{},commitMission:async()=>null});
vm.runInContext(html.slice(html.indexOf("async function saveQuest()"),html.indexOf("async function deleteQuest()")),c);
await c.saveQuest(); assert.equal(closed,0); assert.match(elements["quest-err"].textContent,/not yet backed up/); assert.equal(elements["quest-save"].disabled,false);
c.commitMission=async()=>({id:"one"}); await c.saveQuest(); assert.equal(closed,1);
console.log("Quest artwork, 60-item search, attachment exclusion and confirmed-save states passed.");
