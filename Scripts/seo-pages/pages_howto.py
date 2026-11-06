# -*- coding: utf-8 -*-
# tpl.py is the sibling module; running this file puts its own directory on
# sys.path, so no path juggling is needed.
from tpl import *

def howto(name, desc, steps, path):
    return {
        "@context": "https://schema.org",
        "@type": "HowTo",
        "name": name,
        "description": desc,
        "url": SITE + path,
        "inLanguage": "en",
        "step": [{"@type": "HowToStep", "position": i + 1, "name": s[0], "text": s[1],
                  "url": SITE + path + "#step-" + str(i + 1)}
                 for i, s in enumerate(steps)],
    }

XNOTE = """<div class="callout"><p>X's own bookmark features change, and some of them (folders, for example) have
been limited to paid X Premium tiers. Check X's current help pages before assuming what your account can do. The
method below does not depend on which tier you are on.</p></div>"""

# ───────── /how-to-organize-twitter-bookmarks ─────────
ORG_STEPS = [
 ("Get bookmarker", "Install bookmarker free from the App Store (iOS 17 or later), or open the web app at bookmarker.lol. Your first 20 saves work with no account."),
 ("Save a post from X", "In X, tap Share on the post, then “Share via…” to reach the iOS share sheet, and pick bookmarker. Pin bookmarker to the front of the share sheet once — More → Edit → add to Favourites — and it is the first icon from then on."),
 ("File it in one tap", "The save happens at once. Then a dial shows the seven likeliest topics, with the best guess in the middle: tap to file it there, such as Fitness › Mobility, turn the dial to pick another, or leave it and the guess stands. Signed in, an AI model also reads the post and suggests a topic and subtopic. Saving is never blocked by filing."),
 ("Bring your existing bookmarks in", "Request your X data archive (X Settings → Your account → Download an archive of your data), then import the file into bookmarker so your old saves are filed too."),
 ("Browse by topic instead of scrolling", "Open Browse and pick a topic to see everything on that subject from every app, or switch the axis to browse by source app. Add tags for one-off projects, and a dated note when you want to remember why you kept something."),
]

