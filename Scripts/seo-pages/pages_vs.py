# -*- coding: utf-8 -*-
import sys
sys.path.insert(0, "/tmp/gen")
from tpl import *

HEDGE = ("""<div class="callout"><p>Competitor details here come from the other product's own website, checked on
21 October 2026, and they change. Follow the links and confirm anything that matters to you. Where the other
tool is better, it says so.</p></div>""")

SEARCH_TRUTH = """<p>One thing to be clear about, because it is easy to oversell: bookmarker does not index the
inside of the posts you save. A search matches the title, the account that posted it, your tags, your notes, the
topic and subtopic, the source app, the link, and any description text the page published. You can narrow it to
topics, subtopics or tags. Several words mean "all of these must appear"; there is no quoted-phrase operator.</p>"""

# ─────────────────────── /vs-raindrop ───────────────────────
write(
    "/vs-raindrop",
    "bookmarker vs Raindrop.io: which bookmark manager to pick",
    "Raindrop.io is the better web-article manager; bookmarker is built for posts you save in phone apps. "
    "Compared on sources, search, archiving, platforms and price. Updated October 2026.",
    crumb="bookmarker vs Raindrop.io",
    ogtype="article",
    jsonld=[breadcrumb("bookmarker vs Raindrop.io", "/vs-raindrop"),
            article("bookmarker vs Raindrop.io",
                    "An honest comparison of bookmarker and Raindrop.io for saving and organising links.",
                    "/vs-raindrop"),
            APP_LD],
    body="""
<h1>bookmarker vs Raindrop.io</h1>
<p class="meta">Last updated: """ + UPDATED + """</p>

<p class="intro">Both are bookmark managers, and they are built for different halves of the problem.
<a href="https://raindrop.io/" rel="nofollow noopener" target="_blank">Raindrop.io</a> is a mature, cross-platform
manager for web pages, articles and research that you save from a browser. bookmarker is a free iPhone and web
library for the posts you save inside Instagram, X, TikTok and YouTube, filed into topics automatically. If your
saving happens in a browser, Raindrop is probably the better answer; if it happens in phone apps, bookmarker is.</p>

""" + HEDGE + """

<h2>What Raindrop.io does, in its own terms</h2>
<p>Per raindrop.io, Raindrop runs as a web app, browser extensions and apps across platforms, and organises saves
into nestable collections with tags and filters. It finds duplicates and broken links, offers highlights and
annotations, several view modes (grid, headlines, masonry, list), integrations and an API, sharing and permissions
for collaborators, and backups to Dropbox or Google Drive. Two things stand out as genuinely strong: it keeps an
archived copy of saved web pages, so a page that is taken down still has something behind it; and its full-text
search covers the entire content of every saved page, PDF and YouTube video, not just titles and tags. It has a
free plan and a paid subscription.</p>

<h2>What bookmarker does</h2>
<p>bookmarker starts from the phone. You tap Share in any app and pick bookmarker, or paste a link, or import the
data export from X, Instagram, TikTok or YouTube. Every save lands in a topic and subtopic automatically — 50
topics, 612 subtopics, all overridable — and the app it came from is recorded, so you can browse by topic
("everything about running, wherever it came from") or by source ("everything I kept from TikTok"), with each
filtering the other. You can add a dated note to any save, bookmarker counts how often you reopen something, and
you can turn a set of saves into a shareable page at bookmarker.lol/c/&hellip; with an optional expiry.</p>

<h2>Where Raindrop.io is better</h2>
<ul>
  <li><strong>Search depth.</strong> Raindrop searches inside the content of what you saved. bookmarker does not —
    see the note below.</li>
  <li><strong>Archiving.</strong> Raindrop keeps copies of saved pages. bookmarker stores links only, so a deleted
    post is simply gone.</li>
  <li><strong>Platform coverage.</strong> Raindrop has browser extensions and runs on Android, Windows and macOS.
    bookmarker is an iPhone app plus a web app, with no browser extension and no Android app.</li>
  <li><strong>Manual structure and teamwork.</strong> Nestable collections, permissions, shared editing, an API.</li>
  <li><strong>Maturity.</strong> It has been around far longer and has the feature surface to show for it.</li>
</ul>
""" + SEARCH_TRUTH + """

<h2>Where bookmarker is better</h2>
<ul>
  <li><strong>Saving from social apps.</strong> bookmarker is designed for the share sheet inside Instagram,
    TikTok, YouTube and X, and it labels every save with the app it came from.</li>
  <li><strong>Filing you do not have to do.</strong> Raindrop asks which collection; bookmarker picks a topic and
    subtopic and lets you correct it. With a few thousand saves, that difference is the whole product.</li>
  <li><strong>Two browse axes that cross.</strong> Topic and source app, each filtering the other.</li>
  <li><strong>Dated notes and revisit counts.</strong> Why you kept something, and whether you ever went back.</li>
  <li><strong>Price.</strong> bookmarker is free, including the unlimited, backed-up library after a free email
    sign-in.</li>
</ul>

<h2>Side by side</h2>
<div class="comparison-table">
  <table>
    <thead><tr><th>&nbsp;</th><th>bookmarker</th><th>Raindrop.io</th></tr></thead>
    <tbody>
      <tr><td>Built for</td><td>Posts saved inside phone apps</td><td>Web pages, articles, research</td></tr>
      <tr><td>Saving from Instagram / TikTok / X / YouTube</td><td class="yes">iOS share sheet, source app recorded</td><td>Link saving; integrations can auto-save X and YouTube favourites</td></tr>
      <tr><td>Browser extension</td><td class="no">No</td><td class="yes">Yes</td></tr>
      <tr><td>Android / Windows</td><td class="no">No app (web app works in any browser)</td><td class="yes">Yes</td></tr>
      <tr><td>Automatic filing into topics</td><td class="yes">Yes — 50 topics, 612 subtopics, overridable</td><td>You choose the collection; tags and an AI assistant are offered</td></tr>
      <tr><td>Search inside saved page content</td><td class="no">No — titles, accounts, tags, notes, topics, links</td><td class="yes">Yes — pages, PDFs and YouTube</td></tr>
      <tr><td>Archived copy of saved pages</td><td class="no">No — links only</td><td class="yes">Yes</td></tr>
      <tr><td>Browse by the app a save came from</td><td class="yes">Yes</td><td>Not a documented feature</td></tr>
      <tr><td>Revisit tracking</td><td class="yes">Counts reopens</td><td>Not a documented feature</td></tr>
      <tr><td>Import your old saves</td><td class="yes">Browser bookmarks plus X, Instagram, TikTok, YouTube exports</td><td class="yes">Browser bookmarks and other managers</td></tr>
      <tr><td>Works offline</td><td class="yes">Yes, the iPhone library is local</td><td>Partly, depending on the app</td></tr>
      <tr><td>Price</td><td class="yes">Free</td><td>Free plan plus a paid subscription (see <a href="https://raindrop.io/pricing" rel="nofollow noopener" target="_blank">raindrop.io/pricing</a>)</td></tr>
    </tbody>
  </table>
</div>

<h2>Can you use both?</h2>
<p>Yes, and it is a sensible setup: Raindrop for articles and research you save in a browser, bookmarker for the
reels, clips and threads you save on your phone. The workflows barely touch — one is browser-first, the other is
share-sheet-first.</p>

<h2>The bottom line</h2>
<p>Choose Raindrop.io if most of what you keep is web pages, you want them searchable to the word and archived,
and you need Android, Windows or a browser extension. Choose bookmarker if most of what you keep is posts from
social apps, you want them filed by topic without doing it yourself, and you want it free.</p>

<p><a class="cta" href="/get/">Try bookmarker — free</a></p>
<span class="cta-sub">See also <a href="/alternatives">all the alternatives</a>,
<a href="/vs-twillot">vs Twillot</a> and the <a href="/faq">FAQ</a>.</span>
""")

