#!/usr/bin/env node
/**
 * bookmarker MCP Server
 * 
 * Allows Claude and ChatGPT to save and search a user's bookmarks
 * through the MCP (Model Context Protocol) interface.
 * 
 * Environment variables required:
 * - SUPABASE_URL: Your Supabase project URL
 * - SUPABASE_ANON_KEY: Your Supabase anonymous key
 * - SUPABASE_USER_ACCESS_TOKEN: User's access token (from auth)
 */

import { Server } from '@modelcontextprotocol/sdk/server/index.js';
import { StdioServerTransport } from '@modelcontextprotocol/sdk/server/stdio.js';
import {
  CallToolRequestSchema,
  ListToolsRequestSchema,
} from '@modelcontextprotocol/sdk/types.js';
import { createClient } from '@supabase/supabase-js';

// Environment validation
const SUPABASE_URL = process.env.SUPABASE_URL;
const SUPABASE_ANON_KEY = process.env.SUPABASE_ANON_KEY;
const SUPABASE_USER_ACCESS_TOKEN = process.env.SUPABASE_USER_ACCESS_TOKEN;

if (!SUPABASE_URL || !SUPABASE_ANON_KEY) {
  console.error('Error: SUPABASE_URL and SUPABASE_ANON_KEY must be set');
  process.exit(1);
}

if (!SUPABASE_USER_ACCESS_TOKEN) {
  console.error('Warning: SUPABASE_USER_ACCESS_TOKEN not set. Requests will fail without user authentication.');
}

// Initialize Supabase client
const supabase = createClient(SUPABASE_URL, SUPABASE_ANON_KEY, {
  global: {
    headers: {
      Authorization: `Bearer ${SUPABASE_USER_ACCESS_TOKEN}`,
    },
  },
});

// MCP Server
const server = new Server(
  {
    name: 'bookmarker-mcp-server',
    version: '1.0.0',
  },
  {
    capabilities: {
      tools: {},
    },
  }
);

// List available tools
server.setRequestHandler(ListToolsRequestSchema, async () => {
  return {
    tools: [
      {
        name: 'search_bookmarks',
        description: 'Search the user\'s bookmarks by keyword, platform, category, or author. Returns matching bookmarks with title, URL, platform, category, and tags.',
        inputSchema: {
          type: 'object',
          properties: {
            query: {
              type: 'string',
              description: 'Search query to match against bookmark titles, body text, and authors',
            },
            platform: {
              type: 'string',
              description: 'Filter by platform: instagram, x, tiktok, youtube, web',
              enum: ['instagram', 'x', 'tiktok', 'youtube', 'web'],
            },
            category: {
              type: 'string',
              description: 'Filter by category (e.g., technology, fitness, fooddrink)',
            },
            limit: {
              type: 'number',
              description: 'Maximum number of results to return (default: 20)',
              default: 20,
            },
          },
        },
      },
      {
        name: 'save_bookmark',
        description: 'Save a new bookmark to the user\'s library. The bookmark will be automatically categorized.',
        inputSchema: {
          type: 'object',
          properties: {
            url: {
              type: 'string',
              description: 'The URL to bookmark',
            },
            title: {
              type: 'string',
              description: 'Title or caption of the bookmark',
            },
            platform: {
              type: 'string',
              description: 'Source platform',
              enum: ['instagram', 'x', 'tiktok', 'youtube', 'web'],
            },
            author: {
              type: 'string',
              description: 'Author or username (optional)',
            },
            tags: {
              type: 'array',
              items: { type: 'string' },
              description: 'Custom tags (optional)',
            },
            note: {
              type: 'string',
              description: 'Personal note about this bookmark (optional)',
            },
          },
          required: ['url', 'title', 'platform'],
        },
      },
      {
        name: 'get_categories',
        description: 'Get a list of all bookmark categories the user has saved to, with counts.',
        inputSchema: {
          type: 'object',
          properties: {},
        },
      },
      {
        name: 'get_recent_bookmarks',
        description: 'Get the user\'s most recently saved bookmarks.',
        inputSchema: {
          type: 'object',
          properties: {
            limit: {
              type: 'number',
              description: 'Number of recent bookmarks to return (default: 10)',
              default: 10,
            },
          },
        },
      },
    ],
  };
});