write(
    "/how-to-organize-twitter-bookmarks",
    "How to organise your X (Twitter) bookmarks in 2026",
    "X bookmarks are one long list with no topics. Here is a practical method for organising them by subject, "
    "including importing the X bookmarks you already have.",
    crumb="How to organise your X bookmarks",
    ogtype="article",
    jsonld=[breadcrumb("How to organise your X bookmarks", "/how-to-organize-twitter-bookmarks"),
            howto("How to organise your X (Twitter) bookmarks",
                  "Save X posts into a library that files each one into a topic automatically, and import the X bookmarks you already have.",
                  ORG_STEPS, "/how-to-organize-twitter-bookmarks"),
            article("How to organise your X (Twitter) bookmarks",
                    "A practical method for getting hundreds of saved X posts into topics you can browse.",
                    "/how-to-organize-twitter-bookmarks"),
            APP_LD],
    body="""
<h1>How to organise your X (Twitter) bookmarks</h1>
<p class="meta">Last updated: """ + UPDATED + """</p>

<p class="intro">If you have saved hundreds of posts on X and cannot find any of them, the problem is not you —
it is that a reverse-chronological list with no titles and no subjects is not an organisational system. This page
covers the realistic options, and then the method we think works: let something file each save into a topic as it
arrives, instead of trying to tidy the pile later.</p>

""" + XNOTE + """

<h2>Why the bookmark list goes bad</h2>
<p>Three things compound. The list is ordered by when you saved, but you remember what something was
<em>about</em>. Nothing in it has a useful title, so scanning does not work. And it only holds X, so the other
half of what you saved on the same subject is sitting in Instagram or YouTube where this list cannot see it. A
hundred saves is browsable. A thousand is a landfill.</p>

<h2>Your options, honestly</h2>
<h3>Manual folders inside X</h3>
<p>If your account has bookmark folders, they work, and for a small number of broad buckets they are the least
effort. The catch is that they are manual, they only cover X, and every new save is a decision you have to make.</p>
<h3>Copy posts into a notes app</h3>
<p>Screenshotting into Apple Notes, Notion or Obsidian gives you full control and good search of your own words.
It is also slow, and you lose the live link back to the post, the replies and the author.</p>
<h3>Export to a spreadsheet</h3>
<p>You can request your X archive and search the bookmarks file in a spreadsheet. It is a snapshot — it does not
update, and it is unusable on a phone.</p>
<h3>A library that files saves for you</h3>
<p>The option with the least ongoing effort: save through a tool that assigns a subject at save time, so the
organising has already happened by the time you want to find something. That is what bookmarker does, and it is
the method below.</p>

<h2>The method, step by step</h2>
<ol>
""" + "\n".join(
    f'  <li id="step-{i+1}"><strong>{t}.</strong> {b}</li>' for i, (t, b) in enumerate(ORG_STEPS)) + """
</ol>

<h2>Why topics beat folders</h2>
<p>Folders are a decision per save, made from a blank list. Topics are a decision made for you: bookmarker
ranks its 50 topics and 612 subtopics against the words in the link and the post, and against where you filed
that account before, and offers the best seven on a dial the moment you save. Confirming takes one tap; ignoring
it keeps the guess. With a couple of thousand saves that is the difference between a system you keep up with and
one you abandon in week two.</p>
<p>The first pass runs on your device, instantly and offline. When you are signed in, every save you make by hand
also goes once to bookmarker's server, which asks a language model to read the post text and suggest a topic and
subtopic; its answer is weighed with the rest, and answers it is not confident about are dropped. Signed out or
offline, the on-device answer is the only answer. X posts with very little text are the hard case, so expect to
correct some — it takes one tap, and bookmarker remembers where you file each account. Anything left unfiled
waits in <em>Sort your borks</em>, one card at a time.</p>

<h2>Tags for the things topics cannot know</h2>
<p>Topics handle subjects. Tags handle projects: tag everything you save for a specific conference, trip or client
and pull the set back instantly. A dated note on a save is for the other half of the problem — remembering
<em>why</em> you kept it.</p>

<h2>Organise across apps, not just X</h2>
<p>The point of all this only lands when the library holds more than X. Your Instagram recipe reel and your X
recipe thread belong in the same place, and in bookmarker they are both in Recipes, each still labelled with the
app it came from, so you can filter by source when you want to.</p>

<h2>What this will not fix</h2>
<p>bookmarker stores links, not copies: if a post is deleted, the link dies. And X saves usually arrive with the
post text but no thumbnail, because X's embed endpoint, which the iPhone app reads, does not include an image. The filing, the notes and the
search all still work; the card just looks plainer than a YouTube one.</p>

<p><a class="cta" href="/get/">Get bookmarker — free</a></p>
<span class="cta-sub">Next: <a href="/how-to-search-twitter-bookmarks">how to search your X bookmarks</a>, or
<a href="/vs-twitter-bookmarks">how a library compares to X's own bookmarks</a>.</span>
""")

# ───────── /how-to-search-twitter-bookmarks ─────────
SEARCH_STEPS = [
 ("Get bookmarker", "Install bookmarker free from the App Store (iOS 17 or later) or open the web app at bookmarker.lol."),
 ("Save X posts through it", "In X, tap Share, then “Share via…”, then bookmarker. The link, the title where X publishes one, the account and the source app are recorded, and the save is filed into a topic."),
 ("Import the bookmarks you already have", "Request your X archive under X Settings → Your account → Download an archive of your data, then import the file so your existing saves become searchable too."),
 ("Search your library", "Type a word into the search field. bookmarker matches the title, the account that posted it, your tags, your notes, the topic and subtopic, the source app, the link, and any description text the page published."),
 ("Narrow it when a word is too common", "Tap the Topics, Subtopics or Tags chips to restrict a search to those fields, or filter the results by source app to see only X."),
]

