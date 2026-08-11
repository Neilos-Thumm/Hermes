---
date: 2026-08-11
description: What this Hermes implementation does, the Hermes tools it uses, and every model/API/provider that facilitates it.
type: reference
tags: [Hermes]
---

# Hermes Agent — this implementation

## What it does

A personal automation agent running on this Mac (via [Hermes Agent](https://hermes-agent.nousresearch.com),
Nous Research's open-source agent CLI/gateway). Three scheduled jobs deliver a daily
brief to Discord and log a permanent copy to an Obsidian vault; a fourth, message-
triggered feature turns any Discord message into a to-do item in the day's journal
note.

```
   ┌─────────────┐      ┌──────────────┐      ┌─────────┐      ┌──────────────┐
   │ cron (local  │ ───▶ │ script or    │ ───▶ │ Discord │      │ Obsidian     │
   │ scheduler)   │      │ agent turn   │ ───▶ │ (deliver)│     │ vault (log)  │
   └─────────────┘      └──────────────┘      └─────────┘      └──────────────┘
                                ▲
                         ┌──────┴───────┐
                         │ Discord msg  │  (quick-capture channel,
                         │ (event, not  │   message-content intent)
                         │  cron)       │
                         └──────────────┘
```

## Features

| Feature | Trigger | LLM involved? | Delivers to | Logs to |
|---|---|---|---|---|
| `git-daily` | cron `0 7 * * *` | Yes — summarizes script output | Discord | `Notes/git-daily/<date>.md` |
| `trending-repos` | cron `0 8 * * *` | Yes — summarizes script output | Discord | `Notes/trending-repos/<date>.md` |
| `hermes-health` | cron `0 21 * * *` | **No** — pure script, `--no-agent` | Discord | `Notes/hermes-health/<date>.md` |
| Quick-capture | Discord message in a dedicated channel | Yes — one turn per message | Discord (confirmation) | `Journal/Daily/<Month Dayth Year>.md` |

Each script self-fetches any secret it needs at runtime (`hermes config get <KEY>`)
rather than relying on inherited environment variables — Hermes strips API-key-shaped
variables from every subprocess it spawns by design, so this is the only pattern that
reliably works.

## Models and providers

Everything routes through **one provider — OpenRouter** — as the single upstream
aggregator for every model below.

| Role | Model | Used for |
|---|---|---|
| Main model | `deepseek/deepseek-v4-flash-0731` | All actual reasoning and tool-calling — the "brain" for every job and for interactive chat |
| Fallback model | `minimax/minimax-m2.7` | Only invoked if the main model's provider call fails (rate-limit/5xx/connection error) |
| Auxiliary model | `qwen/qwen3.7-flash` | Small side-tasks: vision (image/screenshot description), `web_extract` (cleaning scraped web content), `approval` (yes/no action gating), `title_generation` (session naming) |
| Auxiliary — compression | `deepseek/deepseek-v4-flash-0731` | Rewriting conversation history when context gets long — pinned to the main model, not the cheap one, since quality here matters |

## External APIs, besides the model provider

| API | Used by | Auth |
|---|---|---|
| GitHub REST API (`/users/<user>/events`) | `git-daily` | `GITHUB_TOKEN`, fine-grained PAT, Contents: Read-only |
| GitHub Search API (`/search/repositories`) | `trending-repos` | Same `GITHUB_TOKEN` |
| Discord Bot API + Gateway | Messaging platform — delivery (REST) and two-way chat (gateway websocket, requires the Message Content privileged intent) | `DISCORD_BOT_TOKEN` |
| Frankfurter API (`api.frankfurter.dev`) | `hermes-health`, USD→AUD conversion for the daily cost estimate | None — free, no key |

## Hermes tools/subsystems this implementation actually uses

| Tool/subsystem | Role here |
|---|---|
| `cronjob` | Schedules the three time-triggered jobs; supports `--script` (script output feeds the agent) and `--no-agent` (script output delivered verbatim, zero LLM cost) |
| `file` | Reads/writes Obsidian vault notes — per-job logs and the quick-capture daily journal |
| `terminal` | Used only during early debugging of `git-daily`; no longer load-bearing since the switch to native `--script` execution |
| Discord platform adapter | Delivery, two-way chat, per-channel `system_prompt` override (`channel_overrides`), mention-free response (`free_response_channels`), and `missed_message_backfill` (catches messages sent while the gateway was offline) |
| `memory` / skill auto-curation | Autonomous, not explicitly invoked — Hermes periodically reflects on recent conversation turns and may save a memory or draft a reusable skill. Token cost only, not CPU/RAM |

Configured in this install but **not used** by any of the above: browser automation
(`agent-browser` isn't even installed), TTS/STT, image generation, DuckDuckGo web
search, delegation to sub-agents, kanban, MCP servers, and every messaging platform
besides Discord.

## Key config (`~/.hermes/config.yaml`)

- `agent.max_turns: 25` + `tool_loop_guardrails.hard_stop_enabled: true` — caps a
  runaway agent loop well below the token counts a 150-turn ceiling allowed
- `timezone: Australia/Brisbane` — pinned explicitly, not left to resolve from the
  machine's local setting
- `platforms.discord.free_response_channels`, `.missed_message_backfill`,
  `.channel_overrides` — the quick-capture channel's configuration

See [[hermes-hardening-and-new-features]] for the full build/debug history, and
[[hermes-roadmap]] for what's still planned.
