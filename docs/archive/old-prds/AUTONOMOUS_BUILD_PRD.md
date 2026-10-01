# Autonomous Build PRD --- AI Personal Memory / Capture App

**Document:** `AUTONOMOUS_BUILD_PRD.md`\
**Build mode:** Autonomous / low-interruption\
**Target agent:** Codex, Luna, or equivalent coding agent\
**Status:** Approved for autonomous MVP implementation\
**Date:** 2026-07-23

------------------------------------------------------------------------

# 1. EXECUTIVE DIRECTIVE

Build a complete, usable MVP of an AI-powered personal memory
application.

The application should allow a user to dump information into it with
almost no organizational effort and later retrieve, understand, connect,
and act on that information through AI.

The core product principle is:

> **The user captures information. The system organizes it.**

The user must not be required to maintain folders, notebooks, tags,
databases, or a manually curated "second brain."

This is an autonomous build.

Do not stop after scaffolding, architecture, database design, or an
individual phase. Continue through implementation, integration, testing,
repair, and documentation until the MVP acceptance criteria in this PRD
are satisfied.

The desired final agent report is:

> Application is running. Here is how to open it. Here is what works.
> Here are any remaining limitations.

Not:

> Phase 1 is complete. Would you like me to continue?

------------------------------------------------------------------------

# 2. AUTONOMOUS AGENT OPERATING RULES

These rules have priority throughout implementation.

## 2.1 Do not ask routine questions

Do not ask the user to choose:

-   file names
-   folder structures
-   component names
-   database field names
-   routine library choices
-   CSS implementation details
-   minor UI decisions
-   test frameworks
-   API route naming
-   internal abstractions
-   naming conventions
-   ordinary implementation tradeoffs

Make a reasonable engineering decision and continue.

## 2.2 Continue between phases automatically

Do not wait for approval after:

-   planning
-   scaffolding
-   database creation
-   backend implementation
-   frontend implementation
-   AI implementation
-   tests
-   Docker configuration
-   documentation

Proceed automatically to the next required task.

## 2.3 Repair your own failures

If:

-   a build fails
-   tests fail
-   lint fails
-   TypeScript fails
-   Docker fails
-   migrations fail
-   an API contract is inconsistent
-   an integration does not work

investigate and repair it.

Do not report a routine development failure to the user as a blocker.

## 2.4 Genuine blockers

Stop only when progress requires something only the user can provide,
such as:

-   credentials
-   API keys
-   domain/DNS access
-   paid-service authorization
-   inaccessible infrastructure
-   a destructive action with meaningful external consequences
-   an externally imposed decision that cannot reasonably be inferred

When possible, isolate that dependency behind configuration and continue
building everything else.

## 2.5 Minimize token waste

This build may be executed using a cost-conscious coding model.

Therefore:

-   inspect before rewriting
-   avoid repeatedly summarizing the PRD
-   avoid verbose progress narration
-   use deterministic code where AI is unnecessary
-   do not regenerate working files without reason
-   run focused tests during development
-   run the complete validation suite before completion
-   record important architectural decisions in documentation instead of
    repeatedly reconsidering them

## 2.6 No feature creep

Build the MVP defined here.

Do not spontaneously add:

-   native iOS application
-   native Android application
-   Apple Watch application
-   browser extension
-   Gmail integration
-   Google Calendar integration
-   Slack integration
-   team collaboration
-   social features
-   public sharing
-   elaborate graph visualization
-   billing
-   subscriptions
-   multi-tenant enterprise administration

Architect cleanly enough that future integrations are possible, but do
not implement them now.

------------------------------------------------------------------------

# 3. PRODUCT VISION

The application is a personal AI memory system.

Users should be able to capture:

-   quick thoughts
-   voice notes
-   meeting notes
-   project ideas
-   URLs
-   documents
-   screenshots
-   miscellaneous files

The application stores the original material, extracts useful
information, automatically organizes it, identifies relationships, and
makes the resulting memory searchable through natural language.

The product should feel less like maintaining a notes application and
more like talking to a reliable external memory.

