# bookmarker brand assets

- `share-card.png` / `share-card@2x.png` — 1200×630 share card (live as `/img/share.jpg`, used for og:image / twitter:image on every page).
- `share-square.png` — 1080×1080 social variant (live as `/img/share-square.jpg`).
- `hero-bookmark.png` — the clay bookmark with the four platform tiles, no copy (live as `/img/hero-bookmark.jpg`, signed-out hero on bookmarker.lol).
- `clay-concepts/` — the generated clay bookmark explorations. `e_sockets_1` is the one in use; the others (ribbon, stack, 3D icon, pocket) are spare art for posts.
- `share-card-src/` — the HTML that renders the cards. Regenerate with:
  `"/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" --headless=new --disable-gpu --hide-scrollbars --allow-file-access-from-files --window-size=1200,630 --screenshot=out.png file://$PWD/card.html`
  (`square.html` at 1080×1080, `hero.html` at 900×900; add `--force-device-scale-factor=2` for @2x.)

Platform logos are the official shapes from Simple Icons (CC0), in brand colours; the base art is a generated clay render — bookmarker owns it.
Colours: paper #F6F3EE · ink #191510 · coral #FF5A2D · card bg #E6DBC6. Type: Bricolage Grotesque 800 (headlines), Instrument Sans (body).