write(
    "/how-to-search-twitter-bookmarks",
    "How to search your X (Twitter) bookmarks",
    "How to get searchable X bookmarks: the export-to-spreadsheet route, and the quicker one — a library that "
    "indexes the title, account, tags, notes and topic of every save.",
    crumb="How to search your X bookmarks",
    ogtype="article",
    jsonld=[breadcrumb("How to search your X bookmarks", "/how-to-search-twitter-bookmarks"),
            howto("How to search your X (Twitter) bookmarks",
                  "Make your saved X posts searchable by keeping them in a library that records the title, account, tags, notes and topic of each save.",
                  SEARCH_STEPS, "/how-to-search-twitter-bookmarks"),
            article("How to search your X (Twitter) bookmarks",
                    "Practical ways to find a saved X post again, and what each method can and cannot match.",
                    "/how-to-search-twitter-bookmarks"),
            APP_LD],
    body="""
<h1>How to search your X (Twitter) bookmarks</h1>
<p class="meta">Last updated: """ + UPDATED + """</p>

<p class="intro">Saved a good post weeks ago and cannot find it? The reason is that X's search box searches X, not
your saves, and scrolling a long bookmark list is not searching. This page covers the two methods that actually
work — exporting your archive, and keeping saves in a library built to be searched — and is specific about what
each one can and cannot match.</p>

""" + XNOTE + """

<h2>Why scrolling fails</h2>
<p>A bookmark list is ordered by when you saved. You remember what something was about, who posted it, or roughly
what it looked like — almost never the date. So the one axis the list gives you is the one axis you cannot use,
and with a few hundred saves the only honest strategy left is luck.</p>

<h2>Method 1: export your X archive and search the file</h2>
<ol>
  <li>Open X &rarr; Settings &rarr; Your account &rarr; Download an archive of your data.</li>
  <li>Wait for X to prepare it — this can take a day.</li>
  <li>Download the archive and unzip it.</li>
  <li>Open the bookmarks data file and search it in a spreadsheet or text editor.</li>
</ol>
<p><strong>What it is good for:</strong> a one-off hunt, and it costs nothing. <strong>What it is bad for:</strong>
it is a snapshot that never updates, it is awkward on a phone, and you have to re-export to catch anything new.</p>

<h2>Method 2: keep your saves in a library you can search</h2>
<p>The method with no maintenance: save through something that records the useful fields at save time, so finding
is a search rather than an excavation. bookmarker is free, works from the X share sheet, and holds your Instagram,
TikTok and YouTube saves in the same place.</p>
<ol>
""" + "\n".join(
    f'  <li id="step-{i+1}"><strong>{t}.</strong> {b}</li>' for i, (t, b) in enumerate(SEARCH_STEPS)) + """
</ol>

<h2>Exactly what bookmarker's search matches</h2>
<p>Worth spelling out, because "full-text search" gets claimed loosely in this category. A bookmarker search looks
at:</p>
<ul>
  <li>the title of the save;</li>
  <li>the account or handle that posted it;</li>
  <li>your tags;</li>
  <li>your notes;</li>
  <li>the topic and subtopic it was filed into;</li>
  <li>the source app;</li>
  <li>the link itself;</li>
  <li>and whatever post text bookmarker holds — the caption or post text TikTok and X publish through their embed
    endpoints (read by the iPhone app), the description an ordinary page published, or the full post body when the
    save arrived in an X likes export. Instagram usually provides none.</li>
</ul>
<p>What it does <strong>not</strong> do is open the page behind the link. The body of an article, a PDF or a
video transcript is never fetched, so none of it is searchable, and there is no quoted-phrase or operator syntax:
typing several words means "every one of these must appear somewhere". If you need search that reaches inside
saved page content, <a href="/vs-raindrop">Raindrop.io</a> does that and we say so on the comparison page. If you
want a full, lasting copy of your X posts rather than the text an export happens to carry,
<a href="/vs-twillot">Twillot</a> archives them.</p>

<h2>Getting more out of a search</h2>
<h3>Search the word you would use for the subject</h3>
<p>Because every save is filed into a topic and subtopic, the subject word usually hits even when the title is
useless — searching "mobility" finds things filed under Fitness &rsaquo; Mobility whose titles never said it.</p>
<h3>Scope the search when a word is everywhere</h3>
<p>A query like "running" matches eleven titles as loudly as the topic you actually filed things under. Tapping
the Topics, Subtopics or Tags chips restricts the match to those fields, which is usually the fix.</p>
<h3>Filter by the app it came from</h3>
<p>If you know you saved it on X, filter the results by source and the list collapses to a handful.</p>
<h3>Give future-you something to search for</h3>
<p>A tag or a one-line dated note at save time is the single highest-leverage habit here — those are your words,
so they are the words you will search for.</p>

<h2>Why author search is not the answer</h2>
<p>Searching X for the person who posted it only works if you remember who they were, they have not deleted the
post, and they have not posted a thousand times since. Most of the time you remember the content, not the author.
X's advanced search operators have the same limit: they search all of X, not your saves.</p>

<p><a class="cta" href="/get/">Get bookmarker — free</a></p>
<span class="cta-sub">Next: <a href="/how-to-organize-twitter-bookmarks">how to organise your X bookmarks</a>, or
read the <a href="/faq">FAQ</a>.</span>
""")