Examples:

> What did I decide about the training project?

> Find the fan I was researching last week.

> What ideas have I captured about MineOps?

> I remember writing something about Fusion parameters. Find it.

> What have I said I need to do but haven't finished?

> What changed in my thinking about this project?

------------------------------------------------------------------------

# 4. PRODUCT PRINCIPLES

## 4.1 Capture first

Capturing information must require minimal friction.

## 4.2 Organization is automatic

Manual tagging is optional, not required.

## 4.3 Original sources are immutable

AI-generated interpretation must never replace the source material.

## 4.4 AI claims require provenance

A user must be able to determine why the application believes something.

## 4.5 Search must work even when wording differs

Semantic retrieval is a core requirement.

## 4.6 Time matters

The system should understand that newer information may supersede older
information.

## 4.7 AI is an interpretation layer

Storage and retrieval must remain functional even if the configured AI
provider is unavailable.

## 4.8 Useful beats elaborate

A small system that reliably remembers information is better than an
impressive but unreliable autonomous-agent demo.

------------------------------------------------------------------------

# 5. MVP USER EXPERIENCE

The primary experience should contain five major areas:

1.  Today
2.  Capture
3.  Ask
4.  Memories
5.  Settings

A responsive desktop/mobile web application is required.

The UI should be polished enough for daily use but should not consume
disproportionate development time.

Avoid an enterprise-dashboard aesthetic.

Prefer:

-   generous whitespace
-   readable typography
-   large capture controls
-   simple cards
-   restrained navigation
-   clear source attribution
-   responsive mobile layout

------------------------------------------------------------------------

# 6. TODAY

Today is the application's home screen.

It should answer:

> What from my memory system deserves attention right now?

Include:

## Open Loops

Potential commitments, unfinished tasks, follow-ups, or unresolved
decisions extracted from captured information.

## Recent Memories

Recently captured or recently updated material.

## Resurfaced

Older information selected because it appears relevant or useful.

The resurfacing algorithm may initially be simple and deterministic.

Example factors:

-   age
-   importance
-   unresolved status
-   project relevance
-   recent related activity

Do not require an advanced recommendation model for MVP.

------------------------------------------------------------------------

# 7. CAPTURE

Provide a prominent capture interface.

Supported MVP capture types:

### Typed note

User enters free-form text.

### Voice note

User records audio in the browser.

The application stores the original audio and creates a transcript when
transcription is configured.

### File upload

Support common files including:

-   PDF
-   TXT
-   Markdown
-   DOCX where practical
-   images

Extract text when practical.

### URL

User pastes a URL.

Store the URL and attempt to extract useful page metadata/content when
feasible.

URL ingestion failure must not prevent the URL itself from being saved.

------------------------------------------------------------------------

# 8. INGESTION PIPELINE

All captures should enter a common pipeline.

Conceptually:

``` text
CAPTURE
   ↓
SOURCE
   ↓
TEXT EXTRACTION / TRANSCRIPTION
   ↓
NORMALIZATION
   ↓
AI ANALYSIS
   ↓
ENTITY / TOPIC / ACTION EXTRACTION
   ↓
CHUNKING
   ↓
EMBEDDINGS
   ↓
MEMORY RECORDS
   ↓
RELATIONSHIPS
   ↓
SEARCH INDEX
```

Processing must be observable.

Use states similar to:

``` text
pending
processing
ready
partial
failed
```

A failed AI operation must not destroy the source.

Retries should be possible.

------------------------------------------------------------------------

# 9. SOURCE MODEL

Every captured item creates a Source.

Suggested fields:

``` text
id
type
title
original_text
extracted_text
source_url
file_path
mime_type
created_at
updated_at
captured_at
processing_status
processing_error
metadata
```

Possible source types:

``` text
note
voice
file
url
image
```

Preserve the original source whenever technically possible.

------------------------------------------------------------------------

# 10. MEMORY MODEL

A Memory is an interpreted piece of useful information derived from a
Source.

Suggested fields:

