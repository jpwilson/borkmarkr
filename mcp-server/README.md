# bookmarker MCP Server

A Model Context Protocol (MCP) server that allows Claude Desktop, ChatGPT, and other MCP-compatible AI assistants to save and search your bookmarker library.

## What is this?

This MCP server gives AI assistants the ability to:
- Search your bookmarks by keyword, platform, category, or author
- Save new bookmarks to your library
- Browse your categories and recent saves
- Work with your bookmarker data using natural language

## Security

**Important**: This server only accesses bookmarks for the authenticated user whose access token is provided. It never exposes other users' data. Each user must set up their own MCP server instance with their own credentials.

## Prerequisites

- Node.js 20 or later
- A bookmarker account
- Supabase project credentials (these will be provided by bookmarker)
- Claude Desktop, ChatGPT, or another MCP-compatible client

## Installation

1. Install dependencies:

```bash
cd mcp-server
npm install
```

2. Set up environment variables:

```bash
cp .env.example .env
```

3. Edit `.env` and fill in your credentials:
   - `SUPABASE_URL`: Your Supabase project URL
   - `SUPABASE_ANON_KEY`: Your Supabase anonymous key
   - `SUPABASE_USER_ACCESS_TOKEN`: Your personal access token

### Getting Your Credentials

**For bookmarker administrators**: Supabase URL and anon key are in your Supabase project settings at https://app.supabase.com/project/_/settings/api

**For users**: Your access token should be provided by bookmarker in your account settings. If this feature is not yet available in the app, contact support.

## Usage with Claude Desktop

1. Build the server:

```bash
npm run build
```

2. Add to your Claude Desktop config (`~/Library/Application Support/Claude/claude_desktop_config.json` on macOS):

```json
{
  "mcpServers": {
    "bookmarker": {
      "command": "node",
      "args": ["/path/to/bookmarker/mcp-server/dist/index.js"],
      "env": {
        "SUPABASE_URL": "https://your-project.supabase.co",
        "SUPABASE_ANON_KEY": "your-anon-key",
        "SUPABASE_USER_ACCESS_TOKEN": "your-access-token"
      }
    }
  }
}
```

3. Restart Claude Desktop

4. You can now ask Claude to:
   - "Search my bookmarks for sourdough recipes"
   - "Save this tweet to my bookmarks: [URL]"
   - "What categories do I have in my bookmarks?"
   - "Show me my recent bookmarks"

## Usage with ChatGPT (via OpenAPI)

If you prefer to use this with ChatGPT, you'll need to create a lightweight HTTP wrapper around the MCP server that exposes an OpenAPI-compatible REST API. This is not included in the current implementation but can be added.

## Available Tools

### search_bookmarks

Search your bookmarks by keyword, platform, category, or author.

**Parameters:**
- `query` (string, optional): Search query to match against titles, content, and authors
- `platform` (string, optional): Filter by platform (instagram, x, tiktok, youtube, web)
- `category` (string, optional): Filter by category
- `limit` (number, optional): Maximum results (default: 20)

**Example:**
```
"Search my bookmarks for TypeScript tutorials"
```

### save_bookmark

Save a new bookmark to your library.

**Parameters:**
- `url` (string, required): The URL to bookmark
- `title` (string, required): Title or caption
- `platform` (string, required): Source platform (instagram, x, tiktok, youtube, web)
- `author` (string, optional): Author or username
- `tags` (array, optional): Custom tags
- `note` (string, optional): Personal note

**Example:**
```
"Save this tweet to my bookmarks: https://x.com/user/status/123"
```

### get_categories

Get a list of all your bookmark categories with counts.

**Example:**
```
"What categories do I have in my bookmarks?"
```

### get_recent_bookmarks

Get your most recently saved bookmarks.

**Parameters:**
- `limit` (number, optional): Number of bookmarks to return (default: 10)

**Example:**
```
"Show me my 5 most recent bookmarks"
```

## Development

Run in development mode with auto-reload:

```bash
npm run dev
```

## Security Notes

1. **Never commit your `.env` file** — it contains your access token
2. **Never share your access token** — it grants full access to your bookmarks
3. **User isolation**: This server only accesses bookmarks for the authenticated user (based on the access token). It cannot access other users' data.
4. **No secrets in code**: All credentials are passed via environment variables, never hardcoded

## Future Enhancements

- [ ] HTTP wrapper for ChatGPT integration via custom GPTs
- [ ] Bulk import/export operations
- [ ] Collection management (create and share collections)
- [ ] Advanced filtering (date ranges, tag combinations)
- [ ] Bookmark editing and deletion

## Troubleshooting

**"User not authenticated" error**: Your `SUPABASE_USER_ACCESS_TOKEN` is invalid or expired. Generate a new one from your bookmarker account settings.

**"SUPABASE_URL must be set" error**: You haven't set up your `.env` file. Copy `.env.example` to `.env` and fill in your credentials.

**No results when searching**: Make sure you're using the correct user access token and that you have bookmarks saved in your account.

## Support

For issues or questions:
- GitHub Issues: (create issues in the main bookmarker repo)
- Email: hello@bookmarker.lol

## License

This MCP server is part of the bookmarker project. See the main repository for license information.