# ───────── /how-to-organize-instagram-saved-posts ─────────
IG_STEPS = [
 ("Get bookmarker", "Install bookmarker free from the App Store (iOS 17 or later), or open the web app at bookmarker.lol. Your first 20 saves work with no account."),
 ("Share a post from Instagram", "On the post or reel, tap the Share (paper plane) button and choose the option that opens the iPhone share sheet, then pick bookmarker. Or tap Copy link and paste it into bookmarker. Pin bookmarker to the front of the share sheet once — More → Edit → add to Favorites — and it is the first icon from then on."),
 ("File it in one tap", "The save happens at once. A dial then offers the seven likeliest topics with the best guess in the middle: tap to file it, turn the dial to pick another, or leave it and the guess stands. Signed in, an AI model also suggests a topic and subtopic."),
 ("Bring in the posts you already saved", "Request your Instagram data (Settings → Accounts Centre → Your information and permissions → Download your information, in JSON format), then drop the .zip into the web app's importer, or import the saved_posts.json inside it on iPhone."),
 ("Sort the imported pile", "Imported Instagram saves arrive with the account and the date but no caption, so many need a topic. Open Sort your borks and file them one card at a time; bookmarker remembers where you put each account, so the next post from them is suggested first."),
]

write(
    "/how-to-organize-instagram-saved-posts",
    "How to organise your Instagram saved posts (and find them again)",
    "Instagram's Saved tab is one long grid plus collections you sort by hand. Here is how to file saved posts "
    "and reels by topic, import the ones you already have, and search them.",
    crumb="How to organise your Instagram saved posts",
    ogtype="article",
    jsonld=[breadcrumb("How to organise your Instagram saved posts", "/how-to-organize-instagram-saved-posts"),
            howto("How to organise your Instagram saved posts",
                  "File Instagram posts and reels by topic as you save them, import the saved posts you already have, and sort the rest one tap at a time.",
                  IG_STEPS, "/how-to-organize-instagram-saved-posts"),
            article("How to organise your Instagram saved posts",
                    "Instagram's own Saved collections, what they are good at, and a method for filing saved posts by topic across apps.",
                    "/how-to-organize-instagram-saved-posts"),
            APP_LD],
    body="""
<h1>How to organise your Instagram saved posts</h1>
<p class="meta">Last updated: """ + UPDATED + """</p>

<p class="intro">If you tap the bookmark icon on Instagram several times a day, your Saved tab is probably hundreds
of reels and posts deep, and finding the one recipe or workout you meant to come back to means scrolling. This page
covers what Instagram's own collections do well, where they stop, and a method that files each save by topic as you
make it — including the posts you saved years ago.</p>

<div class="callout"><p>Instagram changes its menus often. The paths below were right when this page was updated;
if a label has moved, the same option is usually one screen away.</p></div>

<h2>What Instagram gives you: Saved and collections</h2>
<p>Every post you bookmark goes into <strong>Saved</strong> (your profile &rarr; the menu &rarr; Saved), ordered by
when you saved it. You can create <strong>collections</strong> and add posts to them, either as you save or
afterwards. For a handful of broad buckets — "Recipes", "Trips" — that works, it costs nothing, and the posts stay
inside Instagram where they play best.</p>
<p>Where it stops:</p>
<ul>
  <li><strong>Every post is a manual decision.</strong> Collections only fill when you file into them, so most
    people stop after the first week and the "All posts" grid keeps growing.</li>
  <li><strong>It only holds Instagram.</strong> The TikTok, YouTube and X saves about the same subject live in three
    other apps.</li>
  <li><strong>It is built for scrolling, not finding.</strong> The grid shows covers, and you remember what a post
    was about, not when you saved it.</li>
</ul>

<h2>The method: file by topic as you save</h2>
<p>The approach with the least ongoing effort is to save through something that suggests the subject at save time,
so the organising has already happened when you come looking. bookmarker is free, takes posts from Instagram's share
button, and keeps them next to everything you save from other apps.</p>
<ol>
""" + "\n".join(
    f'  <li id="step-{i+1}"><strong>{t}.</strong> {b}</li>' for i, (t, b) in enumerate(IG_STEPS)) + """
</ol>

<h2>Importing years of saved posts</h2>
<p>Instagram will hand you a copy of your data. Ask for it in <strong>JSON</strong>, not HTML: the email can take
anywhere from a few minutes to a couple of days, and the download link expires after a few days, so grab it when it
lands. In the bookmarker web app on a computer you can drop the whole .zip in without unzipping it; the importer
finds <code>saved_posts.json</code> (and your collections) inside. On iPhone, unzip it and import <code>saved_posts.json</code> from the app.</p>
<p>Be clear about what the export contains: the link to each post, the account that posted it and the date you
saved it. It does not contain captions or images, and Instagram does not publish them to an app that is not logged
in, so imported posts arrive as plain cards with the account name. That is why the last step above matters:
<em>Sort your borks</em> shows anything without a topic one card at a time, and because bookmarker learns where you
file each account, a creator you have filed three times is suggested first from then on.</p>

<h2>Finding a saved post again</h2>
<p>Once a post is in bookmarker you can find it by:</p>
<ul>
  <li>the topic and subtopic it is filed under — Recipes &rsaquo; Meal prep, Fitness &rsaquo; Mobility;</li>
  <li>the account that posted it;</li>
  <li>any tag or dated note you added — the single best habit, because those are your own words;</li>
  <li>the source app, to see only what came from Instagram;</li>
  <li>and the link and title.</li>
</ul>
<p>Search does not see inside the post. For Instagram that matters more than for other apps: there is usually no
caption to search, so the topic, the account and your own tags do the work. If you want the words of a reel to be
searchable, add a short note when you save it.</p>

<h2>Topics beat collections across apps</h2>
<p>The reason to organise outside Instagram is that your interests are not split by app. A mobility routine saved
on Instagram, a stretching video on YouTube and a thread on X all belong in Fitness &rsaquo; Mobility. In bookmarker
they sit together, each still labelled with the app it came from, and opening one sends you straight back to the
original post in Instagram.</p>

<h2>What this will not do</h2>
<p>bookmarker stores links, not copies. If a creator deletes a post or makes their account private, the link stops
working — it is a library, not an archive. It does not download reels, and it cannot reach into Instagram and pull
your Saved list down by itself; the data export is the way to bring that across. There is no Android app, though
the web app runs in any browser.</p>

<p><a class="cta" href="/get/">Get bookmarker — free</a></p>
<span class="cta-sub">Next: <a href="/how-to-search-tiktok-favorites">how to search your TikTok favourites</a>, the
<a href="/faq">FAQ</a>, or the <a href="/alternatives">alternatives</a>.</span>
""")