``` text
id
source_id
memory_type
content
summary
importance
confidence
occurred_at
created_at
superseded_by
status
metadata
```

Possible memory types:

``` text
fact
decision
idea
task
question
preference
reference
observation
event
```

These are not required to be perfect.

The data model should permit future expansion.

------------------------------------------------------------------------

# 11. ENTITY MODEL

Automatically identify useful entities such as:

``` text
Person
Project
Organization
Product
Place
Topic
Technology
Document
```

Suggested fields:

``` text
id
entity_type
canonical_name
description
created_at
updated_at
metadata
```

Entity aliases should be supported.

Example:

``` text
MineOps
MineOpsWeb
Mine Ops
```

may eventually resolve to one conceptual entity.

Do not build a complicated entity-resolution engine for MVP.

Use practical normalization plus AI assistance.

------------------------------------------------------------------------

# 12. RELATIONSHIPS

Memories and entities should be connectable.

Suggested relationship structure:

``` text
id
from_type
from_id
relationship_type
to_type
to_id
confidence
source_id
created_at
```

Example relationships:

``` text
memory -> about -> project
person -> involved_in -> project
decision -> supersedes -> decision
task -> related_to -> project
memory -> mentions -> product
```

Relationships should remain traceable to source evidence.

------------------------------------------------------------------------

# 13. OPEN LOOPS

This is a major differentiating feature.

The application should attempt to identify statements representing
unfinished activity.

Examples:

> I need to order the vent.

> Remind me to test this later.

> We still need to wire the fragments bar.

> I should ask Bill about this.

> Need to compare these IDs.

Represent open loops separately or through memory metadata.

Suggested fields:

``` text
id
memory_id
description
status
due_at
confidence
created_at
resolved_at
```

Statuses:

``` text
open
resolved
dismissed
```

The user must be able to mark an open loop resolved or dismissed.

AI extraction should be conservative enough that the Today page does not
become useless noise.

------------------------------------------------------------------------

# 14. TEMPORAL / SUPERSESSION MODEL

The system should support newer information replacing older information
without deleting history.

Example:

Old memory:

> Project will use OCR.

New memory:

> OCR has been removed. Sync is now authoritative.

The old memory remains.

The newer memory can mark or imply that the earlier memory is
superseded.

The UI should be capable of indicating:

> This information may be outdated.

MVP implementation may combine:

-   dates
-   entity/topic overlap
-   contradiction analysis
-   explicit `superseded_by`

Do not attempt perfect automated truth maintenance.

------------------------------------------------------------------------

# 15. ASK --- CONVERSATIONAL MEMORY SEARCH

Provide an Ask interface.

The user enters a natural-language question.

Pipeline:

``` text
QUESTION
   ↓
EMBED QUESTION
   ↓
SEMANTIC RETRIEVAL
   ↓
OPTIONAL KEYWORD FILTERING
   ↓
RELEVANT SOURCES / MEMORIES
   ↓
RERANK / LIMIT
   ↓
LLM RESPONSE
   ↓
SOURCE CITATIONS
```

Answers must be grounded in retrieved memory.

If insufficient evidence exists, the assistant should say so rather than
inventing an answer.

------------------------------------------------------------------------

# 16. PROVENANCE

This is mandatory.

Every AI-generated answer should retain references to the source
material used.

The UI should allow the user to inspect those sources.

Example:

``` text
You decided to remove OCR and rely on synchronized game data.

Sources:
• Project note — July 14
• Voice note — July 16
```

Selecting a source should display the relevant original/extracted
material.

Never present AI interpretation as unquestionable truth.

------------------------------------------------------------------------

# 17. SEARCH

Implement hybrid search where practical:

-   semantic/vector search
-   keyword/full-text search
-   filters

Useful filters:

``` text
source type
date
entity
memory type
status
```

The application should handle vague recollection queries well.

Example:

> that thing I wrote about Fusion cutter parameters

should work even if those exact words do not occur together.

------------------------------------------------------------------------

# 18. MEMORIES BROWSER

Provide a simple browsing interface for:

