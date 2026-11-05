# -*- coding: utf-8 -*-
"""Assembles the static written pages for docs/. Output is plain HTML files;
nothing runs at request time. Re-run only when the shared head/nav/footer
changes (see SEO.md)."""
import json, os, re
from pathlib import Path

SITE = "https://bookmarker.lol"
# Derived from this file, not hard-coded: the generators must work in any
# checkout, and an absolute path would quietly write into the wrong one.
OUT = Path(__file__).resolve().parents[2] / "docs"
UPDATED = "21 October 2026"
LASTMOD = "2026-10-21"

NAV = """<header class="site-head">
  <div class="head-in">
    <a class="brand" href="/"><img src="/img/mark-192.png" width="28" height="28" alt=""><span>bookmarker</span></a>
    <nav class="head-nav" aria-label="Main">
      <a href="/what-is-bookmarker">What it is</a>
      <a href="/app/">iPhone app</a>
      <a href="/faq">FAQ</a>
      <a href="/alternatives">Alternatives</a>
      <a href="/vs-twitter-bookmarks">vs X bookmarks</a>
      <a href="/vs-raindrop">vs Raindrop</a>
      <a href="/vs-twillot">vs Twillot</a>
      <a href="/vs-mymind">vs mymind</a>
    </nav>
    <a class="head-cta" href="/get/">Get the app</a>
  </div>
</header>"""

FOOT = """<footer class="site-foot">
  <div class="foot-in">
    <div>
      <h2>bookmarker</h2>
      <ul>
        <li><a href="/">Web app</a></li>
        <li><a href="/app/">iPhone app</a></li>
        <li><a href="/what-is-bookmarker">What is bookmarker?</a></li>
        <li><a href="/faq">FAQ</a></li>
        <li><a href="/palace/">Library Island</a></li>
      </ul>
    </div>
    <div>
      <h2>Compare</h2>
      <ul>
        <li><a href="/alternatives">Best bookmark managers for saved posts</a></li>
        <li><a href="/vs-twitter-bookmarks">vs X (Twitter) bookmarks</a></li>
        <li><a href="/vs-raindrop">vs Raindrop.io</a></li>
        <li><a href="/vs-twillot">vs Twillot</a></li>
        <li><a href="/vs-mymind">vs mymind</a></li>
      </ul>
    </div>
    <div>
      <h2>Guides</h2>
      <ul>
        <li><a href="/how-to-organize-twitter-bookmarks">Organise your X bookmarks</a></li>
        <li><a href="/how-to-search-twitter-bookmarks">Search your X bookmarks</a></li>
        <li><a href="/llms.txt">llms.txt</a></li>
      </ul>
    </div>
    <div>
      <h2>Company</h2>
      <ul>
        <li><a href="/press/">Press kit</a></li>
        <li><a href="/privacy">Privacy policy</a></li>
        <li><a href="/terms">Terms of use</a></li>
        <li><a href="mailto:hello@bookmarker.lol">hello@bookmarker.lol</a></li>
      </ul>
    </div>
  </div>
  <p class="foot-copy">&copy; 2026 bookmarker. Made by JP. bookmarker is free on the App Store and on the web.</p>
</footer>"""

