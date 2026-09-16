# Public MCP install files

Handshake for `/projects/faers-mobi/`. Do not merge this GPS PR. Deploy when good. Pay gate / billing is out of scope.

#51 Footer/About link to /llms.txt is live. Do not pile this onto #51.

## Problem

API.md still points at a local MCP path. `mcp/server.py` and `mcp/claude_desktop.example.json` 404 on faers.mobi. ChatGPT already has a paste-ready recipe (#48); MCP does not.

## Wanted

Mirror #48 for MCP:

1. Serve `mcp/server.py` and `mcp/claude_desktop.example.json` at public URLs.
2. Optional paste-ready `/mcp.md` install recipe for Claude Desktop / Cursor (auth none; hypothesis disclaimer; when to use series/profile/class/brief).
3. Update `llms.txt`, footer/About, and `API.md` pointers as needed.

No new compute. No billing / pay gate.

## Done when

- Those files (and `/mcp.md` if shipped) are 200.
- llms.txt / footer / About / API.md point at the public URLs, not a local path.
- Deploy note with those URLs.

## Out of scope

Pay gate, Stripe, PDF/Typst, site chat box, new `/signals` formats, merging this GPS PR.