-   memories
-   sources
-   projects/topics/entities

Users should be able to inspect what the system believes it knows.

Do not require them to organize it manually.

Useful views:

``` text
All
Projects
People
Topics
Decisions
Ideas
Tasks
```

Only implement categories supported reliably by the data model.

------------------------------------------------------------------------

# 19. SOURCE DETAIL

A Source detail page should show:

-   title
-   capture date
-   source type
-   original content
-   extracted/transcribed content
-   generated summary
-   extracted memories
-   entities
-   open loops
-   processing state

This page is important for debugging AI interpretation and maintaining
user trust.

------------------------------------------------------------------------

# 20. MANUAL CORRECTIONS

Allow lightweight correction.

At minimum:

-   rename source
-   edit generated memory
-   dismiss memory
-   resolve/dismiss open loop
-   retry failed processing

Do not implement a sophisticated editorial workflow.

------------------------------------------------------------------------

# 21. AI PROVIDER ABSTRACTION

Do not hard-wire application logic directly to one AI vendor.

Create provider interfaces.

Conceptually:

``` text
AIProvider
  analyzeSource()
  answerQuestion()
  detectRelationships()
```

and:

``` text
EmbeddingProvider
  embedText()
  embedBatch()
```

and:

``` text
TranscriptionProvider
  transcribe()
```

Initial implementations may use an OpenAI-compatible API because many
providers expose that protocol.

Configuration should be environment-driven.

Example:

``` text
AI_BASE_URL=
AI_API_KEY=
AI_MODEL=
EMBEDDING_MODEL=
TRANSCRIPTION_MODEL=
```

Do not commit secrets.

------------------------------------------------------------------------

# 22. NO-AI DEVELOPMENT MODE

The application must be runnable without paid AI credentials.

Implement a deterministic/mock provider.

It should permit:

-   app startup
-   capture
-   persistence
-   browsing
-   testing
-   predictable fake analysis

This is required for autonomous development and CI.

When real AI configuration is absent, clearly indicate development/mock
AI mode.

------------------------------------------------------------------------

# 23. AI STRUCTURED OUTPUT

AI extraction should use structured schemas rather than parsing
arbitrary prose.

Example analysis response:

``` json
{
  "summary": "...",
  "memories": [
    {
      "type": "decision",
      "content": "...",
      "importance": 0.8,
      "confidence": 0.9
    }
  ],
  "entities": [
    {
      "type": "project",
      "name": "MineOps"
    }
  ],
  "openLoops": [],
  "relationships": []
}
```

Validate model output before persistence.

Malformed model responses must fail gracefully.

------------------------------------------------------------------------

# 24. CHUNKING

Long documents should be chunked before embedding.

Chunks must retain:

``` text
source_id
chunk_index
text
embedding
metadata
```

Use sensible overlap.

Do not embed entire large documents as one vector.

------------------------------------------------------------------------

# 25. TECHNICAL STACK

Use a modern TypeScript-first stack.

Preferred architecture:

## Application

``` text
React
TypeScript
Vite
```

## Styling

Use a lightweight modern approach such as:

``` text
Tailwind CSS
```

or an equivalent already well-supported by the selected project tooling.

## Backend

Prefer:

``` text
Node.js
TypeScript
Fastify or Express
```

Choose one and continue.

Fastify is preferred for a new implementation.

## Database

Use:

``` text
PostgreSQL
```

with:

``` text
pgvector
```

for embeddings.

## ORM

Prefer:

``` text
Drizzle ORM
```

or another mature TypeScript ORM if a concrete compatibility issue makes
Drizzle inappropriate.

## Object/file storage

For MVP, implement a storage abstraction.

Development may use local filesystem-backed storage.

Design the interface so S3-compatible storage can be added later.

## Jobs

Do not introduce Kafka, RabbitMQ, or similarly heavy infrastructure.

Use a simple persistent job table/worker pattern.

## Testing

Use appropriate modern TypeScript testing tools.

Prefer:

``` text
Vitest
Playwright
```

where appropriate.

