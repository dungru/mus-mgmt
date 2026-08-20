---
title: Wiki Maintenance Schema
updated: 2026-08-19
---

# Wiki Maintenance Schema

The wiki uses three layers: **raw evidence**, **maintained wiki pages**, and
**maintenance rules**. The goal is to preserve environment onboarding, device
validation, and design decisions as searchable team knowledge.

## Layers and ownership

| Layer | Location | Rule |
|---|---|---|
| Raw evidence | `docs/raw/` | Immutable; name by date and source |
| Wiki | `docs/*.md` | Maintained, cross-linked, and evidence-based |
| Rules | This file | Defines structure, updates, and lint requirements |

## Adding information

1. Store original requirements, device output, or external specifications in
   `docs/raw/` with source and date information.
2. Create or update a topic page and distinguish confirmed facts, inferences,
   and open decisions.
3. Update [index.md](index.md) with a one-line summary.
4. Append an entry to [log.md](log.md).
5. When new evidence replaces an earlier conclusion, update the old page and
   explain what changed and why.

## Page format

- Use YAML frontmatter containing at least `title` and `updated`.
- Use clear English titles and lowercase kebab-case file names.
- Link existing pages instead of duplicating content.
- Label unverified information as `Pending confirmation` or `Inference`.
- All maintained documentation, test titles, descriptions, and expected
  results must be written in English.

## Periodic wiki lint

Check that the index includes every topic, links resolve, no pages are
orphaned, DUT facts do not conflict, completed decisions are updated, and
important decisions from discussions have been written back to the wiki.
