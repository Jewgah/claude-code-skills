---
name: choices
description: Summarize the open decisions/choices from the current conversation into a simple, copy-paste WhatsApp message for the team to weigh in on. Use when work is blocked on product/scope decisions a human must make.
---

# Choices - WhatsApp decision summary

Generate a concise, copy-paste WhatsApp message (English) that lists the open
decisions the team needs to make, based on the current conversation. This is the
sibling of `/explain-dev` (which announces *finished* work in French): `/choices`
surfaces *pending* decisions in English so the team can pick.

## The audience is ALWAYS the client

Every `/choices` message is written to be forwarded to the CLIENT (the partner or
stakeholder who pays for the work), never to an internal dev channel. Write it as
if the client is reading every line, because they are. Two consequences that are
easy to get wrong:

- **Address the client in the second person.** If a named person owes an answer
  and that person is the recipient, write "you answered 1 to 4 in July but not
  this one", never "Alex answered 1 to 4". Third-personing the reader is an
  instant tell that the message was written for someone else.
- **Money questions: ask what is theirs to decide, never what is mine.** The line
  is who the decision belongs to, not whether money is mentioned.
  - **Legitimate** (the client genuinely decides): approving a quote for upcoming
    work, which period to bill something to, whether to authorise more spend, how
    to prioritise a fixed envelope. Put these in plainly, with a number when I
    have one.
  - **Never** (mine alone): whether I gift, absorb, discount or write off work,
    my margin, my capacity, my internal hour estimates. "Should I gift you the
    overage?" is nonsense addressed to the person paying.
- **When the client has said "build everything", a scope question is not a
  choice, it is a quote.** Do not re-offer a phased menu they already declined.
  State what will be built and give the number, framed for approval.

The test for every line: would I be comfortable if the client screenshotted this
line back to me? If not, it belongs in my reply to the user, not in the message.

## Steps

1. Scan the conversation for every UNRESOLVED choice a human must make: forks,
   trade-offs, assumptions awaiting confirmation, "we could do X or Y", and any
   decision you were about to ask (e.g. an AskUserQuestion you queued). Include
   the scope/"how much to build" decision when relevant.
2. For each, distil to a plain-language either/or (or 2-3 short options). Strip
   the technical detail - frame each by user/business impact, not implementation.
3. Merge duplicates; order by importance (the choice that most changes the build
   goes first).
4. Add a one or two line plain-language context at the top so the message stands
   alone for someone who wasn't in the conversation.
5. End by inviting their answers.

## Argument

`$ARGUMENTS` is an optional topic/focus - when given, scope the message to decisions
about that topic. When empty, cover all open decisions in the conversation.

## Format rules

- English. WhatsApp formatting: `*bold*` for the title and each numbered choice
  label. No markdown headers, no `#`, no code, no bullet characters - use `-`.
- First line is the title: `*<Topic> - decisions needed*`
- Then one or two lines of plain context (what this is about, in one breath).
- Number each choice in `*bold*` with a short label, then 1-2 short dashed lines
  giving the options as a clear either/or.
- Keep each choice to ~1-2 lines. NO jargon: no file names, functions, code, and
  not the words "API", "database", "schema", "endpoint", "backend", "migration".
- Always write in the first-person SINGULAR. Use "I / me / my" (and in French
  "je / ma reco / mon hypothèse"), never the plural "we / our / us" ("nous /
  notre / on"). E.g. "my reco", "my assumption", "I'll lock the scope".
- If there's a sensible default, you may note it briefly, e.g.
  "(my assumption: …, confirm?)" - but keep the choice open.
- No emojis. NEVER use an em dash (U+2014), en dash (–) or arrow (→); these read as
  AI-written. Use a comma, parentheses, the word "vs", or "to" instead.
- End with one short line inviting answers (e.g. "Send your answers and I'll lock
  the scope and start building.").
- Output ONLY the message - no preamble, no explanation, no recap of the work.
- Keep it tight: aim for under ~25 lines total.

## Example output

*Team invites - decisions needed*

Quick context: right now anyone with the link can join a workspace. We want to control who gets in, and that opens a few questions worth settling before I build it:

*1. Who can invite*
- Only workspace owners? Or any existing member?

*2. How someone joins*
- They receive an email invite and set a password? Or they request access and an owner approves?

*3. What a new member can see*
- My assumption: everything in the workspace except billing. Confirm that's right?

*4. Invites that go unanswered*
- Should an invite expire after a week, or stay open until someone cancels it?

*5. Removing someone*
- When a member is removed, does their work stay in the workspace or leave with them?

*6. How much to build first*
- A simple version (owner invites by email, one permission level) and add roles later? Or the full permission system in one go?

Send your answers and I'll lock the scope and start building.