------------------------------------------------------------------------

# 26. REPOSITORY STRUCTURE

Prefer a monorepo.

Example:

``` text
/
├── apps/
│   ├── web/
│   └── api/
├── packages/
│   ├── db/
│   ├── ai/
│   ├── shared/
│   └── config/
├── storage/
├── docs/
├── docker/
├── docker-compose.yml
├── .env.example
├── README.md
└── AUTONOMOUS_BUILD_PRD.md
```

The agent may adjust this if necessary but should not ask permission.

------------------------------------------------------------------------

# 27. API

Create clean REST endpoints.

Suggested areas:

``` text
/api/health

/api/sources
/api/sources/:id
/api/sources/:id/reprocess

/api/capture/note
/api/capture/url
/api/capture/file
/api/capture/voice

/api/memories
/api/memories/:id

/api/entities
/api/entities/:id

/api/open-loops
/api/open-loops/:id

/api/search

/api/ask

/api/settings/status
```

Exact route naming may change if needed.

Document the final API.

------------------------------------------------------------------------

# 28. BACKGROUND PROCESSING

Captures should not require long AI processing during the HTTP request.

Preferred pattern:

``` text
capture request
     ↓
persist source
     ↓
create processing job
     ↓
return source
     ↓
worker processes job
     ↓
UI polls or refreshes status
```

A lightweight worker process is sufficient.

The worker must recover pending jobs after restart.

Implement reasonable retry limits.

------------------------------------------------------------------------

# 29. AUTHENTICATION

This MVP is initially a single-user personal application.

Do not build a full multi-tenant SaaS authentication system.

However, do not expose the application completely unprotected in
production architecture.

Implement a simple authentication mechanism appropriate for a
self-hosted single-user application.

Acceptable options include:

-   local account/password
-   secure session cookie
-   similarly simple proven authentication

Passwords must be hashed appropriately.

Do not invent custom cryptography.

------------------------------------------------------------------------

# 30. PRIVACY AND SECURITY

Required:

-   no API keys in source control
-   `.env.example`
-   uploaded files not publicly exposed by default
-   authenticated file access
-   input validation
-   reasonable upload size limits
-   safe filename handling
-   MIME validation where practical
-   parameterized DB access through ORM
-   HTML sanitization where applicable
-   secure password hashing
-   secure session configuration
-   production secrets supplied through environment

Do not log full sensitive source contents unnecessarily.

------------------------------------------------------------------------

# 31. DELETION

The user must be able to delete a Source.

Deleting a source should also remove or invalidate derived:

-   chunks
-   embeddings
-   memories
-   relationships
-   open loops
-   stored file

Implement this transactionally where practical.

------------------------------------------------------------------------

# 32. OBSERVABILITY

Provide useful logs for:

``` text
capture
processing
AI calls
transcription
embedding
job retries
errors
startup
```

Never log API keys.

Provide a health endpoint.

The UI should display processing failures in a useful way.

------------------------------------------------------------------------

# 33. DOCKER

The entire application must run through Docker Compose.

Target experience:

``` bash
cp .env.example .env
docker compose up -d --build
```

Required services may include:

``` text
web
api
worker
postgres
```

Use health checks and dependency ordering appropriately.

Persistent volumes must be configured for:

-   PostgreSQL
-   uploaded files

A container restart must not erase user data.

------------------------------------------------------------------------

# 34. DEVELOPMENT EXPERIENCE

Also provide a practical local development workflow.

Document:

``` text
install dependencies
start database
run migrations
start web
start API
start worker
run tests
run lint
run typecheck
```

Prefer workspace-level commands.

Example desired commands:

``` bash
npm install
npm run dev
npm test
npm run lint
npm run typecheck
npm run build
```

Exact package manager may be npm, pnpm, or equivalent.

Choose one and use it consistently.

------------------------------------------------------------------------

# 35. DATABASE MIGRATIONS

Database schema changes must be migration-driven.

Do not depend on manually editing a production database.

Provide:

``` text
migration generation
migration execution
migration documentation
```

