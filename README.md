---
date: 2026-08-16
description: What this Hermes implementation does, the Hermes tools it uses, and every model/API/provider that facilitates it.
type: reference
tags: [Hermes]
---

# Hermes Agent — this implementation

## What it does

A personal automation agent running on this Mac (via [Hermes Agent](https://hermes-agent.nousresearch.com),
Nous Research's open-source agent CLI/gateway). Eight scheduled cron jobs deliver a
daily brief to Discord and log a permanent copy to an Obsidian vault — five of them
(`news-brief`, `market-brief`, `tech-brief`, `thailand-brief`, `australia-brief`) as
narrated audio plus a short text brief, not just text; a ninth, message-triggered
feature turns any Discord message into a to-do item in the day's journal note (and,
since 2026-08-14, the week's kanban board). All eight cron jobs share a single
`0 6 * * *` schedule, timed to a macOS scheduled wake — see **macOS power
management**, below.

```
   ┌─────────────┐      ┌──────────────┐      ┌─────────┐      ┌──────────────┐
   │ cron (local  │ ───▶ │ script or    │ ───▶ │ Discord │      │ Obsidian     │
   │ scheduler)   │      │ agent turn   │──┬──▶│ (deliver)│     │ vault (log)  │
   └─────────────┘      └──────────────┘  │   └─────────┘      └──────────────┘
                                ▲          ▼
                         ┌──────┴───────┐ ┌──────────────┐
                         │ Discord msg  │ │ text_to_speech│  (news-brief, market-brief,
                         │ (event, not  │ │ (Edge TTS) →  │   tech-brief, thailand-brief,
                         │  cron)       │ │ MEDIA: audio  │   australia-brief only)
                         └──────────────┘ └──────────────┘
```

## Features

| Feature | Trigger | LLM involved? | Delivers to | Logs to |
|---|---|---|---|---|
| `news-brief` | cron `0 6 * * *` | Yes — narrates general/world/politics headlines into a spoken script + a separate text brief (pure summary, capped at ~1950 chars) + a trailing "Sources:" link list, one per bullet, not counted against that cap | Discord (text brief, then audio) | `Briefing/news-brief/<date>.md` (the text brief, verbatim) |
| `market-brief` | cron `0 6 * * *` | Yes — narrates index levels + market news into a spoken script + a separate text brief | Discord (text brief, then audio) | `Briefing/market-brief/<date>.md` (the text brief, verbatim) |
| `tech-brief` | cron `0 6 * * *` | Yes — narrates LLM/AI model news + general tech news into a spoken script + a separate text brief, split into labeled "LLM & Models" / "Also in tech" halves, each with the item's own source link | Discord (text brief, then audio) | `Briefing/tech-brief/<date>.md` (the text brief, verbatim) |
| `thailand-brief` | cron `0 6 * * *` | Yes — narrates Thailand-specific news (Bangkok Post's Thailand section + Khaosod English) into a spoken script + a separate text brief (pure summary, capped at ~1950 chars) + a trailing "Sources:" link list, one per bullet, not counted against that cap | Discord (text brief, then audio) | `Briefing/thailand-brief/<date>.md` (the text brief, verbatim) |
| `australia-brief` | cron `0 6 * * *` | Yes — narrates Australia-specific news (ABC News' Around Australia feed + Guardian Australia, opinion/podcast/video items filtered out) into a spoken script + a separate text brief (pure summary, capped at ~1950 chars) + a trailing "Sources:" link list, one per bullet, not counted against that cap | Discord (text brief, then audio) | `Briefing/australia-brief/<date>.md` (the text brief, verbatim) |
| `git-daily` | cron `0 6 * * *` | Yes — summarizes script output | Discord | `Briefing/git-daily/<date>.md` |
| `trending-repos` | cron `0 6 * * *` | Yes — summarizes script output | Discord | `Briefing/trending-repos/<date>.md` |
| `hermes-health` | cron `0 6 * * *` | **No** — pure script, `--no-agent` | Discord | `Briefing/hermes-health/<date>.md` |
| Quick-capture | Discord message in a dedicated channel | Yes — one turn per message | Discord (confirmation) | `Journal/Daily/<Month Dayth Year>.md` |

All eight now share one schedule (originally staggered 6am/7am/8am/9pm) because macOS's
`pmset repeat` only supports **one** recurring wake time per day — consolidating was
required to cover every job with a single scheduled wake, not just tidiness. As a
side effect, `hermes-health`'s cost estimate (`InsightsEngine.generate(days=1)`, a
rolling 24h window from whenever the script runs) now reports 6am-to-6am instead of
9pm-to-9pm, with no script change needed.

For `news-brief`/`market-brief`/`tech-brief`/`thailand-brief`/`australia-brief`, the
agent composes exactly two summaries per run — a flowing spoken script (fed to
`text_to_speech`) and a terse bullet brief — and reuses the bullet brief verbatim for
both the vault note and the Discord text message, so the vault log matches exactly
what was posted and nothing gets summarized a third time. `tech-brief` was originally
combined into `news-brief` (general news + tech in one channel); split out to its own
channel with a dedicated source pool (Hacker News top 25 + TechCrunch) so it could go
deeper — labeled LLM/model vs. general tech halves, 10-12 bullets by default,
expanding well past that on a genuinely big AI/tech news day. `thailand-brief` shipped
2026-08-16 as a geography-scoped sibling of `news-brief` (flat bullet list, no two-way
split — country-scoped news doesn't have news-brief's tech/general fork) — Bangkok
Post's dedicated `thailand.xml` section feed was picked deliberately over its
`topstories.xml` (which mixes in international wire content) specifically to keep the
pool Thailand-specific by construction, not by prompt-side filtering alone.
`thailand-brief` originally had the model append each bullet's source URL inline (a
pattern carried over from `tech-brief`, which still does this — its LLM/model-news half
needs per-item attribution); removed from `thailand-brief` shortly after launch, then
reintroduced 2026-08-23 in a different shape — see the "Sources:" section note below,
now shared by `news-brief`/`thailand-brief`/`australia-brief`. `tech-brief` itself is
unchanged, still inline.

`australia-brief` shipped 2026-08-16 alongside two lessons applied proactively from
`thailand-brief`'s launch: (1) the script extracts and cleans each item's RSS
`description` field (not just its title) for both sources, since a bare headline gives
the model nothing to add for stories it has no background knowledge of — Bangkok
Post/Khaosod's descriptions were already clean plain text, but Guardian Australia's
`description` field turned out to be the *full article body* wrapped in a promotional
newsletter-signup block, not a short summary; the script extracts just the genuine
lead paragraph (the one sentence before that block) rather than the whole article or a
crude truncation. (2) Guardian's `australia-news` RSS mixes hard news with opinion
columns, podcasts, and video clips — roughly half the feed on a normal day — filtered
out mechanically before the pool reaches the model: opinion/franchise pieces reliably
end their title `... | <byline>`, the opinion vertical lives under `/commentisfree/`,
and audio/video items end their title with the word itself. Same reasoning as ABC's
"Around Australia" feed being picked over its "Top Stories"/"Just In" feeds, which are
themselves mixed with international and human-interest content — check a candidate
feed's actual content before wiring it in, don't assume a plausible-sounding feed name
is actually scoped the way it sounds.

**Both `thailand-brief` and `australia-brief` prompts now cap length explicitly**,
added after a real Discord-message-overflow bug: richer per-item detail (from the
`description` fix above) pushed a 12-bullet brief to 2021 characters — over Discord's
hard 2000-char single-message limit — causing Discord's own delivery layer to
auto-split it into two messages `(1/2)`/`(2/2)`. The spoken script prompt now states an
explicit ~1.8-2 minute / ~260-300 word ceiling (never split into multiple parts under
any circumstance), and the bullet brief prompt states an explicit character ceiling —
raised from an initial 1700 to **1950** once it was confirmed the `MEDIA:` tag is
stripped out of the text and delivered as a separate attachment *before* Discord's
2000-char check runs, so it was never actually competing with the bullet text for
budget — trading bullet count/wording tightness for staying under the limit on a heavy
news day rather than letting the total run long. Same fix applied to both jobs since
both share the identical enriched-bullet pattern and neither had a length cap before
this.

**`news-brief` fixed to match `thailand-brief`/`australia-brief`'s depth**, 2026-08-23,
after the user directly compared per-bullet richness across jobs and found `news-brief`
noticeably thinner, plus inconsistent link inclusion day to day. Same root cause as the
original `thailand-brief` bug: `news-brief.sh` was still only extracting `title` +
`link` from BBC's feed, never the `description` field — masked longer than it should
have been because BBC's major-story headlines are things the model often already has
background knowledge of, so it read passably even without the source's own summary
sentence. The "links where useful" phrasing in the prompt was the separate cause of the
inconsistency — subjective wording, interpreted differently run to run. Fixed both:
script now extracts and cleans `description` like the other jobs; prompt now specifies
pure-summary, link-free bullets capped at ~1950 characters, followed by a separate
"Sources:" section listing each bullet's link in matching order — explicitly *not*
counted against that cap, and allowed to push the total over Discord's limit into a
second auto-split message, accepted deliberately rather than trimming content to avoid
it. Same "Sources:" pattern extended to `thailand-brief` and `australia-brief`
2026-08-23 (both scripts updated to carry each item's link through the pool again,
having dropped it entirely days earlier — see below) — all three general-news-style
jobs now share one link convention.

**`market-brief`'s prompt now separates the index-summary line from the news-bullet
budget**, fixed 2026-08-16 after a report looked unusually shallow (2 news bullets
instead of the usual 5). Root cause: the prompt's "4-6 total bullets" cap never
distinguished the index-level summary from actual news — on days the model combined
all four indices into one bullet line (the norm across prior good days), 5 slots were
left for news; the day it flagged, the model split the four indices across 4 separate
lines instead, and the same undifferentiated cap left only 1-2 slots for news
regardless of how much was in the pool (which, checked directly, was a healthy 8
items that day — not a thin-data problem). Fix: the index summary is now specified as
always exactly one combined line, structurally separate from and not counted against
the "4-6 news bullets" budget.

**`thailand-brief` and `australia-brief` got the same "Sources:" treatment as
`news-brief`, 2026-08-23**, at explicit request to match "exactly the same manner."
Both scripts had dropped each item's link entirely when links were removed a week
earlier; both now carry the link back through the pool alongside title and description
(Guardian's block already computed `link` internally for its opinion/podcast filtering
but never printed it — just needed wiring to the output line). Prompts updated
identically to `news-brief`'s: link-free bullets capped at ~1950 characters, followed
by a "Sources:" section not counted against that cap. Verified per job: `thailand-brief`
landed at 1915 bullet-chars (11 bullets, 11 matching sources, cutting it closer to the
1950 ceiling than usual but still under), `australia-brief` at 1255 (9 bullets, 9
matching sources) — both delivered clean, TTS audio confirmed generated for both.

**`cron.wrap_response: false` added to `config.yaml`.** Every cron job's Discord
delivery was silently being wrapped in a `Cronjob Response: <name>\n(job_id: ...)\n---\n\n<content>\n\nTo stop or manage this job, send me a new message (e.g. "stop reminder <name>").`
envelope by Hermes' own scheduler (`cron/scheduler.py`, on by default, invisible from
this project's own logs/vault files/`messages` DB since those all record the *raw*
pre-wrap agent output, not the actually-delivered text) — global, not per-job. Turned
off because the user manages cron jobs by talking to Claude Code directly rather than
via the in-Discord "stop reminder" command, and the header/footer added visual noise
Hermes generated on its own, not something either job's prompt ever asked for. Applies
to all eight cron jobs' Discord deliveries, not just the two brief jobs that surfaced
it — `load_config()` caches on the config file's mtime, so this took effect
immediately, no gateway restart needed.

Each script self-fetches any secret it needs at runtime (`hermes config get <KEY>`)
rather than relying on inherited environment variables — Hermes strips API-key-shaped
variables from every subprocess it spawns by design, so this is the only pattern that
reliably works. `news-brief`, `market-brief`, `tech-brief`, `thailand-brief`, and
`australia-brief` need no secrets at all — every source they use is free and keyless.

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
| Text-to-speech | Edge TTS (Microsoft, via the `edge-tts` package) | Narrates `news-brief`/`market-brief`/`tech-brief` scripts into audio. Free, no key, Hermes' default TTS provider — no `tts.provider` override needed in `config.yaml` |

## External APIs, besides the model provider

| API | Used by | Auth |
|---|---|---|
| GitHub REST API (`/users/<user>/events`) | `git-daily` | `GITHUB_TOKEN`, fine-grained PAT, Contents: Read-only |
| GitHub Search API (`/search/repositories`) | `trending-repos` | Same `GITHUB_TOKEN` |
| Discord Bot API + Gateway | Messaging platform — delivery (REST) and two-way chat (gateway websocket, requires the Message Content privileged intent) | `DISCORD_BOT_TOKEN` |
| Frankfurter API (`api.frankfurter.dev`) | `hermes-health`, USD→AUD conversion for the daily cost estimate | None — free, no key |
| Hacker News API (`hacker-news.firebaseio.com`) | `tech-brief` — top 25 tech/AI stories | None — free, no key |
| BBC News RSS (`feeds.bbci.co.uk`) | `news-brief` — general/world/politics headlines + descriptions | None — free, no key |
| TechCrunch RSS (`techcrunch.com/feed`) | `tech-brief` — mainstream tech/industry news | None — free, no key |
| Yahoo Finance chart API (`query1.finance.yahoo.com`) | `market-brief` — index levels (S&P 500, Nasdaq, Dow, ASX 200) | None — free, no key, just needs a User-Agent header. **Unofficial/undocumented endpoint** — could change without notice, same caveat as the roadmap's TradingView blocker |
| MarketWatch RSS (`feeds.marketwatch.com`) | `market-brief` — market news headlines | None — free, no key |
| Bangkok Post RSS (`bangkokpost.com/rss/data/thailand.xml`) | `thailand-brief` — Thailand-section headlines (deliberately not `topstories.xml`, which mixes in non-Thailand wire content) | None — free, no key |
| Khaosod English RSS (`khaosodenglish.com/feed`) | `thailand-brief` — Thailand-domestic headlines | None — free, no key |
| ABC News RSS (`abc.net.au/news/feed/104333858/rss.xml` — "Around Australia") | `australia-brief` — Australia-domestic headlines (deliberately not the "Top Stories"/"Just In" feeds, which mix in international/human-interest content) | None — free, no key |
| Guardian Australia RSS (`theguardian.com/australia-news/rss`) | `australia-brief` — Australia-domestic headlines, opinion/podcast/video items filtered out before reaching the model | None — free, no key |

(Stooq was the first choice for market index data but is now blocked by a JS
proof-of-work anti-bot challenge — Yahoo Finance's chart API was the working
substitute.)

## Hermes tools/subsystems this implementation actually uses

| Tool/subsystem | Role here |
|---|---|
| `cronjob` | Schedules the eight time-triggered jobs; supports `--script` (script output feeds the agent) and `--no-agent` (script output delivered verbatim, zero LLM cost) |
| `file` | Reads/writes Obsidian vault notes — per-job logs, the quick-capture daily journal, and the quick-capture weekly kanban board |
| `text_to_speech` | Converts the `news-brief`/`market-brief`/`tech-brief`/`thailand-brief`/`australia-brief` spoken scripts to audio (Edge TTS) and returns a `MEDIA:` tag; since `.mp3` isn't a "captionable" type, any text before the tag is delivered as its own message, audio follows as a separate attachment — no extra plumbing needed for the text+audio combo |
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
- `cron: {wrap_response: false}` — disables Hermes' default `Cronjob Response: <name>...`
  header/`"stop reminder"` footer wrapper on every cron job's Discord delivery (global,
  on by default otherwise); added 2026-08-16, see the `australia-brief`/`thailand-brief`
  section above

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

Confirmed working across multiple real unattended overnight cycles since (2026-08-13,
2026-08-14 mornings both delivered cleanly). If it ever regresses, check whether
`pmset -g log` shows a real `Wake` or another `DarkWake` at 05:55 first; that isolates
whether the wake itself failed to fire versus something failing downstream of it.

See [[hermes-development-log]] for the full chronological build/debug history
(every session, 2026-08-10 through 2026-08-14 — bug writeups, root causes,
decisions and why), and [[hermes-roadmap]] for what's still planned.
