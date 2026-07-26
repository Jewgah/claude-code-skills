---
description: Write a WhatsApp-ready, non-technical message explaining a development to the client
argument-hint: "[lang: en (default) | fr] — optionally followed by what to cover"
---

Write a concise, non-technical, copy-paste-ready WhatsApp message explaining the development
discussed or delivered in this conversation. Translate technical work into client benefits.

**Language:** `en` by default. If `$ARGUMENTS` starts with `fr`, write it in French instead, using
the French strings in the table below. Everything else about the format is identical.

**Step 1 — determine the dev's STATUS before writing anything.** Scan the conversation for signs it
is ALREADY shipped (commit made, pushed, merged, deployed, delivered, tests green in prod) versus
only PLANNED/discussed. The status drives the whole message:

- **Already shipped** → past/present tense ("I added…", "the form now has…", "you can now…").
  Never future or conditional. The test section is titled *How to test* — it's live, so never
  "once delivered".
- **Planned** → near-future tense, and the test section keeps the "once delivered" title.
- **When in doubt** (no sign of delivery), treat it as PLANNED.

**Step 2 — build the message.**
1. Identify the tasks/features involved.
2. Group them by theme when it helps.
3. Turn each technical task into a client/user benefit.
4. Add a short test section describing how the client checks it themselves.

## Fixed strings

| Slot | English | French |
|---|---|---|
| Greeting (shipped) | `*Update delivered - [Theme]*` | `*Mise a jour livree - [Thème]*` |
| Greeting (planned) | `*Update planned - [Theme]*` | `*Mise a jour prevue - [Thème]*` |
| Test title (shipped) | `*How to test*` | `*Comment tester*` |
| Test title (planned) | `*How to test once delivered*` | `*Comment tester une fois livre*` |
| Closing line | `Don't hesitate if you have any questions.` | `N'hesitez pas si vous avez des questions.` |

## Format rules

- WhatsApp formatting only: `*bold*` for titles. No markdown headings.
- Open with the greeting line for the detected status (table above).
- List each major change as a `*bold*` number followed by 1-2 explanatory dashes.
- Keep dashes SHORT (1 line max) in language a non-technical reader understands.
- End with the test section, then the closing line.
- NO technical jargon: no file names, no function names, no code, no "API", no "script", no
  "migration", no "database", no "SQL", no "bug fix".
- No emojis.
- NEVER use an em dash (—), en dash (–) or arrow (→) — they read as AI-written. Use a comma, a
  period, parentheses, or the word "to" instead.
- ~25 lines maximum. Stay concise but leave room for the test section.
- Output ONLY the message. No preamble, no explanation, no commit hashes, no ticket links.

## Test-section rules

- **Impersonal tone**: no "you". Actions in the infinitive ("open the tab", "click the button",
  "fill in the field"). Expected results impersonal ("the status should change to…", "a message
  should appear…").
- No technical jargon.
- Simple numbering ("1.", "2.", …), one line per step where possible.
- Cover the main path plus 1-2 important edge cases if relevant.
- 3 to 5 steps max — it's a WhatsApp message, not a full guide.
- No closing formula inside this section; the global closing line follows immediately.

## Example output (planned, English)

*Update planned - Reporting tabs*

*1. Multi-operation handling*
- Each operation in a file will get its own reporting form
- No more single shared form, information can be entered per operation

*2. New end-of-work fields*
- Clickable lot number to jump straight to that lot's operations
- A "Sampled" field (Yes/No) for quality tracking

*How to test once delivered*

1. open a file with several operations and check that each operation has its own form

2. enter different information per operation and save, each operation should keep its own values

3. click the lot number in the reporting tab, the page should open that lot's operations directly

4. set "Sampled" to Yes then to No, the value should be kept after saving

Don't hesitate if you have any questions.

$ARGUMENTS
