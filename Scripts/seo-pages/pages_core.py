# -*- coding: utf-8 -*-
# tpl.py is the sibling module; running this file puts its own directory on
# sys.path, so no path juggling is needed.
from tpl import *

# ───────────────────────── /what-is-bookmarker ─────────────────────────
write(
    "/what-is-bookmarker",
    "What is bookmarker? A bookmark manager for your saved posts",
    "bookmarker is a free bookmark manager for iPhone and the web that puts everything you save on Instagram, "
    "X, TikTok and YouTube into one library, filed by topic and searchable.",
    crumb="What is bookmarker?",
    ogtype="article",
    jsonld=[APP_LD, ORG_LD, breadcrumb("What is bookmarker?", "/what-is-bookmarker"),
            article("What is bookmarker?", "A plain explanation of what bookmarker is, who it is for, what it does and what it does not do.", "/what-is-bookmarker")],
    body="""
<h1>What is bookmarker?</h1>
<p class="meta">Last updated: """ + UPDATED + """</p>

<p class="intro">bookmarker is a free bookmark manager for iPhone and the web that collects everything you save on
Instagram, X (Twitter), TikTok, YouTube and the open web into one library, files every save into a topic
automatically, and lets you find it again later. It is for people who save hundreds or thousands of posts
across several apps and can never find any of them again.</p>

<h2>The problem it solves</h2>
<p>A reel on Instagram, a thread on X, a clip on TikTok, a recipe video on YouTube — every app keeps its own
saved list. None of those lists share anything with each other, almost none of the items have real titles, and
there is no topic to browse by. So you end up with five separate piles of things you meant to come back to, and
no way to answer the only question you ever actually ask: <em>where did I see that thing about&hellip;?</em></p>
<p>bookmarker is the layer above all of them. One library, every app, filed and searchable.</p>

<h2>What it does</h2>
<ul>
  <li><strong>Saves from anywhere.</strong> Tap Share in any iPhone app and pick bookmarker, or paste a link into
    the app, or paste it into the web app at <a href="/">bookmarker.lol</a>.</li>
  <li><strong>Files itself, in one tap.</strong> Every save lands in a topic and a subtopic — Fitness &rsaquo;
    Mobility, Recipes &rsaquo; Meal prep. Straight after you save, a dial shows the seven likeliest of 50 topics
    with the best guess in the middle: tap to file it there, turn the dial to pick another, or leave it and the
    guess stands. Signed in, an AI model also reads the caption and suggests the topic and subtopic. There are 612
    subtopics, you can add topics and subtopics of your own, and anything unfiled or uncertain waits in
    <em>Sort your borks</em>, one card at a time.</li>
  <li><strong>Browses two ways.</strong> By topic, to see everything about running wherever it came from; or by
    source app, to see everything you kept from TikTok. Each view filters the other.</li>
  <li><strong>Finds things again.</strong> Search covers the title, the account that posted it, any post text
    that came with the save, your tags, your notes, the topic and subtopic, the source app and the link itself.
    You can narrow a search to topics, subtopics or tags only.</li>
  <li><strong>Remembers why.</strong> Add a dated note to any save, and bookmarker counts how often you have
    gone back to something — the signal platform bookmarks throw away.</li>
  <li><strong>Imports what you already saved.</strong> Browser bookmarks, or the data export from Instagram
    (saved posts), TikTok (favourites and likes), X (bookmarks and likes), YouTube (playlists, including Watch
    later), plus Pinterest in the web app. Thousands of old saves become one library in a single step.</li>
  <li><strong>Shares a set.</strong> Pick some saves and bookmarker turns them into a page at
    bookmarker.lol/c/&hellip; that you can send to anyone, with an expiry of never, one day or ten days, and a
    switch to turn it off.</li>
</ul>

<h2>Who it is for</h2>
<ul>
  <li>Heavy savers — people with hundreds or thousands of likes and bookmarks across Instagram, X, TikTok and YouTube.</li>
  <li>People who save practical things: recipes, workouts, product research, travel itineraries, tutorials.</li>
  <li>Anyone who has thought "I definitely saved that" and then failed to find it.</li>
  <li>People who want their library on their own phone rather than in another company's feed.</li>
</ul>

<h2>What it does not do</h2>
<p>Being specific here is more useful than overselling:</p>
<ul>
  <li><strong>It stores links, not copies.</strong> bookmarker keeps the link, the title, the account and a
    thumbnail where one is published. Opening a save sends you to the original post in the app it came from. It
    is not an archive — if the original is deleted, the link dies with it.</li>
  <li><strong>Thumbnails and titles are only as good as the platform allows.</strong> YouTube and most ordinary
    web pages publish a title and an image. TikTok and X publish the caption or post text through their embed
    endpoints, which the iPhone app reads (TikTok with a cover image, X usually without). Instagram usually
    returns nothing to a request that is not logged in, so Instagram saves often arrive with a plain title and
    no image.</li>
  <li><strong>Search does not reach into the page behind the link.</strong> It matches what bookmarker holds:
    titles, accounts, tags, notes, topics, source and link, plus whatever post text came with the save — the
    description a page published, or the full post body when it arrived in an X data export. Nothing fetches the
    body of an article, a PDF or a video transcript, so none of that is indexed. There is no quoted-phrase
    operator — multiple words are treated as "all of these must appear".</li>
  <li><strong>No Android app.</strong> There is an iPhone app and a web app that runs in any modern browser.</li>
  <li><strong>Filing is only entirely on-device when you are signed out.</strong> The first pass runs on your
    phone and works offline. Signed in, every save you make by hand is also sent once to our server, which asks
    a language model for a topic — so the link, its title or caption, the account, hashtags and your tags leave
    the device. Your notes never do.</li>
</ul>

<h2>What it costs</h2>
<p>bookmarker is free on the App Store. Your first 20 saves work with no account at all. Past 20, saving asks
you to sign up — that is also free, an email address and a six-digit code — and signing up makes the library
unlimited, backs it up, and makes it readable on the web. There is no paid tier in the app and nothing in it
costs money. A one-time <a href="/lifetime">founding-member price of $30</a> is being reserved for a future
paid version; payments are not switched on, and no card is taken.</p>

<h2>Where to go next</h2>
<div class="cards">
  <a class="card" href="/app/"><h3>The iPhone app &rarr;</h3><p>Screens, the share sheet flow, import, privacy.</p></a>
  <a class="card" href="/faq"><h3>FAQ &rarr;</h3><p>Fifteen straight answers about accounts, search, privacy and limits.</p></a>
  <a class="card" href="/alternatives"><h3>Alternatives &rarr;</h3><p>An honest look at the other tools in this category.</p></a>
  <a class="card" href="/vs-twitter-bookmarks"><h3>vs X bookmarks &rarr;</h3><p>What a separate library adds over the one built into X.</p></a>
</div>

<p><a class="cta" href="/get/">Get bookmarker — free</a></p>
<span class="cta-sub">Free on the App Store, iOS 17 or later. Or use it in a browser at <a href="/">bookmarker.lol</a>.</span>
""")

