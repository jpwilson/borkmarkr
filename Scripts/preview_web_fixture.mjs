// LOCAL SYNTHETIC QA ONLY. No Supabase credentials, emails or writes leave this server.
// Visit the printed URL, choose email sign-in, fixture@example.test / 123456.
// PORT=4877 node Scripts/preview_web_fixture.mjs runs a second copy beside the first.
import http from "node:http";
import fs from "node:fs/promises";
import path from "node:path";
const root=path.resolve("docs"), port=Number(process.env.PORT)||4876, origin=`http://127.0.0.1:${port}`;
const owner="11111111-1111-4111-8111-111111111111", now=new Date().toISOString();
/* 60 synthetic saves that look like a real library: every platform and card
   shape, covers from the site's own /img (two deliberately dead, to show the
   poster a dead cover becomes), 11 not filed yet, 5 automatic guesses, a
   creator filed to the same place three times, and one post saved from both
   TikTok and Instagram. Row 59 stays the needle the search check looks for.
   [title, platform, kind, url, author, topic, subtopic, tags, cover, seconds, filing, body] */
const U="user", A="automatic";
const ROWS=[
  ["3 hip openers I do before every run (no equipment)","tiktok","clip","https://www.tiktok.com/@kaylawalks/video/7312345678001","@kaylawalks","fitness","Mobility",["hips","warmup"],"/img/quests/run.jpg",38,U],
  ["3 hip openers I do before every run (no equipment)","instagram","reel","https://www.instagram.com/kaylawalks/reel/C9hipOpen01/","@kaylawalks","fitness","Mobility",["hips"],null,null,U],
  ["Why your deadlift stalls at 100kg — form breakdown","youtube","video","https://www.youtube.com/watch?v=fx0deadlift1","Squat Mechanics","fitness","Strength",["deadlift","form"],"/img/topics/fitness.jpg",754,U],
  ["Thread: how I'd learn marketing from zero in 2026","x","thread","https://x.com/growthnotes/status/1850000000000000001","@growthnotes","marketing","Social strategy",["beginner"],null,null,U,"Start with one channel, one offer and one number you check every Friday. Everything else is noise for the first 90 days."],
  ["Tiny-apartment storage that actually works","tiktok","clip","https://www.tiktok.com/@smallspacesam/video/7312345678004","@smallspacesam",null,null,[],"/img/topics/home.jpg",51,null],
  ["Sourdough starter troubleshooting flowchart","instagram","post","https://www.instagram.com/crumbcoach/p/C9sourdough5/","@crumbcoach","recipes","Baking",["sourdough"],"/img/quests/cook.jpg",null,U],
  ["The 4-day work week, two years in: what the data says","web","article","https://www.theguardian.com/work/four-day-week-two-years",null,"career","Remote work",[],"/img/art-hero.jpg",null,A],
  ["60-second knife skills: the claw grip","shorts","short","https://www.youtube.com/shorts/knifeclaw007","@kenjiskitchen","recipes","Quick meals",["knife"],"/img/topics/recipes.jpg",58,U],
  ["A field guide to the birds outside your window","x","thread","https://x.com/backyardbirder/status/1850000000000000008","@backyardbirder",null,null,[],null,null,null,"Start with the five you hear before you see. Robins sing first, wrens shout, and the sparrows are the background hum."],
  ["Small balcony vegetable garden ideas for renters","pinterest","pin","https://www.pinterest.com/pin/1850000000009/","Balcony Bloom","garden","Vegetables",["balcony"],"/img/topics/garden.jpg",null,U],
  ["Osaka on $60 a day — full itinerary","tiktok","clip","https://www.tiktok.com/@wanderfrugal/video/7312345678010","@wanderfrugal","travel","Itineraries",["japan","budget"],"/img/topics/travel.jpg",74,U],
  ["The best croissant in Paris is in a laundromat","instagram","reel","https://www.instagram.com/flakyfiles/reel/C9croissant11/","@flakyfiles",null,null,["paris"],null,null,null],
  ["Why this 1970s synth still sounds incredible","youtube","video","https://www.youtube.com/watch?v=synth1970s12","Analog Hours",null,null,[],"/img/topics/music.jpg",1312,null],
  ["How to read a balance sheet in 10 minutes","web","article","https://plainfinance.co/balance-sheet-in-10-minutes",null,"money","Budgeting",["accounting"],null,null,U,"Assets on one side, what you owe on the other, and the difference is what is actually yours."],
  ["5 mobility drills that undo a desk day","instagram","reel","https://www.instagram.com/kaylawalks/reel/C9deskday014/","@kaylawalks","fitness","Mobility",["desk","hips"],"/img/covers/expired-reel.jpg",null,U],
  ["Watercolor basics: your first 3 exercises","tiktok","clip","https://www.tiktok.com/@paintwithmara/video/7312345678015","@paintwithmara","art","Painting",["watercolour"],"/img/topics/art.jpg",62,A],
  ["The negotiation email template that got me +18%","x","thread","https://x.com/careerplays/status/1850000000000000016","@careerplays","career","Negotiation",["salary"],null,null,U,"Anchor on the role, not your old salary. Then go quiet. The first number after the silence is usually theirs."],
  ["Van conversion: the whole electrical system in one video","youtube","video","https://www.youtube.com/watch?v=vanwiring017","Vanlife Garage","outdoors","Camping",["van","wiring"],"/img/topics/outdoors.jpg",2140,U],
  ["Tokyo listening bars you can actually get into","instagram","post","https://www.instagram.com/tinytokyo/p/C9listening18/","@tinytokyo","travel","Food spots",["tokyo","bars"],null,null,A],
  ["Pottery wheel, first session: what to expect","tiktok","clip","https://www.tiktok.com/@mudandfire/video/7312345678019","@mudandfire","crafts","Ceramics",["pottery"],"/img/topics/crafts.jpg",47,U],
  ["A beginner's map of the AI agent landscape","web","article","https://builderslog.dev/ai-agent-landscape",null,"ai","Agents",["agents"],"/img/topics/ai.jpg",null,U],
  ["The 2-minute plank fix nobody tells you","shorts","short","https://www.youtube.com/shorts/plankfix0021","@coreclub",null,null,[],null,44,null],
  ["Magnesium: what the evidence actually says","instagram","reel","https://www.instagram.com/evidencemed/reel/C9magnesium22/","@evidencemed","nutrition","Supplements",["magnesium","sleep"],"/img/topics/nutrition.jpg",null,U],
  ["I rebuilt my sleep in 30 days — protocol inside","x","thread","https://x.com/circadianclub/status/1850000000000000023","@circadianclub","wellness","Evening routines",["sleep"],null,null,U,"Same wake time seven days a week, light in the first hour, no screens in bed. Boring, and it works."],
  ["Capsule wardrobe: 30 outfits from 12 pieces","pinterest","pin","https://www.pinterest.com/pin/1850000000024/","Edit & Keep","fashion","Capsule wardrobe",[],"/img/topics/fashion.jpg",null,U],
  ["Zone 2 explained without the bro science","youtube","video","https://www.youtube.com/watch?v=zone2plain25","Endurance Lab","fitness","Running",["zone2","running"],"/img/topics/sports.jpg",905,U],
  ["Thrifted lamp makeover in 10 minutes","tiktok","clip","https://www.tiktok.com/@secondhandsue/video/7312345678026","@secondhandsue",null,null,["thrift"],"/img/topics/diy.jpg",39,null],
  ["The library of Alexandria didn't burn down once","web","article","https://www.historytoday.com/alexandria-myth",null,"history","Ancient",["alexandria"],null,null,A,"It faded over centuries: budget cuts, purges and neglect did more than any single fire."],
  ["Dog recall training: the 3-step game","instagram","reel","https://www.instagram.com/goodboyschool/reel/C9recall0028/","@goodboyschool","pets","Training",["dogs"],"/img/topics/pets.jpg",null,U],
  ["Bond ladders for people who hate bonds","x","thread","https://x.com/bogleheadd/status/1850000000000000029","@bogleheadd","investing","Bonds",["bonds"],null,null,U,"Buy one bond for each of the next five years. When one matures, buy another at the far end. That's the whole trick."],
  ["Budget mic test: $30 vs $300","shorts","short","https://www.youtube.com/shorts/mictest00030","@gearcheck","tech","Audio",["mic"],"/img/topics/tech.jpg",45,U],
  ["The quiet comeback of the paper notebook","web","article","https://craftnotes.blog/paper-notebook-comeback",null,"learning","Note-taking",[],"/img/quests/learn.jpg",null,U],
  ["Kyoto in the rain — a walking route","tiktok","clip","https://www.tiktok.com/@wanderfrugal/video/7312345678032","@wanderfrugal","travel","Itineraries",["kyoto"],null,66,U],
  ["Moodboard: warm minimal living rooms","instagram","post","https://www.instagram.com/homebyhana/p/C9moodboard33/","@homebyhana","home","Interiors",[],"/img/quests/create.jpg",null,U],
  ["Every hip hinge cue, ranked by a physio","x","thread","https://x.com/rehabroom/status/1850000000000000034","@rehabroom","fitness","Mobility",["hips","form"],null,null,U,"1. Soft knees. 2. Push the hips back to a wall. 3. Keep the phone-screen flat on your back. The rest is detail."],
  ["How Venice actually made its money","youtube","video","https://www.youtube.com/watch?v=venicetrade35","Cities Past","history","Medieval",["venice","trade"],"/img/topics/history.jpg",1580,U],
  ["Why everyone is suddenly talking about Dunbar's number","web","article","https://www.example-weekly.com/dunbars-number",null,null,null,[],null,null,null,"About 150 stable relationships, the theory goes, and the internet keeps testing the ceiling."],
  ["The 20-minute Sunday meal-prep system","instagram","reel","https://www.instagram.com/mealprepmanny/reel/C9mealprep37/","@mealprepmanny","recipes","Meal prep",["sunday","batch"],"/img/topics/fooddrink.jpg",null,U],
  ["Cold plunge: what 30 days actually did","tiktok","clip","https://www.tiktok.com/@iceandiron/video/7312345678038","@iceandiron","wellness","Habits",[],null,83,A],
  ["How the Roman concrete mystery got solved","x","thread","https://x.com/historydept/status/1850000000000000039","@historydept","history","Ancient",["rome"],null,null,U,"Hot-mixing quicklime left little white lumps in the concrete, and those lumps quietly heal its cracks for centuries."],
  ["Hand-lettering practice sheets (free)","pinterest","pin","https://www.pinterest.com/pin/1850000000040/","Letter Club","art","Typography",["lettering"],"/img/quests/market.jpg",null,U],
  ["Bitcoin halving explained in 4 minutes","youtube","video","https://www.youtube.com/watch?v=halving00041","@chainplain","crypto","Bitcoin",["halving"],"/img/topics/crypto.jpg",252,U],
  ["Dollar-cost averaging, backtested over 20 years","web","article","https://plainfinance.co/dca-backtest",null,"investing","ETFs & index funds",["dca"],null,null,U],
  ["Studio tour: 200 sq ft, 3 hobbies","instagram","post","https://www.instagram.com/tinystudio/p/C9studio0043/","@tinystudio",null,null,[],"/img/quests/business.jpg",null,null],
  ["Bouldering: the footwork drill that fixed my climbing","tiktok","clip","https://www.tiktok.com/@senditsarah/video/7312345678044","@senditsarah","outdoors","Climbing",["climbing"],"/img/topics/nature.jpg",55,U],
  ["The ETF flows chart everyone's posting","x","thread","https://x.com/marketmaps/status/1850000000000000045","@marketmaps","crypto","Bitcoin",["etf"],null,null,U],
  ["One-pan lemon orzo in 15 minutes","shorts","short","https://www.youtube.com/shorts/lemonorzo046","@dinnerdash","recipes","One-pan",["orzo"],null,59,U],
  ["Field notes: building a tiny greenhouse","web","article","https://growlog.net/tiny-greenhouse",null,"garden","Vegetables",[],"/img/topics/homestead.jpg",null,U],
  ["Learn this one chord and play 50 songs","instagram","reel","https://www.instagram.com/strumstart/reel/C9chord00048/","@strumstart",null,null,[],null,null,null],
  ["The only Lightroom editing tutorial you need","youtube","video","https://www.youtube.com/watch?v=lightroom049","Light & Lens","photovideo","Editing",["lightroom"],"/img/topics/photovideo.jpg",1104,U],
  ["Why L2 fees finally dropped","x","thread","https://x.com/rollupdaily/status/1850000000000000050","@rollupdaily","crypto","Ethereum",["l2","fees"],null,null,U],
  ["Peony care: cut them at the marshmallow stage","tiktok","clip","https://www.tiktok.com/@bloomwhere/video/7312345678051","@bloomwhere","garden","Houseplants",["flowers"],null,41,U],
  ["What I learned shipping 100 side projects","web","article","https://www.indiehackers.com/post/100-side-projects",null,"business","Startups",[],null,null,U,"Most of them died in week two. The ones that lived had a customer before they had a logo."],
  ["Film photography starter kit under $150","instagram","post","https://www.instagram.com/grainandglow/p/C9filmkit053/","@grainandglow","photovideo","Cameras",["film"],"/img/covers/expired-post.jpg",null,U],
  ["Hot take: most productivity advice is for people who already have time","x","thread","https://x.com/deepworkdan/status/1850000000000000054","@deepworkdan",null,null,[],null,null,null,"If your day is not yours, start with one protected hour a week. That is the whole system."],
  ["Kids' rainy-day activity jar","pinterest","pin","https://www.pinterest.com/pin/1850000000055/","Little Days","parenting","Activities",[],"/img/topics/parenting.jpg",null,U],
  ["Beginner's guide to pour-over coffee","youtube","video","https://www.youtube.com/watch?v=pourover0056","Brew Basics","fooddrink","Coffee",["coffee"],"/img/topics/science.jpg",618,U],
  ["This $8 gadget changed how I cook rice","tiktok","clip","https://www.tiktok.com/@kitchenhacker/video/7312345678057","@kitchenhacker",null,null,[],null,33,null],
  ["The best free tools for learning Spanish in 2026","web","article","https://www.languagelab.io/free-spanish-tools",null,"learning","Languages",["spanish"],"/img/topics/learning.jpg",null,U],
  ["Needle: a saved breathing practice","x","thread","https://x.com/breathcoach/status/1850000000000000059","@breathcoach","wellness","Breathwork",["practice","breath"],null,null,U,"Four in, hold four, six out. Five rounds before anything hard."],
];
const tables={
  profiles:[{id:owner,display_name:"QA fixture",handle:"local_fixture"}],
  bookmarks:ROWS.map(([title,platform,kind,url,author,category,sub,tags,image,seconds,filing,body],i)=>({id:`fixture-${i}`,owner_id:owner,url,title,author,body_text:body??null,platform,kind,category_id:category,subcategory:sub,tags,image_url:image,duration_seconds:seconds,filing_source:filing,note_text:i===0?"My private fixture note":null,saved_at:new Date(Date.now()-i*6*3600000).toISOString(),updated_at:now,deleted_at:null,enrichment_version:2})),
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
