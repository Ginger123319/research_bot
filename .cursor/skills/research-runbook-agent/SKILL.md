---
name: research-runbook-agent
description: Use when generating a runbook-style research document from web sources and you must prioritize original/official materials, score source relevance, verify accessibility, and provide traceable URLs with blocked-source disclosure.
---

# Research Runbook Agent

## Overview

Turn a concrete “小切口问题” into a **runbook** backed by **original sources** (official docs/code/papers), with an explicit **Source Relevance & Authority** table and **access (ok/blocked/not_found)** transparency.

## When to Use

Use when the user asks for:

- “调研机器人 / 搜集网络信息 / 生成 agent 阅读文档”
- Runbook / 排障手册 / 部署 Playbook
- 强调：官方文档/代码/论文优先、真实性验证、提供原始链接、blocked 也要提示

Do NOT use when:

- User only wants a high-level summary without sources.

## Core Workflow (High-recall → Hard-filter)

### 1) Require a Small-Cut Problem Brief (before searching)

Produce (and later store) these fields:

- **problem_statement**: one-line, specific (what exactly is being deployed/diagnosed)
- **environment**: platform + versions + constraints (k8s/baremetal, model/framework version, network constraints)
- **success_criteria**: measurable outcome

If user input is broad, narrow it to one runbook.

### 2) Dual-channel retrieval (recall-first)

- **Channel A (S0-only)**: official docs, official repo docs, code/PR/release notes, papers
- **Channel B (broad)**: synonyms, historical naming, related subsystem keywords to avoid missing key sources

**Hard rule:** Prefer the most original source that matches the claim:

official docs > official code (specific file/commit/PR) > paper > maintainer statement > third-party blog.

### 3) For each candidate source, fill a `SourceCandidate` row

Every source must have:

- **URL** (no invented links)
- **Authority**: S0 / S1 / S2
- **Relevance (0-5)** + **one-sentence rationale**
- **Access**: ok / blocked / not_found

#### Access rules (anti-hallucination)

- **Access must be measured, not guessed.** A URL may only be marked `ok` if you successfully retrieved it (HTTP 2xx) during this run.
- If **Access != ok**, **DO NOT** quote or paraphrase as if you read it.
- If **Access=blocked** but clearly looks official and highly relevant, keep it as **Top Candidate (blocked)** and provide alternatives.

**Minimum requirement:** for every URL you cite, include a recorded access check result from either:

- `python3 scripts/research_runbook.py ... --seed-url <url>` (records status_code/error), or
- a direct fetch in the current session (and record failure mode)

#### Freshness rules (never rely on stale docs)

- **Every cited source MUST have a freshness signal** recorded: page `Last-Modified` header, a visible "last updated" on the page, a release tag/commit date, or a paper/preprint date. If none exists, note `freshness=unknown` and treat as 低 confidence.
- **Detect deprecation/legacy banners.** If the page shows any of: "legacy documentation", "deprecated", "no longer maintained", "has moved", "please use the new documentation", OR contains a `<link rel="canonical">` pointing to a different URL:
  - Demote the legacy page to **not usable for mainline runbook** (treat as blocked equivalent for mainline use).
  - Add a **freshness warning row** and include the new/canonical URL as the primary source.
- **Prefer latest official version** when multiple versions exist:
  - Use the URL from the project's current docs site (e.g., the one linked from the project's homepage/README), not archived mirrors.
  - For code references, prefer a specific **tag/commit** rather than `main`/`master` (so the runbook remains reproducible).
- **Time-window rule for fast-moving areas** (LLM serving, training frameworks, kernels, drivers):
  - If a source is older than 12 months, you must either (a) cross-check with a newer S0/S1 source, or (b) mark that specific claim as 低 confidence.
- **Freshness warning must be surfaced in the `Source Relevance & Authority` table** (the repo script auto-fills `last-modified` and `⚠ canonical_elsewhere / deprecation_notice` when detected).

### 4) Canonicalization & dedup

Before ranking:

- remove tracking params (utm_*, gclid, fbclid, etc.)
- drop fragments (#…)
- prefer canonical URL when redirected
- dedup by canonical URL (or same repo path + same tag/commit)

### 5) Rank sources (table must be output)

Sorting priority:

1. Authority (S0 > S1 > S2)
2. Relevance (5 → 0)
3. Access (ok > blocked > not_found)

Output the **Source Relevance & Authority** table early in the runbook.

### 6) Hard-filter what can enter the main runbook

Runbook **mainline** (steps + key conclusions) may only use evidence that is:

- **S0/S1**
- **Access=ok**
- **Relevance ≥ 4**

**Degrade rule:** If no S0/S1 with Relevance ≥ 4 exists but S0/S1 with Relevance=3 exists, you may use it **only with confidence ≤ 中** and you must add an explicit verification step.

### 7) Produce runbook steps (each step has verification + branching)

Each step must include:

- purpose
- action
- expected observation (verification)
- next branch
- risk + rollback

### 8) Claims table with confidence + conflicts

For each claim:

- **evidence A/B** must be two independent sources when claiming **高** confidence
- if sources conflict, explicitly record:
  - what conflicts
  - likely reason (version/default/platform)
  - which branch is safer

**Confidence rubric**

- **高**: ≥2 independent S0/S1, consistent applicability
- **中**: 1 S0/S1, but runbook includes an explicit verification step
- **低**: only S2, or unresolved conflict without a practical verification

## Quick Reference

### SourceCandidate table columns (must output)

| Title | Type | Authority | Relevance + rationale | Version/Date | Access | URL | Alternatives |
|---|---|---|---|---|---|---|---|

### Blocked-source disclosure (must output when applicable)

- **Top Candidate (blocked)**: `<title>` — “可能最相关/最官方，但当前无法访问”
- **Why likely relevant**: (based on metadata only)
- **Executable alternatives**: 1–2 accessible S0/S1 sources
- **How to obtain**: mirror/raw/tag/release notes, etc.

## Implementation

### Skeleton generation (recommended)

Use the repo script to generate the initial runbook + session files and to check access for seed URLs:

```bash
python3 scripts/research_runbook.py --help
```

Then fill:

- Titles
- Authority/Relevance
- Runbook steps + verification points
- Claim table

## Common Mistakes

- **Invented URLs**: If you didn’t retrieve it, don’t cite it.
- **Guessing access**: never label `ok/blocked/not_found` without an actual access-check result in this run.
- **Quoting blocked sources**: Access!=ok → no quotes/snippets.
- **Using S2 as main evidence**: keep S2 as background only.
- **No verification points**: runbook steps without observables are not actionable.
- **Stale docs used as mainline**: if the page is a legacy/deprecated mirror or has a canonical pointing elsewhere, do not use it as mainline evidence — switch to the new/canonical URL and record the legacy URL only as a historical note.

