---
date: 2026-08-12
description: What this Hermes implementation does, the Hermes tools it uses, and every model/API/provider that facilitates it.
type: reference
tags: [Hermes]
---

# Hermes Agent — this implementation

## What it does

A personal automation agent running on this Mac (via [Hermes Agent](https://hermes-agent.nousresearch.com),
Nous Research's open-source agent CLI/gateway). Five scheduled cron jobs deliver a
daily brief to Discord and log a permanent copy to an Obsidian vault — two of them
(`news-brief`, `market-brief`) as narrated audio plus a short text brief, not just
text; a sixth, message-triggered feature turns any Discord message into a to-do item
in the day's journal note. All five cron jobs share a single `0 6 * * *` schedule,
timed to a macOS scheduled wake — see **macOS power management**, below.

```
   ┌─────────────┐      ┌──────────────┐      ┌─────────┐      ┌──────────────┐
   │ cron (local  │ ───▶ │ script or    │ ───▶ │ Discord │      │ Obsidian     │
   │ scheduler)   │      │ agent turn   │──┬──▶│ (deliver)│     │ vault (log)  │
   └─────────────┘      └──────────────┘  │   └─────────┘      └──────────────┘
                                ▲          ▼
                         ┌──────┴───────┐ ┌──────────────┐
                         │ Discord msg  │ │ text_to_speech│  (news-brief,
                         │ (event, not  │ │ (Edge TTS) →  │   market-brief
                         │  cron)       │ │ MEDIA: audio  │   only)
                         └──────────────┘ └──────────────┘
```

## Features

| Feature | Trigger | LLM involved? | Delivers to | Logs to |
|---|---|---|---|---|
| `news-brief` | cron `0 6 * * *` | Yes — narrates tech/world headlines into a spoken script + a separate text brief | Discord (text brief, then audio) | `Notes/news-brief/<date>.md` (the text brief, verbatim) |
| `market-brief` | cron `0 6 * * *` | Yes — narrates index levels + market news into a spoken script + a separate text brief | Discord (text brief, then audio) | `Notes/market-brief/<date>.md` (the text brief, verbatim) |
| `git-daily` | cron `0 6 * * *` | Yes — summarizes script output | Discord | `Notes/git-daily/<date>.md` |
| `trending-repos` | cron `0 6 * * *` | Yes — summarizes script output | Discord | `Notes/trending-repos/<date>.md` |
| `hermes-health` | cron `0 6 * * *` | **No** — pure script, `--no-agent` | Discord | `Notes/hermes-health/<date>.md` |
| Quick-capture | Discord message in a dedicated channel | Yes — one turn per message | Discord (confirmation) | `Journal/Daily/<Month Dayth Year>.md` |

All five now share one schedule (originally staggered 6am/7am/8am/9pm) because macOS's
`pmset repeat` only supports **one** recurring wake time per day — consolidating was
required to cover every job with a single scheduled wake, not just tidiness. As a
side effect, `hermes-health`'s cost estimate (`InsightsEngine.generate(days=1)`, a
rolling 24h window from whenever the script runs) now reports 6am-to-6am instead of
9pm-to-9pm, with no script change needed.

For `news-brief`/`market-brief`, the agent composes exactly two summaries per run — a
flowing spoken script (fed to `text_to_speech`) and a terse bullet brief — and reuses
the bullet brief verbatim for both the vault note and the Discord text message, so
the vault log matches exactly what was posted and nothing gets summarized a third
time.

Each script self-fetches any secret it needs at runtime (`hermes config get <KEY>`)
rather than relying on inherited environment variables — Hermes strips API-key-shaped
variables from every subprocess it spawns by design, so this is the only pattern that
reliably works. `news-brief` and `market-brief` need no secrets at all — every source
they use is free and keyless.

## Models and providers

Every **LLM** call routes through **one provider — OpenRouter** — as the single
upstream aggregator for every model below. The one exception is text-to-speech
(next table), which is a separate, non-OpenRouter, non-LLM path.

| Role | Model | Used for |
|---|---|---|
| Main model | `deepseek/deepseek-v4-flash-0731` | All actual reasoning and tool-calling — the "brain" for every job and for interactive chat |
| Fallback model | `minimax/minimax-m2.7` | Only invoked if the main model's provider call fails (rate-limit/5xx/connection error) — does **not** cover client-side idle-timeouts, see **macOS power management** |
| Auxiliary model | `qwen/qwen3.7-flash` | Small side-tasks: vision (image/screenshot description), `web_extract` (cleaning scraped web content), `approval` (yes/no action gating), `title_generation` (session naming) |
| Auxiliary — compression | `deepseek/deepseek-v4-flash-0731` | Rewriting conversation history when context gets long — pinned to the main model, not the cheap one, since quality here matters |
| Text-to-speech | Edge TTS (Microsoft, via the `edge-tts` package) | Narrates `news-brief`/`market-brief` scripts into audio. Free, no key, Hermes' default TTS provider — no `tts.provider` override needed in `config.yaml` |

## External APIs, besides the model provider

| API | Used by | Auth |
|---|---|---|
| GitHub REST API (`/users/<user>/events`) | `git-daily` | `GITHUB_TOKEN`, fine-grained PAT, Contents: Read-only |
| GitHub Search API (`/search/repositories`) | `trending-repos` | Same `GITHUB_TOKEN` |
| Discord Bot API + Gateway | Messaging platform — delivery (REST) and two-way chat (gateway websocket, requires the Message Content privileged intent) | `DISCORD_BOT_TOKEN` |
| Frankfurter API (`api.frankfurter.dev`) | `hermes-health`, USD→AUD conversion for the daily cost estimate | None — free, no key |
| Hacker News API (`hacker-news.firebaseio.com`) | `news-brief` — top tech stories | None — free, no key |
| BBC News RSS (`feeds.bbci.co.uk`) | `news-brief` — general/world headlines | None — free, no key |
| Yahoo Finance chart API (`query1.finance.yahoo.com`) | `market-brief` — index levels (S&P 500, Nasdaq, Dow, ASX 200) | None — free, no key, just needs a User-Agent header. **Unofficial/undocumented endpoint** — could change without notice, same caveat as the roadmap's TradingView blocker |
| MarketWatch RSS (`feeds.marketwatch.com`) | `market-brief` — market news headlines | None — free, no key |

(Stooq was the first choice for market index data but is now blocked by a JS
proof-of-work anti-bot challenge — Yahoo Finance's chart API was the working
substitute.)

## Hermes tools/subsystems this implementation actually uses

| Tool/subsystem | Role here |
|---|---|
| `cronjob` | Schedules the five time-triggered jobs; supports `--script` (script output feeds the agent) and `--no-agent` (script output delivered verbatim, zero LLM cost) |
| `file` | Reads/writes Obsidian vault notes — per-job logs and the quick-capture daily journal |
| `text_to_speech` | Converts the `news-brief`/`market-brief` spoken scripts to audio (Edge TTS) and returns a `MEDIA:` tag; since `.mp3` isn't a "captionable" type, any text before the tag is delivered as its own message, audio follows as a separate attachment — no extra plumbing needed for the text+audio combo |
| `terminal` | Used only during early debugging of `git-daily`; no longer load-bearing since the switch to native `--script` execution |
| Discord platform adapter | Delivery, two-way chat, per-channel `system_prompt` override (`channel_overrides`), mention-free response (`free_response_channels`), and `missed_message_backfill` (catches messages sent while the gateway was offline) |
| `memory` / skill auto-curation | Autonomous, not explicitly invoked — Hermes periodically reflects on recent conversation turns and may save a memory or draft a reusable skill. Token cost only, not CPU/RAM |

Configured in this install but **not used** by any of the above: browser automation
(`agent-browser` isn't even installed), STT, image generation, DuckDuckGo web search,
delegation to sub-agents, kanban, MCP servers, and every messaging platform besides
Discord.

## Key config (`~/.hermes/config.yaml`)

- `agent.max_turns: 25` + `tool_loop_guardrails.hard_stop_enabled: true` — caps a
  runaway agent loop well below the token counts a 150-turn ceiling allowed
- `timezone: Australia/Brisbane` — pinned explicitly, not left to resolve from the
  machine's local setting
- `platforms.discord.free_response_channels`, `.missed_message_backfill`,
  `.channel_overrides` — the quick-capture channel's configuration
- `tts: {use_gateway: false}` — the only TTS setting present; no `tts.provider` means
  Hermes' free Edge default applies, matching the original setup wizard's choice

## macOS power management (outside Hermes, `pmset`)

Diagnosed 2026-08-12: all five morning jobs failed simultaneously with a generic
"provider timeout" / fallback-exhausted error. Root cause, confirmed against
`pmset -g log` timestamps lining up exactly: **not** a provider-side issue. The Mac
was cycling through macOS's DarkWake/Power Nap state — ~2-second network windows
every 15–20 minutes while the lid was closed and unattended — which froze in-flight
OpenRouter requests mid-response repeatedly until Hermes' own 600s client-side idle
watchdog gave up. The fallback chain never got a chance to fire, since a client-side
abort isn't a provider error.

Fix, two persistent `pmset` settings (system-level, survive reboots, **require the
Mac to stay on AC power** — scheduled wake and this sleep-timer override are both
unreliable on battery):

```bash
sudo pmset repeat wakeorpoweron MTWRFSU 05:55:00   # real full wake, 5 min before the 6am cron slot
sudo pmset -c sleep 15                              # AC-power idle-sleep timer, was 1 min — Hermes holds
                                                     # no sleep-prevention lock while a job runs, so the
                                                     # default was short enough to cut a job off mid-run
```

Verify anytime (no sudo needed): `pmset -g sched` (wake schedule), `pmset -g custom`
(sleep timers, broken out by AC vs battery). Revert either independently:
`sudo pmset repeat cancel`, `sudo pmset -c sleep 1`.

Not yet verified against a real unattended overnight cycle — next run is
2026-08-13T06:00. If jobs still fail, check whether `pmset -g log` shows a real
`Wake` or another `DarkWake` at 05:55 first; that isolates whether the wake itself
failed to fire versus something failing downstream of it.

See [[hermes-hardening-and-new-features]] for the full build/debug history, and
[[hermes-roadmap]] for what's still planned.
