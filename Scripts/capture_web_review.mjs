#!/usr/bin/env node
/**
 * Capture every web page of the design review, at phone and desktop size.
 *
 *     node Scripts/capture_web_review.mjs <output-folder> [names...] [--only=mobile|desktop]
 *
 * Starts its own fixture server (Scripts/preview_web_fixture.mjs, a synthetic
 * 60-save library; nothing reaches Supabase) on PORT (default 4886) and its own
 * headless Chrome over the DevTools protocol (CDP_PORT, default 9334, a
 * throw-away profile), so it never disturbs anything already running. PostHog
 * is blocked, light mode and reduced motion are forced.
 *
 * Sizes: mobile 390×844 @2x with an iPhone UA, desktop 1440×900 @1x. File
 * names match the 1.3 baseline (`current/web/NN-name-mobile.png`,
 * `-desktop.png`, and `-full-` for the long pages). Pass names (e.g.
 * `02-library 04-browse`) to shoot only those. CHROME= overrides the binary.
 */
import { spawn } from "node:child_process";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";

// Needs Node ≥ 22 (global WebSocket). Under an older node, re-run under a
// newer one if the machine has it (NODE22=/path/to/node to choose).
if (typeof WebSocket === "undefined") {
  const { spawnSync } = await import("node:child_process");
  const candidates = [process.env.NODE22, "/opt/homebrew/bin/node", "/usr/local/bin/node"].filter(Boolean);
  const newer = candidates.find((bin) => {
    const v = spawnSync(bin, ["-p", "typeof WebSocket"], { encoding: "utf8" });
    return v.status === 0 && v.stdout.trim() === "function";
  });
  if (!newer) { console.error("capture_web_review needs Node 22+ (global WebSocket). Set NODE22=/path/to/node."); process.exit(2); }
  const r = spawnSync(newer, [fileURLToPath(import.meta.url), ...process.argv.slice(2)], { stdio: "inherit" });
  process.exit(r.status ?? 1);
}
const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const args = process.argv.slice(2);
const OUT = args.find((a) => !a.startsWith("--"));
if (!OUT) { console.error("usage: node Scripts/capture_web_review.mjs <output-folder> [names...] [--only=mobile|desktop]"); process.exit(2); }
const ONLY = args.filter((a) => !a.startsWith("--")).slice(1);
const VIEWPORTS = (args.find((a) => a.startsWith("--only=")) || "--only=mobile,desktop").slice(7).split(",");
const PORT = Number(process.env.PORT) || 4886, CDP = Number(process.env.CDP_PORT) || 9334;
const O = `http://127.0.0.1:${PORT}`;
const CHROME = process.env.CHROME || "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome";
fs.mkdirSync(OUT, { recursive: true });

// What to shoot. signedIn pages get the fixture session; js runs after load.
const PLAN = [
  { name: "01-home-signed-out", path: "/", full: true },
  { name: "02-library", path: "/", signedIn: true },
  // The fixture server keeps what is saved, so each size pastes a link of its
  // own; a fixed link came out as "Already in your library" the second time.
  { name: "03-add-quick-file-dial", path: "/", signedIn: true, after: 3500,
    js: `(async()=>{const b=[document.getElementById("add-mobile"),document.getElementById("add-desktop")].find(x=>x&&x.offsetParent);b&&b.click();await new Promise(r=>setTimeout(r,500));const i=document.getElementById("add-url");if(!i)return false;i.value="https://www.tiktok.com/@kaylawalks/video/7299"+String(Date.now()).slice(-6);i.dispatchEvent(new InputEvent("input",{bubbles:true,inputType:"insertFromPaste"}));return true})()` },
  { name: "04-browse", path: "/#browse", signedIn: true },
  { name: "05-topic-fitness", path: "/#browse/fitness", signedIn: true },
  { name: "06-side-quests", path: "/#browse/quests", signedIn: true },
  { name: "07-revisit", path: "/#revisit", signedIn: true },
  { name: "08-you", path: "/#you", signedIn: true },
  { name: "09-help", path: "/#help", signedIn: true },
  { name: "10-collections", path: "/#collections", signedIn: true },
  { name: "11-pro-yearly", path: "/pro/?plan=yearly", full: true },
  { name: "12-app", path: "/app/", full: true },
  { name: "13-faq", path: "/faq", full: true },
  { name: "14-lifetime", path: "/lifetime", full: true },
  { name: "15-what-is-bookmarker", path: "/what-is-bookmarker", full: true },
].filter((s) => !ONLY.length || ONLY.includes(s.name));

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const server = spawn(process.execPath, [path.join(ROOT, "Scripts/preview_web_fixture.mjs")],
  { cwd: ROOT, env: { ...process.env, PORT: String(PORT) }, stdio: "ignore" });