# ─────────────────────── /vs-twillot ───────────────────────
write(
    "/vs-twillot",
    "bookmarker vs Twillot: X bookmark manager comparison",
    "Twillot archives your whole X bookmark history in a browser extension; bookmarker covers Instagram, "
    "TikTok and YouTube too, from your phone. An honest comparison, updated October 2026.",
    crumb="bookmarker vs Twillot",
    ogtype="article",
    jsonld=[breadcrumb("bookmarker vs Twillot", "/vs-twillot"),
            article("bookmarker vs Twillot",
                    "An honest comparison of bookmarker and Twillot for managing X (Twitter) bookmarks.",
                    "/vs-twillot"),
            APP_LD],
    body="""
<h1>bookmarker vs Twillot</h1>
<p class="meta">Last updated: """ + UPDATED + """</p>

<p class="intro">Both tools exist because X's bookmark list becomes useless once it is long. They attack it from
opposite ends. <a href="https://www.twillot.com/en" rel="nofollow noopener" target="_blank">Twillot</a> is a
browser extension that reaches into X and pulls your entire bookmark, like and post history down into a local
archive. bookmarker is a free iPhone and web library that takes new saves from <em>any</em> app — X, Instagram,
TikTok, YouTube — and files them into topics. If your problem is "I already have 4,000 X bookmarks", Twillot is
the more direct answer.</p>

""" + HEDGE + """

<h2>What Twillot does, in its own terms</h2>
<p>Per twillot.com, Twillot turns your X bookmarks into a searchable library: it syncs your bookmarks, likes,
posts and replies, gets you past X's scroll limit to reach your full history, keeps the data inside your browser,
and preserves posts even after they are deleted. Its listed features include search, "folders that fill
themselves", AI organising, export of your archive, an offline archive and media downloads. It is a browser
extension with a web workspace, and it has a free start plus paid plans.</p>

<h2>What bookmarker does</h2>
<p>bookmarker is a native iPhone app (iOS 17+) with a web app. You save by tapping Share in any app and picking
bookmarker — on X, tap Share and then "Share via&hellip;" — or by pasting a link, or by importing the data export
from X, Instagram, TikTok or YouTube. Every save is filed into one of 50 topics and 612 subtopics automatically
and overridably, labelled with the app it came from, and browsable either way. You can add dated notes, see how
often you have reopened something, and share a set of saves as a link with an optional expiry.</p>

<h2>Where Twillot is better</h2>
<ul>
  <li><strong>Getting your existing X bookmarks.</strong> Twillot syncs them directly from X. bookmarker cannot
    read your X bookmark list — you import X's data export instead, which means requesting the archive and
    waiting for it.</li>
  <li><strong>Surviving deletion.</strong> Twillot says it preserves posts after they are deleted. bookmarker
    stores links, so a deleted post is gone.</li>
  <li><strong>Export and bulk operations.</strong> Exporting your archive and downloading media are headline
    Twillot features.</li>
  <li><strong>Desktop.</strong> It lives in a desktop browser, which is where a lot of people do their reading.</li>
  <li><strong>X depth generally.</strong> Likes, replies and your own posts, not just bookmarks.</li>
</ul>

<h2>Where bookmarker is better</h2>
<ul>
  <li><strong>It is not only X.</strong> Instagram, TikTok, YouTube, YouTube Shorts, Threads, Pinterest and plain
    web pages all land in the same library, with the source app recorded.</li>
  <li><strong>It works where you actually see the post.</strong> You are holding a phone in Instagram; a desktop
    browser extension cannot help there.</li>
  <li><strong>Browse by topic across sources.</strong> Your X thread and your Instagram reel about the same
    marathon end up in the same topic.</li>
  <li><strong>Dated notes and revisit counts.</strong></li>
  <li><strong>Price.</strong> bookmarker is free, including the unlimited backed-up library after a free email
    sign-in.</li>
</ul>
""" + SEARCH_TRUTH + """

<h2>Side by side</h2>
<div class="comparison-table">
  <table>
    <thead><tr><th>&nbsp;</th><th>bookmarker</th><th>Twillot</th></tr></thead>
    <tbody>
      <tr><td>Form factor</td><td>iPhone app + web app</td><td>Browser extension + web workspace</td></tr>
      <tr><td>X (Twitter) saves</td><td class="yes">Yes, new saves via the share sheet; old ones via X's data export</td><td class="yes">Yes, synced directly from your X account</td></tr>
      <tr><td>Reaches your existing X bookmark history</td><td class="no">Only through X's data export</td><td class="yes">Yes, including past X's scroll limit</td></tr>
      <tr><td>Instagram, TikTok, YouTube, Threads, Pinterest</td><td class="yes">Yes</td><td class="no">X only</td></tr>
      <tr><td>Automatic organising</td><td class="yes">Topic + subtopic on every save, overridable</td><td class="yes">Folders that fill themselves, AI organising</td></tr>
      <tr><td>Keeps posts after deletion</td><td class="no">No — links only</td><td class="yes">Yes</td></tr>
      <tr><td>Export your archive</td><td>Share a collection as a link</td><td class="yes">Yes, multiple formats</td></tr>
      <tr><td>Media downloads</td><td class="no">No</td><td class="yes">Yes</td></tr>
      <tr><td>Save from a phone, inside the app you are in</td><td class="yes">Yes</td><td class="no">Desktop browser</td></tr>
      <tr><td>Dated notes / revisit counts</td><td class="yes">Yes</td><td>Not a documented feature</td></tr>
      <tr><td>Price</td><td class="yes">Free</td><td>Free start plus paid plans (see <a href="https://www.twillot.com/en" rel="nofollow noopener" target="_blank">twillot.com</a>)</td></tr>
    </tbody>
  </table>
</div>

<h2>Can you use both?</h2>
<p>That is arguably the best setup if X is a big part of your life: Twillot to rescue and archive the X history you
already have, bookmarker for everything you save from now on, across every app.</p>

<h2>The bottom line</h2>
<p>Twillot is the specialist — the right tool if the job is "get my X bookmarks out of X and keep them". bookmarker
is the generalist — the right tool if the job is "stop having five separate piles of saved posts on my phone".</p>

<p><a class="cta" href="/get/">Try bookmarker — free</a></p>
<span class="cta-sub">See also <a href="/vs-twitter-bookmarks">vs X's built-in bookmarks</a>,
<a href="/alternatives">all the alternatives</a> and the <a href="/faq">FAQ</a>.</span>
""")

