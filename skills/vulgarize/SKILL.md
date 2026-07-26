---
name: vulgarize
description: Turn the technical changes in the working tree into a short, casual, jargon-free message you can send straight to the client (en/fr)
argument-hint: "[lang: en (default) | fr] [optional context]"
---

# Vulgarize — plain-language summary of what changed

Produce a simple message for a **non-technical client** summarising the code changes. It reads like
the developer texting the client directly, not like a release note.

**Language:** `en` by default. If `$ARGUMENTS` starts with `fr`, write it in French, casual and
informal (tutoiement, no polite formulas). Everything else below is identical.

> Sibling skill: `/explain-dev` produces a *structured* WhatsApp update (bold numbered points + a
> numbered "How to test" section). **This** one produces a flowing, casual text message. Pick by
> how formal the recipient is.

## Steps

1. **Read the changes**: look at the git diff (staged + unstaged) and recent commits to understand
   what actually changed.
2. **Find the "why"**: for each change, identify the concrete impact for the user or the business.
3. **Write the message** following the rules below.

## Writing rules

- **First person, speaking directly to them**: "I did…", "I added…" — as if you are the developer
  talking TO the client. Never refer to the client in the third person ("the client asked…"). Say
  "you mentioned that…" when referencing feedback you got.
- **No technical jargon**: no file names, function names, variable names, component names. Ever.
- **Casual tone**: like a WhatsApp/Slack message. No formal salutations, no sign-off boilerplate.
- **Explain the WHY, not just the what**: e.g. "that way the numbers are frozen at the moment the
  order is accepted, so they can't drift afterwards".
- **Group logically**: merge related changes into one flowing explanation rather than listing them
  file by file.
- **If a technical concept is unavoidable**, explain it in parentheses: "a snapshot (a frozen copy)".
- **No bullet lists, no markdown**: plain text, it's a message not a document.
- **Short and direct**: no "here's what I did" preamble. Get straight to it.
- **NEVER use an em dash (—), en dash (–) or arrow (→)** — they read as AI-written. Use a comma, a
  period, parentheses, or the word "to" instead.

## Output format

Two paragraphs:

1. **What changed and why** (rules above).
2. **How to test**: one or two plain sentences on how they can check it themselves, no jargon.
   E.g. "to check it, log in and open any order, the total should stay the same after you refresh".

Output ONLY the message, ready to copy-paste and send. No commentary, no "here's the message:".

## Example

**Technical changes (input)**

- Clear the tax-number field when the company country changes
- Store a snapshot of the buyer and seller details when the order is created
- Refresh those snapshots on payment retry
- Build the invoice from the stored snapshot instead of re-reading live data

**Client message (expected output)**

ok so here's what I did:
when the company country changes I now clear the tax number, since it doesn't apply anymore
I save a copy of the buyer and seller details the moment the order is created (a snapshot)
and the invoice is now built from that copy instead of re-reading everything later
that way the details are frozen at the moment the price is accepted and can't shift afterwards
if a payment is retried I refresh that copy once the payment goes through, because the amount is
recalculated at that point

to check it, create an order then change the company details afterwards, the invoice should still
show the details as they were when the order was placed

$ARGUMENTS