// Handle tool calls
server.setRequestHandler(CallToolRequestSchema, async (request) => {
  const { name, arguments: args } = request.params;

  try {
    switch (name) {
      case 'search_bookmarks': {
        const { query, platform, category, limit = 20 } = args as {
          query?: string;
          platform?: string;
          category?: string;
          limit?: number;
        };

        let queryBuilder = supabase
          .from('bookmarks')
          .select('id, url, title, author, platform, category_id, subcategory, tags, saved_at')
          .is('deleted_at', null)
          .order('saved_at', { ascending: false })
          .limit(limit);

        if (platform) {
          queryBuilder = queryBuilder.eq('platform', platform);
        }

        if (category) {
          queryBuilder = queryBuilder.eq('category_id', category);
        }

        if (query) {
          // Full-text search across title, body_text, and author
          queryBuilder = queryBuilder.or(`title.ilike.%${query}%,body_text.ilike.%${query}%,author.ilike.%${query}%`);
        }

        const { data, error } = await queryBuilder;

        if (error) {
          return {
            content: [
              {
                type: 'text',
                text: `Error searching bookmarks: ${error.message}`,
              },
            ],
          };
        }

        return {
          content: [
            {
              type: 'text',
              text: JSON.stringify(
                {
                  count: data.length,
                  bookmarks: data.map((b) => ({
                    title: b.title,
                    url: b.url,
                    author: b.author,
                    platform: b.platform,
                    category: b.category_id,
                    subcategory: b.subcategory,
                    tags: b.tags,
                    saved_at: b.saved_at,
                  })),
                },
                null,
                2
              ),
            },
          ],
        };
      }

      case 'save_bookmark': {
        const { url, title, platform, author, tags, note } = args as {
          url: string;
          title: string;
          platform: string;
          author?: string;
          tags?: string[];
          note?: string;
        };

        // Generate a stable ID from the URL (simplified version)
        const stableId = url.toLowerCase().replace(/[?#].*$/, '');

        // Get current user
        const { data: userData } = await supabase.auth.getUser();
        if (!userData.user) {
          return {
            content: [
              {
                type: 'text',
                text: 'Error: User not authenticated',
              },
            ],
          };
        }

        const { data, error } = await supabase
          .from('bookmarks')
          .upsert({
            id: stableId,
            owner_id: userData.user.id,
            url,
            title,
            author,
            platform,
            kind: 'link', // Default kind
            tags: tags || [],
            note_text: note,
            saved_at: new Date().toISOString(),
            updated_at: new Date().toISOString(),
          })
          .select();

        if (error) {
          return {
            content: [
              {
                type: 'text',
                text: `Error saving bookmark: ${error.message}`,
              },
            ],
          };
        }

        return {
          content: [
            {
              type: 'text',
              text: `Bookmark saved successfully!\n\nTitle: ${title}\nURL: ${url}\nPlatform: ${platform}${author ? `\nAuthor: ${author}` : ''}${tags?.length ? `\nTags: ${tags.join(', ')}` : ''}`,
            },
          ],
        };
      }

      case 'get_categories': {
        const { data, error } = await supabase
          .from('bookmarks')
          .select('category_id')
          .is('deleted_at', null);

        if (error) {
          return {
            content: [
              {
                type: 'text',
                text: `Error fetching categories: ${error.message}`,
              },
            ],
          };
        }

        // Count bookmarks per category
        const categoryCounts = data.reduce((acc, bookmark) => {
          const cat = bookmark.category_id || 'uncategorized';
          acc[cat] = (acc[cat] || 0) + 1;
          return acc;
        }, {} as Record<string, number>);

        return {
          content: [
            {
              type: 'text',
              text: JSON.stringify(
                {
                  total_categories: Object.keys(categoryCounts).length,
                  categories: Object.entries(categoryCounts)
                    .sort(([, a], [, b]) => b - a)
                    .map(([category, count]) => ({ category, count })),
                },
                null,
                2
              ),
            },
          ],
        };
      }

      case 'get_recent_bookmarks': {
        const { limit = 10 } = args as { limit?: number };

        const { data, error } = await supabase
          .from('bookmarks')
          .select('id, url, title, author, platform, category_id, tags, saved_at')
          .is('deleted_at', null)
          .order('saved_at', { ascending: false })
          .limit(limit);

        if (error) {
          return {
            content: [
              {
                type: 'text',
                text: `Error fetching recent bookmarks: ${error.message}`,
              },
            ],
          };
        }

        return {
          content: [
            {
              type: 'text',
              text: JSON.stringify(
                {
                  count: data.length,
                  bookmarks: data.map((b) => ({
                    title: b.title,
                    url: b.url,
                    author: b.author,
                    platform: b.platform,
                    category: b.category_id,
                    tags: b.tags,
                    saved_at: b.saved_at,
                  })),
                },
                null,
                2
              ),
            },
          ],
        };
      }

      default:
        return {
          content: [
            {
              type: 'text',
              text: `Unknown tool: ${name}`,
            },
          ],
          isError: true,
        };
    }
  } catch (error) {
    return {
      content: [
        {
          type: 'text',
          text: `Error executing tool: ${error instanceof Error ? error.message : String(error)}`,
        },
      ],
      isError: true,
    };
  }
});

// Start server
async function main() {
  const transport = new StdioServerTransport();
  await server.connect(transport);
  console.error('bookmarker MCP Server running on stdio');
}

main().catch((error) => {
  console.error('Fatal error:', error);
  process.exit(1);
});
