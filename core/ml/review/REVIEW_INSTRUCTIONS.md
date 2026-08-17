# CT-1 content review — instructions for reviewers

You have been given one HTML file. Open it in a browser. There is nothing to
install and nothing to connect to.

This document is the procedure around it: what you are being asked, what you
are explicitly *not* being asked, and what happens to your answers.

---

## What this work is for

The catalogue has around 1,900 exercise entries in two languages. A set of
deterministic rules currently flags some of them as suspect. Nobody has ever
checked whether those rules are right, and nobody has ever checked how much
they miss — so every quality number this project could report today would be
the rules agreeing with themselves.

Your answers are the first independent measurement. 180 rows, drawn
deliberately rather than at random, split across three reviewers.

## What you are NOT being asked

**You are not being asked whether an exercise is safe.**

Not whether it is safe in general, safe for a beginner, safe for someone with
an injury, medically advisable, or clinically correct. No question on the page
asks this, and if you find yourself answering it, stop — the answer would be
recorded as a content-quality label and read later by someone who does not know
you meant something else.

That judgement requires clinical authority this project does not have. It is
tracked separately as `D1 = EXTERNAL_CLINICAL_VALIDATION_REQUIRED` and
`H3 = HOLD`, and nothing you do here can close either. There is no way to
produce a clinical label from this tool; that is enforced in code, not by
asking you to be careful.

If a row worries you for a reason the questions do not cover, tick **"Needs
someone with domain knowledge to look at this"** and write a note. That routes
it out of content QA to a person qualified to judge it. It is not a verdict.

## What you are being asked

Eight questions per row. Every one is a comparison between two things visible
on your screen — the title against the steps, the steps against the equipment,
the Russian against the English. You do not need to know anything about
exercise to answer them. You need to read.

| Question | What it means |
|---|---|
| Title matches content | Does the title describe the movement the steps describe? |
| Content is complete | Anything obviously missing or cut off mid-sentence? |
| Structure is consistent | Sensible order, not repeated, formatting intact? |
| Instructions are consistent | Do steps and tips agree with each other? |
| Content is not duplicated | Specific to this entry, or copied from another? |
| Equipment matches content | Does the listed equipment match what the steps use? |
| Localisation is faithful | Does the Russian say the same thing, and is it translated at all? |
| Metadata matches content | Do muscles, difficulty and the stretch flag fit? |

Each takes one of three answers:

- **OK** — you looked and it is fine.
- **Problem** — something is wrong. You must then tick at least one reason
  code saying what.
- **Unsure** — you cannot tell from what is in front of you.

**Use Unsure freely.** It is not a failure to answer. A forced guess enters the
dataset looking exactly like a considered judgement, and there is no way to
tell them apart afterwards. Unsure is recorded as an abstention and never
counted as either answer.

### Reason codes

When you mark a problem, tick every code that applies. If none fits, tick
**"Something else"** and write a note — that is required, and it is how we find
out the vocabulary is incomplete rather than watching people force a near-miss
code.

### Skipping

**Skip this row** records that you looked and chose not to answer. It is
different from not opening the row at all: an unopened row comes back as
*unknown*, and unknown is never counted as clean.

---

## What you must not do

**Do not compare notes with the other reviewers while you work.**

Some rows are deliberately given to two people. Your file does not tell you
which ones, and that is on purpose — a reviewer who knows a row is being
double-checked answers it differently, and then the agreement figure measures
the marking rather than the work. Discussing rows in progress destroys the
measurement entirely.

**Do not use an AI assistant to answer for you.**

Not as a first pass, not to speed up the boring rows, not "just to check". The
entire value of this batch is that it is *not* machine output — a model's
answers here would be a slightly noisier copy of the rules we are trying to
measure, and the measurement would come out looking excellent and mean nothing.

There is no technical way to detect this. The import refuses obviously
machine-shaped reviewer names, and that catches carelessness, not intent. This
one is on you.

**Do not look anything up to decide.** If the row does not contain the evidence,
the answer is Unsure. That is the correct answer, not a cop-out.

---

## Practical notes

- **Your work saves automatically** in the browser, on every change. You can
  close the tab and come back. Do not clear site data, and do not switch
  browsers halfway.
- **Take breaks.** Sixty-plus rows in one sitting produces a measurable drop in
  quality around the middle, and we would rather have your judgement than your
  endurance.
- **When you are done**, type your name at the bottom, press **Export
  submission**, and send the downloaded file back. The file contains only your
  answers and the ids of the rows you saw.

## What happens to your answers

They are validated on import. The importer will refuse a submission — not
silently repair it — if it is for the wrong batch, from an unassigned reviewer,
partially answered, or missing a reason code on a problem.

One case is worth knowing about: if a catalogue row **changed** after your file
was generated, your review of it is marked `RE_REVIEW_REQUIRED` rather than
imported. You judged text that is no longer there. That is not a mistake on
your part and you may be asked to look at that row again.

Where two reviewers disagree, **nothing is resolved automatically.** No majority
rule, no first-answer-wins, no tie-break. It goes to a third person who has not
seen either answer. If they cannot decide either, it is recorded as unresolved
and excluded from the evaluation set — an honest gap rather than a manufactured
consensus.

Your name is recorded against your labels. Aggregate agreement figures may be
reported; your individual answers are not published as a performance measure,
and disagreement is expected and useful rather than a mark against anyone.

---

## Questions

Ask before guessing, and ask about the *procedure* rather than about a specific
row — a discussion about how to judge row 0417 is a discussion that
contaminates row 0417 for whoever else has it.