Fresh installation must work from zero.

------------------------------------------------------------------------

# 36. SEED / DEMO DATA

Provide optional demo data useful for development.

Include examples representing:

-   idea
-   decision
-   task/open loop
-   project
-   person
-   older superseded information

Demo data should make it possible to evaluate search and Today behavior
quickly.

Do not automatically seed demo data into production unless explicitly
enabled.

------------------------------------------------------------------------

# 37. UI DETAIL

## Desktop

Use a simple left navigation or equivalent.

Suggested:

``` text
Today
Capture
Ask
Memories
Settings
```

## Mobile

Use responsive navigation suitable for a phone.

Capture should always be easy to reach.

## Today card examples

``` text
OPEN LOOPS

□ Compare manager IDs
□ Order shop vent
□ Ask Bill about training cohort
```

``` text
RESURFACED

Fusion Cutter Parameters
You were simplifying the parametric cutter workflow.
```

## Ask result

``` text
Q: What did I decide about OCR?

You decided to remove OCR from the project and use synchronized
game data as the authoritative player-data source.

Sources
[Project note · Jul 14]
[Voice note · Jul 16]
```

------------------------------------------------------------------------

# 38. SETTINGS

MVP settings should include:

-   AI configuration status
-   current AI model
-   embedding model
-   transcription configuration
-   mock/real AI mode
-   storage status
-   database status
-   app version/build information

Do not expose secret API key values after configuration.

Environment configuration is sufficient for the initial MVP.

------------------------------------------------------------------------

# 39. ERROR STATES

Design explicit UX for:

-   AI unavailable
-   transcription unavailable
-   embedding unavailable
-   URL extraction failed
-   unsupported file
-   processing failed
-   source partially processed
-   no search results
-   insufficient evidence for answer

Partial functionality is preferable to losing a capture.

Example:

> Saved successfully. AI analysis is temporarily unavailable.

------------------------------------------------------------------------

# 40. TESTING REQUIREMENTS

Tests are part of the product, not optional cleanup.

## Unit tests

Cover important logic including:

-   structured AI output validation
-   chunking
-   open-loop handling
-   source status transitions
-   mock AI provider
-   deletion cascade logic
-   search result normalization

## Integration tests

Cover:

``` text
capture note
process source
generate memory
search memory
ask question
return source provenance
delete source
```

## E2E

At minimum automate a core user journey:

``` text
login
capture note
wait for processing
view memory
search for it
ask about it
inspect source citation
```

Use mock AI mode for deterministic CI.

------------------------------------------------------------------------

# 41. QUALITY GATES

Before declaring completion, all applicable commands must pass.

Equivalent of:

``` bash
npm run lint
npm run typecheck
npm test
npm run build
```

Run E2E tests.

Then test Docker from a clean state.

Do not declare the project complete with known compilation failures.

------------------------------------------------------------------------

# 42. MVP ACCEPTANCE TEST

The build is successful when a fresh user can perform this sequence:

1.  Start the stack using documented instructions.
2.  Log into the application.
3.  Capture:

``` text
I decided that Project Atlas will use PostgreSQL instead of SQLite.
I still need to migrate the old records this weekend.
```

4.  Processing completes.
5.  Application creates useful interpreted data including:

``` text
Project Atlas
decision about PostgreSQL
open loop concerning migration
```

6.  Today displays the migration open loop.
7.  Search for:

``` text
Atlas database
```

returns the captured information.

8.  Ask:

``` text
What database did I choose for Project Atlas?
```

returns an answer equivalent to:

``` text
PostgreSQL
```

9.  The answer links to the original source.
10. Opening the source shows the original captured text.
11. The open loop can be marked resolved.
12. The source can be deleted.
13. Derived information disappears appropriately.

This entire flow must work.

------------------------------------------------------------------------

# 43. SECOND ACCEPTANCE TEST --- SUPERSESSION

Capture:

``` text
Project Atlas will use SQLite because it is easy to deploy.
```

Then capture a newer source:

``` text
I changed my mind about Atlas. We are using PostgreSQL instead of SQLite.
```