# PostHog, byte for byte the block in docs/index.html and the hand-written
# pages, so these pages count visits too. Its own constant because HEAD goes
# through str.format and the loader is all braces.
POSTHOG = """<script>
  /* PostHog — product analytics + session replay (inputs masked). Public
     project token by design; the privacy policy discloses this. */
  !function(t,e){var o,n,p,r;e.__SV||(window.posthog=e,e._i=[],e.init=function(i,s,a){function g(t,e){var o=e.split(".");2==o.length&&(t=t[o[0]],e=o[1]),t[e]=function(){t.push([e].concat(Array.prototype.slice.call(arguments,0)))}}(p=t.createElement("script")).type="text/javascript",p.crossOrigin="anonymous",p.async=!0,p.src=s.api_host.replace(".i.posthog.com","-assets.i.posthog.com")+"/static/array.js",(r=t.getElementsByTagName("script")[0]).parentNode.insertBefore(p,r);var u=e;for(void 0!==a?u=e[a]=[]:a="posthog",u.people=u.people||[],u.toString=function(t){var e="posthog";return"posthog"!==a&&(e+="."+a),t||(e+=" (stub)"),e},u.people.toString=function(){return u.toString(1)+".people (stub)"},o="init capture register register_once register_for_session unregister unregister_for_session getFeatureFlag getFeatureFlagPayload isFeatureEnabled reloadFeatureFlags updateEarlyAccessFeatureEnrollment getEarlyAccessFeatures on onFeatureFlags onSessionId getSurveys getActiveMatchingSurveys renderSurvey canRenderSurvey identify setPersonProperties group resetGroups setPersonPropertiesForFlags resetPersonPropertiesForFlags setGroupPropertiesForFlags resetGroupPropertiesForFlags opt_in_capturing opt_out_capturing has_opted_in_capturing has_opted_out_capturing clear_opt_in_out_capturing reset get_distinct_id getGroups get_session_id get_session_replay_url alias set_config startSessionRecording stopSessionRecording sessionRecordingStarted captureException loadToolbar get_property getSessionProperty createPersonProfile debug".split(" "),n=0;n<o.length;n++)g(u,o[n]);e._i.push([i,s,a])},e.__SV=1)}(document,window.posthog||[]);
  posthog.init('phc_o34s8vv6TWjzDemdh39CAW8d4R52qFzVt2RZCnQEEKqx', {api_host: 'https://us.i.posthog.com', defaults: '2025-05-24'});
  /* Our own devices shouldn't count as traffic: visit /?internal=1 once on a
     device to opt that browser out forever; /?internal=0 to undo. */
  try {
    var _q = new URLSearchParams(location.search);
    if (_q.get("internal") === "1") localStorage.setItem("bm.internal", "1");
    if (_q.get("internal") === "0") { localStorage.removeItem("bm.internal"); posthog.opt_in_capturing(); }
    if (localStorage.getItem("bm.internal")) posthog.opt_out_capturing();
  } catch (e) {}
</script>"""

HEAD = """<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="apple-itunes-app" content="app-id=6799805479">
<title>{title}</title>
<meta name="description" content="{desc}">
<link rel="canonical" href="{url}">
<meta property="og:type" content="{ogtype}">
<meta property="og:site_name" content="bookmarker">
<meta property="og:url" content="{url}">
<meta property="og:title" content="{title}">
<meta property="og:description" content="{desc}">
<meta property="og:image" content="{site}/img/share-v2.jpg">
<meta property="og:image:width" content="1200">
<meta property="og:image:height" content="630">
<meta property="og:image:alt" content="A coral clay bookmark with the Instagram, X, TikTok and YouTube app icons set into it. Every save. One library.">
<meta name="twitter:card" content="summary_large_image">
<meta name="twitter:title" content="{title}">
<meta name="twitter:description" content="{desc}">
<meta name="twitter:image" content="{site}/img/share-v2.jpg">
<link rel="icon" href="/favicon.png">
<link rel="apple-touch-icon" href="/img/apple-touch-icon.png">
<meta name="theme-color" content="#F6F3EE">
<link rel="preconnect" href="https://fonts.googleapis.com">
<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
<link href="https://fonts.googleapis.com/css2?family=Bricolage+Grotesque:opsz,wght@12..96,700;12..96,800&family=Instrument+Sans:wght@400;500;600;700&display=swap" rel="stylesheet">
{posthog}
<link rel="stylesheet" href="/content.css">
{jsonld}</head>
<body>
{nav}
<main>
{crumbs}{body}
</main>
{foot}
</body>
</html>
"""


def ld(obj):
    return ('<script type="application/ld+json">\n'
            + json.dumps(obj, indent=2, ensure_ascii=False) + "\n</script>\n")


def breadcrumb(name, path):
    return {
        "@context": "https://schema.org",
        "@type": "BreadcrumbList",
        "itemListElement": [
            {"@type": "ListItem", "position": 1, "name": "bookmarker", "item": SITE + "/"},
            {"@type": "ListItem", "position": 2, "name": name, "item": SITE + path},
        ],
    }


def article(headline, desc, path):
    return {
        "@context": "https://schema.org",
        "@type": "Article",
        "headline": headline,
        "description": desc,
        "url": SITE + path,
        "datePublished": "2026-10-19",
        "dateModified": LASTMOD,
        "inLanguage": "en",
        "author": {"@type": "Person", "name": "Jean-Paul Wilson", "url": SITE + "/press/"},
        "publisher": {
            "@type": "Organization",
            "name": "bookmarker",
            "url": SITE + "/",
            "logo": {"@type": "ImageObject", "url": SITE + "/img/apple-touch-icon.png"},
        },
        "isPartOf": {"@type": "WebSite", "name": "bookmarker", "url": SITE + "/"},
    }