# ───────────────────────────────── /faq ─────────────────────────────────
FAQ = [
 ("What is bookmarker?",
  """<p>bookmarker is a free bookmark manager for iPhone and the web. It collects everything you save on
  Instagram, X (Twitter), TikTok, YouTube and the open web into one library, files each save into a topic and
  subtopic automatically, and lets you search it later. A saved item is called a <strong>bork</strong>.</p>"""),
 ("Who is bookmarker for?",
  """<p>People who save a lot and lose it: hundreds or thousands of reels, threads, clips and articles spread
  across four or five apps, none of them searchable. If you have ever thought "I definitely saved that" and
  failed to find it, that is the audience.</p>"""),
 ("How much does bookmarker cost?",
  """<p>It is free on the App Store. The first 20 saves need no account. Past 20, saving asks you to sign up,
  which is also free — an email address and a six-digit code — and makes the library unlimited, backed up and
  readable on the web. There is no paid tier in the app and nothing in it costs money. A one-time
  <a href="/lifetime">founding-member price of $30</a> is being reserved for a future paid version; payments are
  not switched on yet and no card is taken.</p>"""),
 ("Which apps can I save from?",
  """<p>Any app with an iOS share sheet. bookmarker recognises Instagram, X (Twitter), TikTok, YouTube, YouTube
  Shorts, Threads, Pinterest and ordinary web pages, and labels each save with where it came from. On X, tap
  Share and then "Share via&hellip;" to reach the share sheet. You can also paste a link straight into the app
  or into the web app.</p>"""),
 ("Do I need an account?",
  """<p>Not to start. Everything works signed out for your first 20 saves, offline, on your phone. Signing in is
  free and does three things: removes the 20-save limit, backs the library up, and lets you open it on the web.
  There is no password to invent — you get a six-digit code by email.</p>"""),
 ("How does the automatic filing work?",
  """<p>The save always happens first; filing never holds it up. Then, on your device, bookmarker ranks its 50
  topics against the words in the link and the title or caption, and against where you have filed that creator
  or website before. That is instant and works offline and signed out.</p>
  <p>Straight after you save &mdash; from the share sheet, the + button, a pasted link or the web app's Add
  dialog &mdash; a dial shows the seven likeliest topics with the best guess in the middle. Tap one to file the
  save there, turn the dial to pick another, or leave it and the save is filed under the guess. Subtopics are
  one more tap.</p>
  <p>When you are signed in, every save you make by hand also gets an AI model's opinion once: bookmarker sends
  the link, its title or caption, the account, the hashtags and any tags you typed to its own server, which asks
  the model for a topic and subtopic and moves the dial when it answers. Its answer is weighed alongside the
  rest rather than taking over, low-confidence answers are dropped, and there is a daily allowance. Imported
  saves keep the older rule: only the ones the on-device pass is unsure about are sent, a few at a time. Signed
  out or offline you keep the on-device answer; your notes are never sent. The <a href="/privacy">privacy
  policy</a> sets this out in full.</p>
  <p>Anything unfiled, and any guess worth a second look, waits in <em>Sort your borks</em>: one card at a time,
  one tap each.</p>"""),
 ("What exactly can I search?",
  """<p>By default a search looks at the title, the account that posted it, your tags, your notes, the topic and
  subtopic, the source app, the link itself, and whatever post text bookmarker holds &mdash; the description a
  page published, or the full post body when the save came in from an X data export. You can narrow a search to
  topics, subtopics or tags only. Several words are treated as "all of these must appear somewhere"; there is no
  quoted-phrase or operator syntax.</p>
  <p>What it does not promise is the whole document behind the link. bookmarker never fetches the body of an
  article, a PDF or a video transcript, so a phrase that appears only deep inside the thing you saved will not
  be found.</p>"""),
 ("Does bookmarker work offline?",
  """<p>Yes. The iPhone library lives on your iPhone, and browsing, searching, saving a pasted link and the keyword
  filing all work with no connection. Fetching a title or a thumbnail needs the network, as does the AI model's
  opinion on where a save belongs, so those parts fill in when you are back online.</p>"""),
 ("Does bookmarker copy the posts I save?",
  """<p>No. It stores the link, the title, the account and a thumbnail where the platform publishes one. Opening
  a save sends you to the original post in the app it came from. That means bookmarker is not an archive: if the
  original is deleted, the link stops working.</p>"""),
 ("Will I get thumbnails for Instagram, TikTok and X saves?",
  """<p>It depends on the platform, and it is worth being straight about why. YouTube and most ordinary web pages
  publish the title, author and image that bookmarker reads. TikTok and X publish the caption or post text and
  the creator through documented embed endpoints, which the iPhone app reads &mdash; TikTok with a cover image, X
  usually without. Instagram generally returns nothing to a request that is not logged in, so Instagram saves
  often arrive with a plain title taken from the link, and no image. The save, the filing and the search all
  still work.</p>"""),
 ("Can I import the saves I already have?",
  """<p>Yes. bookmarker imports browser bookmarks and the data export files from Instagram (your saved posts and
  collections), TikTok (favourites and likes), X (bookmarks and likes), YouTube (playlists, including Watch later,
  from Google Takeout), and in the web app Pinterest too. On a computer, drop the whole .zip into the web app's importer; you do not
  need to unzip it. A few thousand old saves become one library in a single pass instead of being re-saved one at
  a time. An export carries the link and usually the date you saved it; Instagram's also names the account, and X's likes
  file carries the post text. Titles, captions and thumbnails fill in afterwards where the platform publishes
  them.</p>"""),
 ("What happens if I save the same link twice?",
  """<p>You get one bork, not two. bookmarker normalises every URL before storing it — lowercases the host,
  strips <code>www.</code> and <code>m.</code>, drops tracking parameters such as <code>utm_*</code>,
  <code>igshid</code>, <code>si</code> and <code>fbclid</code>, and removes trailing slashes — so the same post
  shared from two places, or shared once and pasted once, collides into a single save.</p>"""),
 ("Can I share my saves with someone?",
  """<p>Yes. Pick a set of saves and bookmarker turns them into a page at <code>bookmarker.lol/c/&hellip;</code>
  you can send to anyone, no account needed to read it. You choose whether the link lasts forever, one day or
  ten days, and you can switch it off afterwards. Everything else in your library stays private.</p>"""),
 ("Is there an Android or desktop app?",
  """<p>There is no Android app. There is a native iPhone app (iOS 17 or later) and a web app at
  <a href="/">bookmarker.lol</a> that runs in any modern browser, including on Android and on a desktop, once
  you have signed in.</p>"""),
 ("Does bookmarker track me?",
  """<p>The iPhone app asks for zero permissions and ships with no ad or analytics SDKs; your library is on your
  device. This website uses PostHog for product analytics and session replay with inputs masked, which the
  <a href="/privacy">privacy policy</a> discloses. Your saves are never sold and are not visible to anyone else
  unless you deliberately share a collection.</p>"""),
]