Expected behavior:

-   both sources remain accessible
-   PostgreSQL should be treated as the newer decision
-   the system should avoid confidently answering SQLite as the current
    choice
-   where feasible, the older decision should be marked potentially
    superseded
-   provenance should make the history understandable

Perfect contradiction detection is not required, but the architecture
and implementation must demonstrate the concept.

------------------------------------------------------------------------

# 44. THIRD ACCEPTANCE TEST --- FAILURE RESILIENCE

Disable real AI access or intentionally use mock mode.

Capture a source.

Expected:

-   source is saved
-   application remains usable
-   processing state is understandable
-   retry/reprocess exists
-   no source data is lost
-   application does not crash

------------------------------------------------------------------------

# 45. DOCUMENTATION DELIVERABLES

At completion provide:

## README.md

Include:

-   product overview
-   screenshots if practical
-   architecture summary
-   prerequisites
-   local development
-   Docker startup
-   environment variables
-   migrations
-   tests
-   AI provider configuration
-   storage
-   backup considerations

## docs/ARCHITECTURE.md

Explain:

``` text
frontend
API
worker
database
AI abstraction
ingestion
retrieval
provenance
storage
```

## docs/DECISIONS.md

Record significant decisions made autonomously.

Use concise ADR-style entries.

## docs/KNOWN_LIMITATIONS.md

Be explicit about limitations.

Do not disguise unfinished features.

------------------------------------------------------------------------

# 46. BACKUP / PORTABILITY

This is a personal memory system, so data portability matters.

For MVP:

-   document how PostgreSQL can be backed up
-   document where uploaded files are stored
-   keep storage formats straightforward
-   avoid unnecessary proprietary lock-in

If inexpensive to implement, provide a simple JSON export of sources and
memories.

Do not delay core MVP completion for a sophisticated export engine.

------------------------------------------------------------------------

# 47. PERFORMANCE TARGETS

This is initially a single-user application.

Optimize for correctness and simplicity rather than massive scale.

Still avoid obvious scaling traps.

Target:

-   thousands of sources without architectural redesign
-   chunked retrieval rather than loading all memory into the LLM
-   database indexes on common query fields
-   vector index appropriate for expected scale
-   pagination on browsing endpoints
-   bounded AI context

------------------------------------------------------------------------

# 48. COST CONTROL

AI cost matters.

Implement reasonable safeguards:

-   do not re-embed unchanged content
-   do not re-analyze unchanged sources
-   hash or version processed content
-   batch embeddings when supported
-   limit retrieval context
-   cap output tokens
-   avoid AI for deterministic operations
-   make expensive reprocessing explicit

Track enough metadata to diagnose model usage.

Do not build a complex billing system.

------------------------------------------------------------------------

# 49. FUTURE CAPABILITIES --- ARCHITECT FOR, DO NOT BUILD

Potential future additions:

``` text
email ingestion
calendar integration
browser extension
mobile share sheet
native apps
watch capture
automatic meeting recording
OCR improvements
image understanding
contact integration
scheduled resurfacing
notifications
multi-user sharing
knowledge graph visualization
local LLM support
agentic task execution
MCP/connectors
cloud sync
S3 storage
```

Do not implement these during the autonomous MVP build unless they
become technically necessary for a core requirement.

------------------------------------------------------------------------

# 50. PRODUCT DIFFERENTIATORS

When implementation choices conflict, prioritize these capabilities:

## Zero-maintenance organization

The user should not need to design their own information architecture.

## Provenance

The system can show where a memory came from.

## Open loops

The system notices unfinished intentions.

## Temporal understanding

The system can recognize that thinking changes.

## Search by recollection

The user does not need to remember exact titles or wording.

## Durable source ownership

Original information remains accessible independent of AI
interpretation.

------------------------------------------------------------------------

# 51. NON-GOALS

The MVP is not:

-   Notion
-   a document editor
-   a project-management suite
-   a todo application
-   a calendar
-   a social network
-   a team wiki
-   an autonomous general-purpose agent
-   a replacement for source files

