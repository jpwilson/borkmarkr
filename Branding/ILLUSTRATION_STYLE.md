# bookmarker clay illustration — locked style

Use this prompt for **every** new scene. Do not invent a second look.

Locked masters (never regenerate, never restyle):

- `questRabbit` — Go down the rabbit hole
- `questBusiness` — Explore starting a business
- `questRun` — Improve mobility for running
- `questMarket` — Marketing on socials

Also keep `questCook`, `questLearn`, `questCreate`, `questMoney`,
`questCompass`, `questScroll` unless a specific scene is rejected.

## Style lock prompt

Soft clay-3D editorial illustration for the iOS app bookmarker. Isolated
subject, centered, generous cream paper background exactly #F6F3EE. Rounded
friendly forms like a collectible toy or premium sticker. Gentle studio
lighting, a small contact shadow under the object only. Palette: muted coral,
sage, warm brown, terracotta, cream. No text, no letters, no numbers, no
watermark, no frame, no logo, no drop shadow behind the whole canvas. One
clear subject, generous margin.

When generating a new scene, **image_edit from `questRabbit`** and replace
only the subject. Do not start from a blank `image_gen` — independent
generations drift.

## Rules

- No words on the object (no “OPEN”, no book titles).
- Do not redraw the four locked quest scenes.
- Every topic has its own `topic{Id}` imageset. Never share a scene across
  two topics. Never use a quest asset (`questRabbit`, `questRun`, …) on a topic.
- Wordmark lives in type (Bricolage Grotesque), never in the bitmap.

## Topics people add themselves

The 50 built-ins are drawn here, by hand, and bundled. A topic a user invents
cannot be — so it is drawn on demand by the `topic-art` Edge Function, which
`image_edit`s from `questRabbit` exactly as above.

**This file is the source of truth for the style; the machine copy lives in
`supabase/functions/_shared/openai.ts` (`STYLE` and `clayPrompt`).** They are
the same words on purpose. Change the look here and change it there in the
same commit, or new topics quietly stop matching the wall.

The one-scene-per-topic rule holds for generated art too: the ledger in
`supabase/migrations/0010_topic_art.sql` is keyed per topic, so a topic is
drawn once and keeps that scene.