# ─────────────────── /vs-twitter-bookmarks ───────────────────
write(
    "/vs-twitter-bookmarks",
    "bookmarker vs X (Twitter) bookmarks: what a library adds",
    "X's built-in bookmarks are free and instant but stay inside X. Here is what a separate library adds — "
    "topics, notes, cross-app saves, revisit counts — and when X's own are enough.",
    crumb="bookmarker vs X bookmarks",
    ogtype="article",
    jsonld=[breadcrumb("bookmarker vs X bookmarks", "/vs-twitter-bookmarks"),
            article("bookmarker vs X (Twitter) built-in bookmarks",
                    "What bookmarker adds over the bookmark feature built into X, and when X's own bookmarks are enough.",
                    "/vs-twitter-bookmarks"),
            APP_LD],
    body="""
<h1>bookmarker vs X (Twitter) built-in bookmarks</h1>
<p class="meta">Last updated: """ + UPDATED + """</p>

<p class="intro">X has a bookmark button, it is free, and it is one tap. So why add anything? The short answer:
X's bookmarks only ever hold X, and they tell you nothing about what you saved or whether you ever went back to
it. bookmarker is a free iPhone and web library that holds your X saves <em>and</em> your Instagram, TikTok and
YouTube saves, files each one into a topic, and lets you search and annotate the lot.</p>

<div class="callout"><p>X's bookmark features change, and some of them depend on a paid X Premium tier — bookmark
folders, for instance, have been a subscriber feature. Check X's current help pages rather than trusting any
comparison, including this one, on the detail. Everything below is about what a separate library adds, which does
not change.</p></div>

<h2>What X's built-in bookmarks are good at</h2>
<p>Zero friction. You are already in X, you tap the bookmark icon, it is saved, there is nothing to install and
nothing to pay. For something you intend to read tomorrow, nothing is better. If you save a handful of posts a
month and only use X, you do not need anything else — and this page is not going to pretend otherwise.</p>

<h2>What they cannot do</h2>
<h3>1. They only hold X</h3>
<p>This is the big one. Your Instagram saves, TikTok favourites and YouTube "Watch later" are three more separate
lists in three more apps. Nothing in X's bookmarks can see them, so the recipe you saved on Instagram and the
recipe thread you saved on X never sit next to each other.</p>

<h3>2. There is no topic to browse by</h3>
<p>X's bookmarks are a reverse-chronological list. You cannot ask for "just the coding threads" or "just the
recipes" unless you have manually filed things into folders — and folders are a paid-tier feature and still
manual. You remember what something was <em>about</em>, not when you saved it.</p>

<h3>3. They do not tell you what you actually use</h3>
<p>No dates to sort by, no note about why you kept it, and no record of how many times you have gone back to
something. The platform has no reason to build that: its business is your next scroll, not your last one.</p>

<h3>4. They stay inside X</h3>
<p>You cannot send someone a curated set of twenty saved posts as one link, and you cannot keep a copy anywhere
you control.</p>

<h2>What bookmarker adds</h2>
<ul>
  <li><strong>One library across apps.</strong> X, Instagram, TikTok, YouTube, YouTube Shorts, Threads, Pinterest
    and ordinary web pages, each labelled with where it came from. Browse by topic or by source app; each view
    filters the other.</li>
  <li><strong>Automatic filing.</strong> Every save lands in a topic and subtopic — 50 topics, 612 subtopics,
    always overridable, and you can add your own subtopics.</li>
  <li><strong>Search.</strong> Over titles, the account that posted it, your tags, your notes, the topic and
    subtopic, the source app and the link, narrowable to topics, subtopics or tags.</li>
  <li><strong>Dated notes.</strong> Why you kept it, written down, with a date.</li>
  <li><strong>Revisit counts.</strong> bookmarker counts how often you reopen a save, so the things you actually
    use rise to the top.</li>
  <li><strong>Shareable collections.</strong> Turn a set of saves into a page at bookmarker.lol/c/&hellip; with an
    expiry of never, one day or ten days, and switch it off whenever.</li>
  <li><strong>Your old saves.</strong> Import X's data export, plus Instagram, TikTok, YouTube and browser
    bookmarks.</li>
  <li><strong>It is free.</strong> First 20 saves with no account; a free email sign-in makes it unlimited and
    backed up.</li>
</ul>
""" + SEARCH_TRUTH + """
<p>bookmarker also stores links rather than copies, so it does not rescue a deleted post — if that is what you
need, look at <a href="/vs-twillot">Twillot</a>, which archives X posts.</p>

<h2>Side by side</h2>
<div class="comparison-table">
  <table>
    <thead><tr><th>&nbsp;</th><th>bookmarker</th><th>X built-in bookmarks</th></tr></thead>
    <tbody>
      <tr><td>Saving a post from X</td><td class="yes">Share &rarr; "Share via&hellip;" &rarr; bookmarker</td><td class="yes">One tap, in the app</td></tr>
      <tr><td>Nothing to install</td><td class="no">Needs the app or the web app</td><td class="yes">Already there</td></tr>
      <tr><td>Holds Instagram, TikTok, YouTube saves too</td><td class="yes">Yes</td><td class="no">X only</td></tr>
      <tr><td>Automatic topic filing</td><td class="yes">Yes, on every save</td><td class="no">No</td></tr>
      <tr><td>Folders</td><td class="yes">Topics, subtopics and tags, free</td><td>Manual folders, a paid X Premium feature</td></tr>
      <tr><td>Your own notes on a save</td><td class="yes">Dated notes</td><td class="no">No</td></tr>
      <tr><td>Tracks what you revisit</td><td class="yes">Yes</td><td class="no">No</td></tr>
      <tr><td>Share a curated set as one link</td><td class="yes">Yes, with an optional expiry</td><td class="no">No</td></tr>
      <tr><td>Keeps a copy if the post is deleted</td><td class="no">No — links only</td><td class="no">No</td></tr>
      <tr><td>Price</td><td class="yes">Free</td><td class="yes">Free (some bookmark features need X Premium)</td></tr>
    </tbody>
  </table>
</div>

<h2>When X's bookmarks are enough</h2>
<ul>
  <li>You save a handful of posts and clear them out regularly.</li>
  <li>X is the only app you save from.</li>
  <li>You do not need to search or group what you saved.</li>
</ul>

<h2>When a separate library is worth it</h2>
<ul>
  <li>You have hundreds or thousands of saves and find nothing.</li>
  <li>You save from Instagram, TikTok and YouTube as well.</li>
  <li>You want to browse by subject rather than scroll by date.</li>
  <li>You want to know what you keep coming back to, or to send someone a set.</li>
</ul>
<p>Plenty of people use both: X's bookmarks as a quick inbox, bookmarker for anything they want to keep.</p>

<p><a class="cta" href="/get/">Try bookmarker — free</a></p>
<span class="cta-sub">See also <a href="/how-to-organize-twitter-bookmarks">how to organise your X bookmarks</a>,
<a href="/how-to-search-twitter-bookmarks">how to search them</a> and
<a href="/alternatives">the alternatives</a>.</span>
""")