It is:

> **A low-friction capture and AI-assisted personal memory retrieval
> system.**

------------------------------------------------------------------------

# 52. IMPLEMENTATION ORDER

Use this as guidance, not as approval checkpoints.

Proceed continuously.

### Stage 1 --- Foundation

-   repository
-   workspace
-   TypeScript configuration
-   database
-   migrations
-   Docker
-   health endpoint

### Stage 2 --- Core data

-   Source
-   Chunk
-   Memory
-   Entity
-   Relationship
-   OpenLoop
-   ProcessingJob

### Stage 3 --- Capture

-   notes
-   files
-   URLs
-   voice recording
-   storage

### Stage 4 --- Processing

-   extraction
-   chunking
-   AI provider
-   mock provider
-   embeddings
-   entity/memory extraction
-   open loops

### Stage 5 --- Retrieval

-   semantic search
-   keyword search
-   hybrid results
-   Ask/RAG
-   provenance

### Stage 6 --- UI

-   authentication
-   Today
-   Capture
-   Ask
-   Memories
-   Source detail
-   Settings

### Stage 7 --- Temporal behavior

-   supersession support
-   outdated-memory indication
-   resurfacing

### Stage 8 --- Hardening

-   validation
-   errors
-   retries
-   deletion
-   security
-   tests

### Stage 9 --- Delivery

-   clean Docker test
-   E2E acceptance tests
-   documentation
-   known limitations
-   final report

Do not stop between stages for user approval.

------------------------------------------------------------------------

# 53. AUTONOMOUS DECISION POLICY

When encountering an unspecified decision, use this hierarchy:

1.  Protect user data.
2.  Preserve original sources.
3.  Prefer simple proven technology.
4.  Prefer maintainability.
5.  Prefer deterministic behavior over unnecessary AI.
6.  Prefer local/self-hostable infrastructure.
7.  Prefer open formats.
8.  Minimize external services.
9.  Minimize ongoing cost.
10. Continue implementation.

If two options are roughly equivalent, choose one and proceed.

Do not spend excessive tokens debating minor alternatives.

------------------------------------------------------------------------

# 54. DEFINITION OF DONE

The project is done when:

-   application starts successfully
-   authentication works
-   typed capture works
-   voice capture path works
-   file capture works
-   URL capture works
-   original sources are retained
-   processing pipeline works
-   mock AI works
-   real AI provider abstraction exists
-   memories are generated
-   entities are generated
-   open loops are generated
-   semantic retrieval works
-   Ask works
-   provenance works
-   Today works
-   source detail works
-   open loops can be resolved
-   failed processing can be retried
-   source deletion cleans derived data
-   supersession behavior is demonstrated
-   responsive UI is usable
-   Docker Compose works
-   migrations work from a clean database
-   lint passes
-   typecheck passes
-   tests pass
-   production build passes
-   E2E acceptance flow passes
-   documentation exists

If a requirement cannot be completed because of a genuine external
dependency, document it precisely and complete everything that does not
depend on it.

------------------------------------------------------------------------

# 55. FINAL AGENT INSTRUCTION

Begin by reading this entire document and inspecting the repository.

Create a concise internal implementation plan and then execute it.

Do not return to the user merely to present the plan.

Do not ask for approval between phases.

Do not stop because a routine implementation decision is ambiguous.

Make the decision, record significant choices, and continue.

Use mock/local substitutes where external credentials are unavailable.

Run the application.

Test it.

Fix it.

Run the acceptance scenarios.

Document it.

The final response to the user should contain only information useful
for taking possession of the completed MVP:

-   completion status
-   how to run/open it
-   credentials/setup steps the user actually needs
-   major implemented capabilities
-   tests/quality-gate results
-   genuine remaining limitations or blockers

The objective of this experiment is not to demonstrate how much code an
agent can generate.

The objective is to determine whether an autonomous coding agent can
take a well-defined product specification and deliver a coherent, usable
application with minimal human supervision.

**Proceed until the MVP is operational.**