# ───────── /how-to-search-tiktok-favorites ─────────
TT_STEPS = [
 ("Get bookmarker", "Install bookmarker free from the App Store (iOS 17 or later), or open the web app at bookmarker.lol."),
 ("Share TikToks to bookmarker", "On a video, tap Share, then the option that opens the iPhone share sheet, and pick bookmarker. Or tap Copy link and paste it in. On iPhone, bookmarker reads the caption and the creator from TikTok's public embed endpoint, so the caption, hashtags included, becomes searchable."),
 ("File it in one tap", "A dial offers the seven likeliest topics with the best guess in the middle; one tap files it, or leave it and the guess stands. Signed in, an AI model reads the caption and suggests a topic and subtopic."),
 ("Import your existing favourites", "Request your TikTok data (Settings → Account → Download your data, in JSON format), then drop the .zip into the web app's importer, or import the user_data.json inside it on iPhone. Favourites and liked videos both come across, with the date you saved each one."),
 ("Search", "Type a word from the caption, a hashtag, the creator, a tag or a note, or pick a topic. Tap the Topics, Subtopics or Tags chips to narrow a common word, and filter by source to see only TikTok."),
]

write(
    "/how-to-search-tiktok-favorites",
    "How to search your TikTok favourites (saved videos)",
    "TikTok's Favorites tab is a grid you scroll, and its search box searches all of TikTok. Here is how to make "
    "saved TikToks searchable by caption, creator and topic, and import the favourites you already have.",
    crumb="How to search your TikTok favourites",
    ogtype="article",
    jsonld=[breadcrumb("How to search your TikTok favourites", "/how-to-search-tiktok-favorites"),
            howto("How to search your TikTok favourites",
                  "Keep saved TikToks in a library that records the caption, creator and topic of each one, and import the favourites you already have.",
                  TT_STEPS, "/how-to-search-tiktok-favorites"),
            article("How to search your TikTok favourites",
                    "Why saved TikToks are hard to find again, and a practical way to search them by caption, creator and topic.",
                    "/how-to-search-tiktok-favorites"),
            APP_LD],
    body="""
<h1>How to search your TikTok favourites</h1>
<p class="meta">Last updated: """ + UPDATED + """</p>

<p class="intro">You saved the video — the pasta recipe, the shoulder exercise, the tip about renting a car abroad —
and now you cannot find it. TikTok's Favorites tab is a grid of covers ordered by when you saved them, and the search
bar at the top of the app searches all of TikTok, not your saves. This page covers what TikTok offers, the export
route, and a way to keep saved TikToks somewhere you can actually search.</p>

<div class="callout"><p>TikTok's menus change between versions. The paths below were right when this page was
updated; if a label has moved, the same option is usually close by.</p></div>

<h2>What TikTok gives you</h2>
<p>Tap the bookmark icon on a video and it goes into <strong>Favorites</strong> on your profile. You can make
<strong>collections</strong> there and move videos into them by hand. That is the whole system: no topics unless you
make them, and finding one video usually means scrolling covers. With a few dozen favourites, that works. With a
few hundred it does not.</p>

<h2>Method 1: download your data and search the file</h2>
<ol>
  <li>In TikTok, go to Settings &rarr; Account &rarr; Download your data.</li>
  <li>Choose <strong>JSON</strong> and request the file; TikTok tells you when it is ready.</li>
  <li>Open <code>user_data.json</code> and look under your activity for the favourite videos list.</li>
</ol>
<p><strong>What you get:</strong> a link and a date for every favourite and liked video. <strong>What you do not
get:</strong> captions, titles or creators — so you can find "something I saved on 3 May", but not "the pasta one".
It is a snapshot, too, and does not update.</p>

<h2>Method 2: keep saved TikToks in a library you can search</h2>
<p>bookmarker is free and takes TikToks from the share button. On iPhone it reads each video's caption and creator
from TikTok's public embed endpoint — no login, nothing scraped — so the words people actually write in a caption,
hashtags included, become searchable, and the video's cover becomes the card.</p>
<ol>
""" + "\n".join(
    f'  <li id="step-{i+1}"><strong>{t}.</strong> {b}</li>' for i, (t, b) in enumerate(TT_STEPS)) + """
</ol>

<h2>What you can search, exactly</h2>
<ul>
  <li>the caption, which becomes the save's title, hashtags included (videos shared from the iPhone app);</li>
  <li>the creator;</li>
  <li>the topic and subtopic the video is filed under;</li>
  <li>your tags and dated notes;</li>
  <li>the source app and the link.</li>
</ul>
<p>Several words mean "all of these must appear". What search does <strong>not</strong> cover is what is said or
shown in the video: bookmarker never fetches a transcript and does not download videos.</p>

<h2>A word on imported favourites</h2>
<p>An imported favourite arrives with what TikTok's export holds: the link and the date. Many export links are short
share links with no creator in them, so imported favourites usually start as plain cards with no caption. They are
still in your library and open straight in TikTok — and <em>Sort your borks</em> walks you through anything
without a topic, one tap per card. For the ones you care about, a quick tag or note makes them as findable as a
fresh save.</p>

<h2>Tips that make the difference</h2>
<h3>Search the subject, not the words you half-remember</h3>
<p>Because every save is filed into a topic, searching "mobility" finds videos filed under Fitness &rsaquo;
Mobility even when the caption was a string of emoji.</p>
<h3>Put TikTok next to everything else</h3>
<p>The recipe you saved on TikTok and the one you saved on Instagram belong in the same place. In bookmarker both
sit in Recipes, each labelled with its app, and opening either sends you back to the original.</p>
<h3>Add a note for the ones that matter</h3>
<p>A one-line dated note — "the garlic one", "do this before runs" — is the most reliable thing you can search
for later, because it is in your words.</p>

<h2>What this will not do</h2>
<p>bookmarker keeps links, not copies: if a video is deleted or made private, the link stops working. It does not
download TikToks or remove watermarks, and it cannot read your Favorites list on its own — the export is the way to
bring that across. There is no Android app, but the web app runs in any browser.</p>

<p><a class="cta" href="/get/">Get bookmarker — free</a></p>
<span class="cta-sub">Next: <a href="/how-to-organize-instagram-saved-posts">how to organise your Instagram saved
posts</a>, the <a href="/faq">FAQ</a>, or the <a href="/alternatives">alternatives</a>.</span>
""")
