# Noted agent guide

## What Noted is today

Noted is a private, recording-first memory system. It preserves original audio and notes, produces reviewable transcripts, and derives source-linked summaries, memories, decisions, action items, follow-ups, and open loops.

The current implementation includes:

- A React and Vite web client in `apps/web`.
- A SwiftUI iOS client in `apps/ios`.
- A local Whisper transcription and review app in `apps/macos`.
- A Fastify API, JSON repository, and one-writer processing scheduler in `apps/api`.
- A separate Cloudflare Worker, D1, R2, and Queues deployment target in `cloudflare`.
- An optional private-network CPU transcription service in `services/transcriber`.

The system is intentionally cost-conscious. Prefer local or free processing when it meets the requirement. Keep raw recordings under the user's control and make outbound processing explicit.

## Read these documents first

Read the following in order before changing product behavior or documentation:

1. `PRODUCT.md` for the current product contract.
2. `README.md` for supported entry points and commands.
3. `docs/CURRENT_PRODUCT.md` for the current scope and platform status.
4. `docs/ARCHITECTURE.md` for implementation boundaries.
5. `docs/WORKFLOWS.md` for capture, processing, and handoff flows.
6. `docs/ROADMAP.md` for planned work.
7. `docs/DECISIONS.md` and `docs/KNOWN_LIMITATIONS.md` for constraints and known gaps.

Current implementation outranks documentation when they disagree. Verify the relevant code, configuration, tests, and runtime contract before changing a document.

## Historical documentation

Everything under `docs/archive/` is historical reference. It is not a product requirement, implementation instruction, or source of current terminology.

The archived Memory Garden and Pocket documents explain earlier directions. Use them only to understand why a decision changed. Do not copy their product names, paths, or autonomous-execution rules into current work.

`NOTED_ENGINEERING_HANDOFF.md` is untracked working material. Verify it against the current implementation before using any of its claims.

## Discovery before editing

1. Inspect `git status --short --branch` and the current branch.
2. Preserve unrelated tracked and untracked user changes.
3. Search targeted directories and file types. Do not dump the whole repository.
4. Track the files you have already inspected.
5. Verify that a file or directory exists before proposing it as the next target.
6. Batch related inspections when several files answer the same question.
7. Inspect the current implementation when a document, task description, or historical PRD makes a conflicting claim.

Use these evidence labels in notes and plans:

- `VERIFIED`: confirmed in current code, configuration, tests, or a directly observed run.
- `DOCUMENTED`: stated in a current document but not confirmed by this inspection.
- `INFERRED`: a reasoned conclusion from verified evidence.
- `UNKNOWN`: not established yet.

## Files and data to skip

During discovery, skip `.git`, `node_modules`, `dist`, build products, `storage`, `.dsh-plugins`, `.obsidian`, `.wrangler`, `.wrangler-test`, `__pycache__`, `.DS_Store`, Xcode user state, and TypeScript build-info files.

Treat `.env`, `storage/`, local transcription output, logs, recordings, and credential stores as private data. Never print, paste, summarize, or commit passwords, API keys, tokens, cookies, model credentials, `.env` values, or other secrets.

## Changes and validation

Keep changes small and reversible. Do not rename a public API, change application behavior, or remove historical material as part of documentation hygiene unless the task explicitly includes it.

After an implementation change, run the relevant tests, type checks, lint, build, or platform validation. Report which checks ran and which remain unverified.

## Qwen3-Coder guidance

- Batch related inspections into one pass.
- Continue through the requested inspection instead of stopping after stating the next action.
- Verify paths before proposing them.
- Keep a short inspected-file list to avoid redundant reads.
- Prefer `rg` and `rg --files` with targeted exclusions.
- Avoid huge recursive listings such as `ls -R`.
- Distinguish current code from archived requirements before making a plan.