# The one description of the product that every page's structured data reuses.
APP_LD = {
    "@context": "https://schema.org",
    "@type": "MobileApplication",
    "name": "Bookmarker: Save Links & Reels",
    "alternateName": "bookmarker",
    "url": SITE + "/app/",
    "sameAs": "https://apps.apple.com/us/app/bookmarker-save-links-reels/id6799805479",
    "installUrl": "https://apps.apple.com/us/app/bookmarker-save-links-reels/id6799805479",
    "applicationCategory": "ProductivityApplication",
    "applicationSubCategory": "Bookmark manager",
    "operatingSystem": "iOS 17.0 or later",
    "image": SITE + "/img/share-v2.jpg",
    "screenshot": [SITE + "/img/library.png", SITE + "/img/browse.png", SITE + "/img/search.png"],
    "description": ("bookmarker is a bookmark manager for iPhone and the web that collects what you save on "
                    "Instagram, X (Twitter), TikTok, YouTube and the open web into one library, files every save "
                    "into a topic and subtopic automatically, and lets you search it again later."),
    "featureList": [
        "Save any link from any app through the iOS share sheet",
        "Automatic filing into 50 topics and 612 subtopics, always overridable",
        "Browse by topic or by the app a save came from",
        "Search titles, accounts, tags, notes, topics and links",
        "Dated notes on any save",
        "Counts how often you reopen something",
        "Import browser bookmarks and X, Instagram, TikTok and YouTube data exports",
        "Share a collection of saves as a link",
        "Works offline; the first 20 saves need no account",
    ],
    "offers": {"@type": "Offer", "price": "0", "priceCurrency": "USD",
               "availability": "https://schema.org/InStock",
               "url": "https://apps.apple.com/us/app/bookmarker-save-links-reels/id6799805479"},
    "author": {"@type": "Person", "name": "Jean-Paul Wilson"},
    "publisher": {"@type": "Organization", "name": "bookmarker", "url": SITE + "/"},
}

ORG_LD = {
    "@context": "https://schema.org",
    "@type": "Organization",
    "name": "bookmarker",
    "url": SITE + "/",
    "logo": SITE + "/img/apple-touch-icon.png",
    "email": "hello@bookmarker.lol",
    "description": ("bookmarker makes a bookmark manager for iPhone and the web that puts everything you save on "
                    "Instagram, X (Twitter), TikTok, YouTube and the open web into one searchable library."),
    "founder": {"@type": "Person", "name": "Jean-Paul Wilson"},
    "sameAs": ["https://apps.apple.com/us/app/bookmarker-save-links-reels/id6799805479"],
}

SITE_LD = {
    "@context": "https://schema.org",
    "@type": "WebSite",
    "name": "bookmarker",
    "url": SITE + "/",
    "inLanguage": "en",
    "description": ("One library for everything you save on Instagram, X (Twitter), TikTok, YouTube and the web."),
    "publisher": {"@type": "Organization", "name": "bookmarker", "url": SITE + "/"},
}


def write(path, title, desc, body, crumb=None, ogtype="article", jsonld=()):
    """path is the canonical path ('/faq'); the file lands at docs/<path>.html."""
    crumbs = ""
    if crumb:
        crumbs = ('<nav class="crumbs" aria-label="Breadcrumb"><a href="/">bookmarker</a> &rsaquo; '
                  + crumb + "</nav>\n")
    html = HEAD.format(
        title=title, desc=desc, url=SITE + path, site=SITE, ogtype=ogtype, posthog=POSTHOG,
        jsonld="".join(ld(o) for o in jsonld), nav=NAV, foot=FOOT,
        crumbs=crumbs, body=body.strip())
    name = path.strip("/") or "index"
    dest = os.path.join(OUT, name + ".html")
    with open(dest, "w", encoding="utf-8") as fh:
        fh.write(html)
    txt = re.sub(r"(?is)<(script|style|noscript|svg)\b.*?</\1>", " ", html)
    txt = re.sub(r"(?s)<[^>]+>", " ", txt)
    words = len([w for w in txt.split() if re.search(r"\w", w)])
    print(f"{words:5d} words  {dest}")