faq_body = """
<h1>bookmarker FAQ</h1>
<p class="meta">Last updated: """ + UPDATED + """</p>
<p class="intro">Straight answers about bookmarker — the free bookmark manager for iPhone and the web that puts
everything you save on Instagram, X, TikTok and YouTube into one searchable library. If something you need is
not here, email <a href="mailto:hello@bookmarker.lol">hello@bookmarker.lol</a>.</p>
""" + "\n".join(
    f'<section class="qa">\n<h2>{q}</h2>\n{a.strip()}\n</section>' for q, a in FAQ) + """

<p><a class="cta" href="/get/">Get bookmarker — free</a></p>
<span class="cta-sub">Free on the App Store, iOS 17 or later. See also
<a href="/what-is-bookmarker">what bookmarker is</a>, the
<a href="/alternatives">alternatives</a>, and <a href="/vs-twitter-bookmarks">how it compares to X bookmarks</a>.</span>
"""

import html as _html, re as _re
def _plain(h):
    """The visible answer as plain text for the JSON-LD. Entities are unescaped
    first: a structured answer reading "Share via&hellip;" is a raw entity in
    the data, not an ellipsis."""
    return _re.sub(r"\s+", " ", _html.unescape(_re.sub(r"(?s)<[^>]+>", " ", h))).strip()

write("/faq",
      "bookmarker FAQ — accounts, search, privacy and limits",
      "Answers to 15 real questions about bookmarker: what it costs, which apps you can save from, what search "
      "covers, whether it works offline, and what it deliberately does not do.",
      crumb="FAQ",
      ogtype="website",
      jsonld=[{
          "@context": "https://schema.org",
          "@type": "FAQPage",
          "url": SITE + "/faq",
          "inLanguage": "en",
          "mainEntity": [
              {"@type": "Question", "name": q,
               "acceptedAnswer": {"@type": "Answer", "text": _plain(a)}}
              for q, a in FAQ
          ],
      }, APP_LD, breadcrumb("FAQ", "/faq")],
      body=faq_body)
