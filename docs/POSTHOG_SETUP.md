# PostHog Analytics Setup for bookmarker.lol

This document explains how to configure PostHog analytics for the bookmarker.lol website.

## Overview

PostHog analytics is now configured to read from environment variables instead of being hardcoded. This allows you to:

- Keep your PostHog API key secure and out of the repository
- Easily change the key without modifying code
- Run the site locally without analytics (useful for development)

## What's Tracked

PostHog automatically tracks:
- **Page views** - All page loads across the site
- **Referrers** - Where visitors come from (including chatgpt.com, perplexity.ai, etc.)
- **Session data** - User sessions and paths through the site

You can also track custom events using the `window.bookmarkerAnalytics` helper:
- `trackSignUp(method)` - User signs up
- `trackSignIn(method)` - User signs in
- `trackBookmarkSaved(source, category)` - Bookmark is saved
- `trackSearch(query)` - User performs a search (query length only, not content)

## Privacy & Compliance

✅ **No PII** - Only anonymous user IDs are tracked, no email/name/personal data
✅ **Form inputs not recorded** - Input masking is enabled
✅ **Search privacy** - Only search length tracked, not actual query text
✅ **Opt-out available** - Internal devices can opt out via `?internal=1`

## Setup Instructions

### For GitHub Pages Deployment

Since GitHub Pages serves static HTML files, you have two options:

#### Option 1: Commit the config file (Quick, less secure)

1. Edit `/docs/posthog-config.js`
2. Set your PostHog API key in the `apiKey` field:
   ```javascript
   window.__POSTHOG_CONFIG__ = {
     apiKey: 'phc_YOUR_ACTUAL_KEY_HERE',
     apiHost: 'https://us.i.posthog.com',
     options: {
       defaults: '2025-05-24'
     }
   };
   ```
3. Commit and push

**Note:** This puts your API key in the repository. PostHog project keys are designed to be public (they're in the browser anyway), but you may prefer the GitHub Actions approach below.

#### Option 2: Use GitHub Actions (Recommended, more secure)

1. **Add PostHog key as a GitHub secret:**
   - Go to your repo: Settings → Secrets and variables → Actions
   - Click "New repository secret"
   - Name: `POSTHOG_KEY`
   - Value: Your PostHog API key (e.g., `phc_o34s8vv6TWjzDemdh39CAW8d4R52qFzVt2RZCnQEEKqx`)

2. **Create a GitHub Actions workflow** (`.github/workflows/deploy-pages.yml`):

```yaml
name: Deploy to GitHub Pages

on:
  push:
    branches: [main]
  workflow_dispatch:

permissions:
  contents: read
  pages: write
  id-token: write

jobs:
  build-and-deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      
      - name: Generate PostHog config
        env:
          POSTHOG_KEY: ${{ secrets.POSTHOG_KEY }}
        run: |
          cat > docs/posthog-config.js << 'EOF'
          window.__POSTHOG_CONFIG__ = {
            apiKey: '${{ secrets.POSTHOG_KEY }}',
            apiHost: 'https://us.i.posthog.com',
            options: {
              defaults: '2025-05-24'
            }
          };
          EOF
      
      - name: Setup Pages
        uses: actions/configure-pages@v4
      
      - name: Upload artifact
        uses: actions/upload-pages-artifact@v3
        with:
          path: docs
      
      - name: Deploy to GitHub Pages
        uses: actions/deploy-pages@v4
```

3. **Update GitHub Pages settings:**
   - Go to Settings → Pages
   - Source: "GitHub Actions"

### For Cloudflare Pages Deployment

If you decide to use Cloudflare Pages instead:

1. **Add environment variable in Cloudflare:**
   - Dashboard → Pages → Your Project → Settings → Environment Variables
   - Variable name: `POSTHOG_KEY`
   - Value: Your PostHog API key

2. **Add a build script** that generates the config file during deployment.

### Testing Without Analytics

To test the site locally without PostHog:

1. Keep `posthog-config.js` with an empty `apiKey: ''`
2. Open the site - it will work normally with a console message:
   ```
   PostHog analytics not configured (missing API key). Site running without analytics.
   ```

## Verifying It Works

1. Deploy your changes
2. Visit https://bookmarker.lol
3. Open your browser's developer console (F12)
4. You should see: `PostHog analytics initialized`
5. In your PostHog dashboard, you should see the pageview event appear

## PostHog Dashboard

To view your analytics:

1. Go to https://app.posthog.com (or https://us.posthog.com)
2. Log in to your PostHog project
3. Check "Product Analytics" → "Insights" for visitor stats
4. Check "Session Replay" to see user sessions (if enabled)

## Filtering Your Own Traffic

To exclude your own devices from analytics:

- Visit `https://bookmarker.lol/?internal=1` once on any device
- That device will be excluded from analytics forever (stored in localStorage)
- To undo: visit `https://bookmarker.lol/?internal=0`

## Files Changed

- `/docs/posthog-config.js` - Configuration file (edit this to set your key)
- `/docs/posthog-init.js` - Initialization code (no need to edit)
- All HTML files in `/docs/` - Updated to use the new config approach

## Need Help?

- PostHog Docs: https://posthog.com/docs
- PostHog Cloud US Dashboard: https://us.posthog.com
- PostHog API Keys: Found in your project settings