const profile = fs.mkdtempSync(path.join(os.tmpdir(), "bookmarker-webshots-"));
const chrome = spawn(CHROME, ["--headless=new", `--remote-debugging-port=${CDP}`, `--user-data-dir=${profile}`,
  "--no-first-run", "--hide-scrollbars", "--mute-audio", "about:blank"], { stdio: "ignore" });
const stop = () => { try { chrome.kill(); } catch {} try { server.kill(); } catch {} try { fs.rmSync(profile, { recursive: true, force: true, maxRetries: 10, retryDelay: 200 }); } catch {} };
process.on("exit", stop);

try {
  for (let i = 0; i < 50; i++) { try { await fetch(`http://127.0.0.1:${CDP}/json/version`); await fetch(O + "/favicon.png"); break; } catch { await sleep(200); } }
  const page = (await (await fetch(`http://127.0.0.1:${CDP}/json`)).json()).find((t) => t.type === "page");
  const ws = new WebSocket(page.webSocketDebuggerUrl);
  await new Promise((r) => (ws.onopen = r));
  let id = 0; const pending = new Map();
  ws.onmessage = (m) => { const d = JSON.parse(m.data); if (d.id && pending.has(d.id)) { pending.get(d.id)(d); pending.delete(d.id); } };
  const send = (method, params = {}) => new Promise((r) => { const i = ++id; pending.set(i, r); ws.send(JSON.stringify({ id: i, method, params })); })
    .then((d) => { if (d.error) throw new Error(method + ": " + JSON.stringify(d.error)); return d.result; });
  const ev = async (expression) => (await send("Runtime.evaluate", { expression, awaitPromise: true, returnByValue: true })).result?.value;

  await send("Network.enable"); await send("Page.enable");
  await send("Network.setBlockedURLs", { urls: ["*posthog*"] });
  await send("Emulation.setEmulatedMedia", { features: [{ name: "prefers-color-scheme", value: "light" }, { name: "prefers-reduced-motion", value: "reduce" }] });
  const VP = {
    mobile: { width: 390, height: 844, deviceScaleFactor: 2, mobile: true,
      ua: "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1" },
    desktop: { width: 1440, height: 900, deviceScaleFactor: 1, mobile: false,
      ua: "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36" },
  };
  const go = async (url, wait = 2500) => { await send("Page.navigate", { url }); await sleep(wait); };
  async function shot(name, full = false) {
    let p = { format: "png" };
    if (full) {
      const m = await send("Page.getLayoutMetrics");
      p = { format: "png", captureBeyondViewport: true,
        clip: { x: 0, y: 0, width: Math.ceil(m.cssContentSize.width), height: Math.ceil(m.cssContentSize.height), scale: 1 } };
    }
    const r = await send("Page.captureScreenshot", p);
    fs.writeFileSync(path.join(OUT, name + ".png"), Buffer.from(r.data, "base64"));
    console.log("  " + name + ".png");
  }
  async function session(on) {
    await go(O + "/favicon.png", 300);
    await ev(on
      ? `localStorage.clear();localStorage.setItem("bm.internal","1");localStorage.setItem("bm.session",JSON.stringify({access_token:"local-fixture-only",refresh_token:"local-fixture-only",expires_at:Date.now()+86400000,user_id:"11111111-1111-4111-8111-111111111111",email:"fixture@example.test"}))`
      : `localStorage.clear();localStorage.setItem("bm.internal","1")`);
  }

  console.log(`Capturing to ${OUT}`);
  for (const vp of VIEWPORTS) {
    const v = VP[vp]; if (!v) continue;
    await send("Emulation.setDeviceMetricsOverride", { width: v.width, height: v.height, deviceScaleFactor: v.deviceScaleFactor, mobile: v.mobile });
    await send("Emulation.setTouchEmulationEnabled", { enabled: v.mobile });
    await send("Emulation.setUserAgentOverride", { userAgent: v.ua });
    for (const s of PLAN) {
      await session(!!s.signedIn);
      await go(O + s.path, s.wait || 3000);
      if (s.js) { await ev(s.js); await sleep(s.after || 2500); }
      await shot(`${s.name}-${vp}`);
      if (s.full) await shot(`${s.name}-full-${vp}`, true);
    }
  }
  ws.close();
} finally {
  stop();
}
process.exit(0);
