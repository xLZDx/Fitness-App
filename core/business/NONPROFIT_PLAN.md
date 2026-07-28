# Nonprofit Plan — Mission-Driven Fitness App

**As of 2026-05-10.** Strategic plan for operating the Fitness App as a
non-profit organisation. Paid subscriptions still exist — they are
the recurring funding stream that sustains the project — but they are
**donations to the mission, not commercial purchases**, and every
external cost gets re-evaluated through the nonprofit lens. Celebrity
content is contributed as in-kind donations, not paid deals.

This doc supersedes the for-profit assumptions in
[`../plans/ROADMAP_2026_V2.md`](../plans/ROADMAP_2026_V2.md) and the
[`COMPETITIVE_ASSESSMENT.md`](COMPETITIVE_ASSESSMENT.md) pricing
analysis. Cross-reference both for technical and competitive detail;
this doc focuses on the *funding model + cost structure + go-to-market*
shifts the nonprofit pivot enables.

---

## Executive summary

**Five things change vs the for-profit roadmap:**

1. **Total external spend to ship a credible v1 drops from ~$50–80k to
   ~$1,000–2,000.** Celebrity signing ($30–80k) is replaced by
   in-kind content donations (tax-deductible for the donor, $0 to us).
   Physio review ($5k) is replaced by an ATC contractor at $1k for
   testnet, upgraded to a pro-bono DPT board member by public launch.
   Wear OS gets deferred behind a phone lock-screen widget (3 days of
   eng vs ~$0 either way; not affected by nonprofit status).

2. **Subscriptions become recurring donations.** Same Stripe flow,
   different framing + lower fees: Stripe.org gives 2.2% + $0.30 to
   verified 501(c)(3)s vs 2.9% + $0.30 standard. Tax receipts
   auto-generated. Critical messaging: *"Your subscription is
   tax-deductible (US) and funds free access for users who can't
   afford to donate."* Trust + tax + mission narrative all work
   together.

3. **Cloud + dev tooling becomes essentially free.** Google for
   Nonprofits = $10k/year Cloud credits (covers Firebase + Functions
   for a long time). Microsoft for Startups Founders Hub for
   nonprofits = $150k Azure credits over 4 years. Apple Developer
   Program waives the $99/year fee for nonprofits. GitHub Team plan
   becomes free. **Year-one infrastructure cost: $0.**

4. **Celebrity outreach completely reframed.** "Sign a celebrity for
   $30–80k" becomes *"would you donate a 30-minute workout video to a
   nonprofit serving people with injuries who can't afford a
   trainer?"*. Way easier ask. Tax-deductible for the donor at fair
   market value (~$5k–50k of value depending on their typical rate).
   Many celebrities prefer the donation route — better PR, no
   commercial-endorsement awkwardness.

5. **Funding diversifies.** Recurring donations from app subscribers +
   one-time donations + grants (Robert Wood Johnson Foundation,
   Mozilla Foundation, NIH SBIR for digital health) + corporate
   sponsorship (gym equipment OEMs, insurance partners) + fiscal
   sponsorship if we don't want to incorporate immediately. **No
   single funding source >40% of total — sustainable, resilient.**

---

## Why nonprofit makes strategic sense (beyond the cost angle)

### 1. The mission is genuinely defensible

Our 34-question intake + injury-aware filtering is built around the
premise that *"safe exercise should be available to everyone — not
just people who can afford a personal trainer."* That's a mission, not
a marketing claim. Every structural choice can flow from it:

- Free tier is full-featured (no feature paywalls, just optional
  donation incentives)
- Open contraindication tagging methodology (publish the rules; let
  PTs improve them)
- Open exercise catalog format (can be forked, re-used, audited)
- Privacy-first: no ad networks, no data sales, ever

### 2. Trust + viral loop

Users recommend nonprofits to friends 3.5× more often than for-profits
(Stanford 2023 study). The "100% donation-funded, no ads, no data
sales" pitch lands hard with the segment that's tired of fitness apps
dark-patterning them. Especially powerful for the **Patient/clinical
referral** funnel — physiotherapists *will* recommend a nonprofit
injury-aware app to patients; they won't recommend a $19.99/mo
celebrity tier.

### 3. Cost structure unlocks moves no for-profit can match

Stripe.org's 2.2% fee + Google for Nonprofits' $10k/year of credits +
Apple's $0 Dev Program means our marginal cost per user is ~$0.05–0.20
in 2026 dollars. A for-profit competitor with the same scale pays
$2–5 per user. This isn't decisive on its own but it means we can
serve free-tier users sustainably indefinitely.

### 4. Celebrity outreach radically easier

A fitness celebrity asked for $30k + revenue share by a startup =
multi-week negotiation, talent agency, lawyers. Same celebrity asked
to donate one 30-minute workout video to a nonprofit serving
underserved users = email + DocuSign in 2 weeks. Tax-deductible
donation at fair market value (~$5–50k of declared value, no cost to
us). Many will say yes who would never sign a commercial deal.

---

## Legal structure — two paths

### Path A: Form a 501(c)(3) directly (US)

**What it is:** Incorporate as a nonprofit in a state (Delaware or
Wyoming are common; California has stricter rules), then apply to the
IRS for 501(c)(3) status.

**Cost breakdown:**
- State incorporation filing: $50–500 depending on state
- IRS Form 1023-EZ (small orgs, <$50k revenue) filing fee: $275
- IRS Form 1023 (larger orgs): $600
- Registered agent service (annual): $0–300
- Optional: Cobalt or Harbor Compliance to handle paperwork: $500–2,000
- **Total: $325–$3,500 over 3–6 months**

**Requirements:**
- Board of directors: minimum 3 unrelated people in most states
- Bylaws + conflict-of-interest policy (template-able from BoardSource)
- Annual Form 990 IRS filing (Form 990-N postcard if revenue <$50k —
  free)
- State annual filings (varies; ~$10–100/year)

**Timeline:** 3–6 months from filing to IRS determination letter (the
"approved 501(c)(3)" status). You can solicit donations during this
period under "501(c)(3) status pending" but tax-deductibility for
donors waits for the determination.

### Path B: Fiscal sponsorship (faster, cheaper to start)

**What it is:** A friendly existing 501(c)(3) "sponsors" your project.
You operate under their tax-exempt umbrella; they handle the legal
overhead; you focus on the product.

**Cost:** Typically 5–10% of donations as the sponsor's overhead fee.
No incorporation costs.

**Examples that sponsor digital-health / fitness projects:**
- **Open Collective Foundation** (defunct as of 2024 — but successors
  like Open Source Collective + the Software Freedom Conservancy
  exist)
- **The Center for Innovation & Engagement** — focuses on health and
  wellness nonprofits
- **Code for America** — adjacent civic-tech but hosts public-good
  projects
- **Player's Health** — sports + health-tech fiscal sponsorship

**Timeline:** 2–4 weeks to onboard. Tax-deductibility starts
immediately. You can graduate to your own 501(c)(3) later when you
have steady revenue.

**Recommendation:** Start with **fiscal sponsorship** so you can
solicit donations + apply for grants within a month. File for
independent 501(c)(3) once you have 6+ months of operating data
demonstrating viability. The 5–10% overhead is genuinely cheap for the
acceleration it buys.

---

## Funding model

Five complementary streams. None should exceed 40% of total budget for
sustainability.

### Stream 1: Recurring donations (subscriptions)

Same Stripe flow we already built; reframed copy.

| Plan | Suggested monthly | Suggested annual | What we tell donors |
|------|-------------------|------------------|---------------------|
| Free | $0 | — | Full app, every feature. No ads. No data sales. |
| Supporter | $9.99 | $99 | "Funds 5 free users per month for someone who can't donate" |
| Sustainer | $19.99 | $199 | "Funds 12 free users + helps us add new safety-reviewed exercises" |
| Champion | One-time | $499 | "Lifetime member; funds 30 free users + your name on the donor wall" |

**Tax-deductibility (US):** every dollar above the fair market value of
what the donor receives. Since the free tier is identical to the paid
tiers, **the entire subscription is tax-deductible** (up to IRS
limits). Subscriptions with paywalled premium features only have the
premium-feature delta as taxable; ours doesn't have that problem.

**Stripe.org integration:** verified 501(c)(3)s get 2.2% + $0.30 vs
2.9% + $0.30 standard. Saves ~$840/year per 1,000 monthly subscribers
at $10/mo. They also handle automatic tax-receipt emails — required
for IRS compliance.

**Estimated revenue (year 1 conservative, 1,000 free users → 50 paying):**
- 30 Supporters × $99/yr = $2,970
- 15 Sustainers × $199/yr = $2,985
- 5 Champions × $499 = $2,495
- **Total: $8,450 / yr from subscriptions alone**

**Year 3 target (10,000 free users → ~500 paying):** ~$85,000 / yr.

### Stream 2: One-time donations

Donor button on the app + landing page. Stripe Checkout one-time
payment. Auto-emailed tax receipt with EIN.

**Where to seek:**
- Existing app users (in-app "donate" prompt that doesn't gate
  features)
- GoFundMe Charity / JustGiving for one-off campaigns
- Year-end appeals (December has the highest donation rate of any
  month due to tax deadlines)

**Estimated:** $5,000–10,000 / yr at year-1 scale.

### Stream 3: Grants

The single highest-leverage funding stream. Apply to multiple. Don't
expect any single grant; expect 1-in-5 success rates.

| Grant source | Typical size | Focus | Why we fit |
|---|---|---|---|
| **Robert Wood Johnson Foundation** | $25k–500k | Health equity, disease prevention | Free tier serving users without insurance access to PT |
| **NIH SBIR (Small Business Innovation Research)** | $50k–1.7M | Digital health technology | The injury-prevention angle + structured intake methodology |
| **Mozilla Foundation Internet Health** | $5k–50k | Privacy-respecting tech | "No ads, no data sales" + open exercise catalog |
| **Microsoft AI for Health** | $10k–100k | AI in health applications | MediaPipe form check + injury-aware recommendation |
| **Google.org** | $25k–500k | Tech for social good | Same |
| **AHA Voices for Healthy Kids** | $25k–250k | Physical activity for children | Future kids-tier track |
| **State / regional health foundations** | $5k–50k | Varies | Often the easiest because less competition |

**Year 1 realistic target:** 1–2 grants × $25k = $25–50k.

**Year 2–3 target:** 1 NIH SBIR Phase I ($50k–250k).

### Stream 4: Corporate sponsorship

Mission-aligned for-profit companies sponsor in exchange for logo
placement + co-marketing. Very different from for-profit ad revenue —
the company is donating, not buying ads.

| Sponsor type | Why they donate | Likely range |
|---|---|---|
| Gym equipment OEMs (Rogue, Eleiko, Concept2, Hammer Strength) | Their equipment is in our QR catalog — natural marketing tie-in | $5k–25k/yr |
| Insurance carriers (Cigna, Aetna, regional plans) | Preventative health = lower claims; potential pilot for premium-discount partnership (MK.4) | $10k–100k/yr |
| Athletic apparel (Lululemon, Nike, On) | CSR + marketing; brand-aligned fitness audience | $10k–50k/yr |
| Sports nutrition (Garage Whey, Momentous) | Same as apparel | $5k–25k/yr |

**Year 1 realistic target:** 1 corporate sponsor × $10k.

### Stream 5: In-kind donations (celebrities + content)

This is where the celebrity-signing budget vanishes. Detailed below.

**Estimated declared value:** $20k–50k / yr (mostly tax-deductible to
the donor, $0 cost to us).

### Combined year-1 budget projection

| Source | Year 1 conservative | Year 1 stretch |
|---|---|---|
| Subscriptions (recurring donations) | $8,450 | $25,000 |
| One-time donations | $5,000 | $15,000 |
| Grants | $0 | $50,000 |
| Corporate sponsorship | $0 | $10,000 |
| In-kind (declared value, not cash) | $20,000 | $50,000 |
| **Cash subtotal** | **$13,450** | **$100,000** |

Year-1 cash needs (below) are ~$2,000–5,000 of external spend +
infrastructure (covered by Google for Nonprofits credits) + dev time
(volunteer-driven if needed). **The conservative case is already
self-sustaining.**

---

## Celebrity content as donations — the workflow

Celebrities, athletes, and trainers contribute content as in-kind
donations rather than getting paid. This reframes the entire outreach.

### The ask (template email)

Subject: *Quick request — would you donate a workout to our nonprofit?*

> Hi [Name],
>
> I'm building a free, nonprofit fitness app for people who can't
> afford a personal trainer — especially folks coming back from
> injury. Every exercise is reviewed by a physical therapist before
> it ships.
>
> I'd love to feature one of your workouts. It would be donated to
> the project (tax-deductible at fair market value), with full credit
> to you on the workout screen and our website. We'd film it together
> in a 1-hour session, or you can send us an existing video you
> already have rights to.
>
> No commercial use of your name or likeness — just an "Donated by
> [Name]" credit. We're a 501(c)(3) (status pending / approved), EIN
> [number], so the donation is fully tax-deductible.
>
> Interested? Happy to share more.

### Why celebrities say yes to this

1. **Tax write-off at fair market value.** A trainer who normally
   charges $5k for a workout video gets a $5k charitable deduction.
   The IRS lets them claim the *fair market value* of the donated
   service.
2. **Better PR than commercial endorsement.** "Worked with a charity"
   reads cleaner on social media than "endorsed a fitness app."
3. **Mission alignment.** Most fitness celebrities have a backstory
   that involves overcoming an injury. The app's mission to help
   injured people resonates.
4. **No long-term commitment.** One workout, one credit line, done.
   Compare to a commercial deal with revenue share + exclusivity +
   ongoing royalty math.

### The legal piece

For each donation we need:
- **Contribution agreement** (1-page, template-able): donor grants
  perpetual non-exclusive royalty-free licence to use the content for
  the nonprofit's mission. Donor retains copyright.
- **In-kind donation acknowledgement letter** (required by IRS for
  donations >$250 of declared value): describes the content,
  acknowledges no goods/services were exchanged, signed by the
  nonprofit director.
- **Donor's responsibility:** they document the fair market value
  themselves for tax purposes (IRS Form 8283 if >$500). We don't
  appraise it.

**Total legal cost per celebrity contribution: $0** (templates from
BoardSource + sample 8283s). Compared to $5k–15k legal for a
commercial deal.

### Pipeline (conservative year 1 target)

- Q3 2026: outreach to 20 micro-influencers (10k–100k followers)
- Q4 2026: secure 5 contributions, 2 filmings done
- Q1 2027: outreach to 10 mid-tier celebrities (100k–1M)
- Q2 2027: secure 1–2 contributions
- **Year 1 declared value: $20k–50k of donated content**

---

## Cost reductions across the board (concrete dollar amounts)

Stack of nonprofit-specific programs. All real, all currently
available as of 2026.

### Cloud infrastructure ≈ $0 / year

- **Google for Nonprofits / Google.org Workspace + Cloud:**
  - Workspace Business Standard free for verified nonprofits
  - **Google Cloud: $10,000/year credits** (covers Firebase, Functions,
    Storage at small scale indefinitely)
  - Apply at <https://www.google.com/nonprofits/>
- **Microsoft Azure for Nonprofits / Founders Hub for Nonprofits:**
  - **$150,000 in Azure credits over 4 years** ($37,500/year average)
  - Includes free GitHub Enterprise Cloud
  - Apply at <https://www.microsoft.com/en-us/nonprofits>
- **AWS Imagine Grant** + AWS for Nonprofits:
  - $5,000–$50,000 in AWS credits per year for selected orgs
- **Cloudflare for nonprofits** (Project Galileo): free Pro plan
- **Sentry for nonprofits**: $500/year in error-tracking credits

**Net infrastructure cost year 1:** $0 (covered by GCP nonprofit credits).

### Developer tooling ≈ $0 / year

- **GitHub Team plan: free** for verified nonprofits (normally $4/user/mo)
- **Apple Developer Program: $0/year** for verified nonprofits (normally $99/year)
- **Google Play Developer: $25 one-time** (no nonprofit waiver, but
  trivial cost)
- **JetBrains All Products Pack: free** for nonprofits (normally
  $250/user/year)
- **Figma: free** Education + Nonprofit plan
- **1Password Teams: free** for nonprofits

**Net dev tooling cost year 1:** $25 (Google Play one-time).

### Payment processing — Stripe.org

- **Stripe.org reduced rate: 2.2% + $0.30** per transaction (vs 2.9% +
  $0.30 standard)
- Some nonprofits qualify for free Stripe processing entirely (rare,
  competitive)
- Auto-generated tax receipts
- Apply after 501(c)(3) approval (or fiscal sponsor's status)
- Saves: at $10,000/year in subscriptions = ~$70/year (small now,
  meaningful later)

### Legal — pro bono / reduced rates

- **Lawyers for Good Government** matches nonprofits with pro bono
  attorneys
- **Probono.net** (US) — searchable directory
- **Legal startup-clinic networks** (Stanford, Harvard, NYU) — free
  legal help for early-stage nonprofits
- **Cobalt / Harbor Compliance** — paid services with nonprofit
  discounts ($500–$2,000 vs $5k–15k for full-rate firms)

**Year 1 legal cost:** $0–500 (using pro bono).

### Insurance — D&O

- **Directors and Officers (D&O) insurance** — required by most state
  laws once incorporated. Protects board members from lawsuits.
- Nonprofit-specific insurers (Philadelphia Insurance, Hartford
  Nonprofit Insurance) charge $500–1,500/year for small orgs vs
  $2,000–5,000 standard.

**Year 1 cost:** $500–800.

### Total infrastructure + tooling year-1 cost: $525–1,325

(Almost all of which is the D&O insurance + Google Play one-time fee.)

---

## Reframed pricing tiers (subscriptions = donations)

The technical implementation barely changes — same Stripe Checkout,
same Cloud Functions webhook, same Firestore subscription doc — but
the *copy* and *receipts* shift everywhere users see them.

### What stays the same
- Three tiers: Free / Supporter (≈ Standard) / Sustainer (≈ Celebrity)
- Same features per tier (no feature paywalls — paid tiers add
  nice-to-haves not necessities; free tier is fully functional)
- Same 14-day trial mechanism (now framed as "try before donating")
- Same Stripe Customer Portal for management
- Annual + lifetime SKUs (per `../plans/NEXT_TICKETS.md` ticket #6)

### What changes

**Subscription page copy:**

> **Become a Supporter — $9.99/month**
>
> Your subscription is a tax-deductible donation that keeps this app
> free for everyone, including users with injuries who can't afford a
> personal trainer. Every dollar goes back into the mission:
> physiotherapist-reviewed exercises, AI form coaching, and zero ads
> ever. We'll email you a tax receipt every December.

**Tax receipt email** (Stripe automation):

> Thank you for your contribution of $9.99 to [App Name], a 501(c)(3)
> nonprofit organization (EIN: XX-XXXXXXX). No goods or services were
> provided in exchange for this contribution beyond what is freely
> available on our public app. This letter serves as your tax receipt
> for IRS purposes.

**Donor wall** (optional opt-in):
- Free section on the website + an "About" page in the app
- Champions ($499 one-time or $199/yr+) get listed by name (with
  consent)
- Builds community + social proof for future donors

### Free-tier vs paid-tier feature split

Critical principle: **the free tier must be fully functional for the
mission to be honest.** Differentiate paid tiers with *experience*
upgrades, not gating safety features.

| Feature | Free | Supporter | Sustainer |
|---|---|---|---|
| Full equipment catalog | ✓ | ✓ | ✓ |
| Injury-aware recommendations | ✓ | ✓ | ✓ |
| Workout logging + progress | ✓ | ✓ | ✓ |
| QR-scan equipment | ✓ | ✓ | ✓ |
| Schedule + reminders | ✓ | ✓ | ✓ |
| 14-day rolling progress chart | ✓ | ✓ | ✓ |
| **Long-term progress + analytics** (8w+, year-over-year) | — | ✓ | ✓ |
| **Form check (MediaPipe)** | — | ✓ | ✓ |
| **Recovery score from HRV** | — | ✓ | ✓ |
| **AI workout generator** (Phase 6) | — | — | ✓ |
| **Donated celebrity workouts** | — | — | ✓ |
| **Donor wall recognition** | — | (opt-in) | ✓ |
| Tax receipt | — | ✓ | ✓ |

This is genuinely different from for-profit freemium — there are no
"sorry, your injury filtering is locked behind paywall" moments. The
mission demands the safety + injury features stay free.

---

## Reduced-cost testnet path (taking your suggestions + applying nonprofit benefits)

### Year-zero spend table (to get a credible v1 in front of users)

| Item | For-profit cost | Nonprofit / testnet cost | How |
|---|---|---|---|
| Physio review | $5k | **$0–1,000** | ATC contractor for $1k OR pro bono PT board member (free, recruit one). Public-protocol citations cover the gap until then. |
| Celebrity content | $30–80k | **$0** | In-kind donations from 1–3 micro-influencers. Tax-deductible for them; $0 cash to us. |
| Wear OS dev | 16 eng-days | **0–3 eng-days** | Skip for testnet entirely or replace with phone lock-screen widget (3d). |
| Catalog scraper / 200 exercise videos | $5–15k | **$500–2,000** | Mix of stock video ($500–2k for 100 clips) + crowdsourced micro-influencer demos donated as in-kind for the rest. |
| Cloud infrastructure | ~$200/mo Firebase + Functions | **$0** | Google for Nonprofits gives $10k/year credits |
| Stripe processing | 2.9% per transaction | **2.2%** | Stripe.org rate (saves ~30% on processing) |
| Legal (incorporation + ongoing) | $5–15k | **$0–500** | Pro bono attorney via Lawyers for Good Government + DIY Form 1023-EZ |
| Apple + Google dev fees | $124/yr | **$25 one-time** | Apple waived for nonprofits |
| D&O insurance | — | **$500–800/yr** | Required if incorporated; nonprofit-specific carriers |
| GitHub / JetBrains / Figma | $500–1,500/yr | **$0** | All have nonprofit free tiers |

### Total year-1 external spend: ~$1,000–4,300

vs the for-profit testnet path of ~$2,000–5,000, with vastly more
optionality (grants, in-kind donations) on top.

---

## Engineering changes from for-profit roadmap

Most code stays — what changes is copy + receipts + a few new
surfaces.

### Done already (no change needed)

- Stripe Checkout integration ✓ (just swap to Stripe.org rate)
- Subscription model + tier system ✓
- Webhook for active/cancelled state ✓
- 14-day trial mechanism ✓

### Small changes (~3–5 days eng)

1. **Subscription page copy + tax receipt language** — change the
   marketing copy to "donation" framing throughout. ~1 day.
2. **About / Mission page** — new screen explaining the nonprofit
   mission, 501(c)(3) status, EIN, where money goes. ~1 day.
3. **Tax receipt email** — Stripe webhook already fires on payment;
   add a Cloud Function that sends a year-end aggregate tax letter
   (Jan 31 each year). ~1 day.
4. **Donor recognition (opt-in)** — Champion-tier donors get listed
   on a /donors page (in-app + web). ~1 day.
5. **Annual transparency / impact report** — content + a static page
   in the app showing how donations were used. ~0.5 day eng + content
   work.

### Larger items (separate work)

- **Public financial reporting** — annual Form 990 published on the
  website (required by 501(c)(3) compliance, also good practice).
- **Volunteer contribution flow** — `CONTRIBUTING.md` + Code of
  Conduct + a way for community PTs / trainers / coders to suggest
  exercise additions or improvements. Mostly process, ~2 days eng for
  any tooling.

---

## Marketing / positioning shifts

The competitive analysis still applies — Fitbod, Hevy, Centr remain
the threats. But the *story* changes:

- **Old:** "AI-personalised fitness app for $9.99/mo"
- **New:** *"The only nonprofit fitness app reviewed by physical
  therapists. Free for everyone, sustained by tax-deductible
  donations. No ads. No data sales. Ever."*

That's a different category — not competing with Fitbod on features
alone, but on **trust and mission**. Different audience overlap, much
easier organic press coverage.

### Where this narrative wins

- **Healthcare media** — Health Affairs, KaiserHealthNews, STAT News
  cover nonprofit health-tech but rarely cover for-profit fitness apps
- **Patient-advocacy networks** — chronic-pain communities,
  post-surgery rehab groups, MS / Parkinson's foundations refer
  patients to nonprofits, not for-profits
- **Corporate wellness** — Fortune 500 wellness programs often have a
  CSR angle that prefers nonprofit partners
- **Insurance preventative-health programs (MK.4)** — way easier
  partnership conversation as a nonprofit ("we're aligned on outcomes,
  not profit")

### Where it doesn't help

- The crossfit / lifter / gym-bro segment doesn't care about
  nonprofit framing. They want the best tool. Compete with them on
  features (form check, progressive overload, equipment scan).
- Marketing must work both narratives: mission-led for one segment,
  feature-led for another. Not a contradiction; just different
  channels.

---

## Phased plan — first 12 months

### Months 1–2: Legal + foundation

**Outcomes:**
- Decision: 501(c)(3) direct vs fiscal sponsorship
- If direct: file articles of incorporation + Form 1023-EZ
- If sponsored: signed agreement with fiscal sponsor
- Apply: Google for Nonprofits, Microsoft for Startups, Apple
  Developer, GitHub Team
- Recruit 3-person board of directors (1 should be a DPT — fills
  physio review need)
- Secure pro bono attorney via Lawyers for Good Government

**Cost:** $325–$3,500 (incorporation + filing fees).

### Months 3–4: Content + testnet launch

**Outcomes:**
- ATC contractor reviews exercise catalog ($1k spent)
- Stock-video catalog populated (~$500–2k spent)
- Subscription page rewritten with donation copy
- About + Mission page shipped
- Tax-receipt email automation deployed
- Closed beta launches to ~500 users via existing waitlist + 3
  patient-advocacy partner channels

**Cost:** $1,500–3,500 + ~5 eng-days.

### Months 5–6: Donation outreach begins

**Outcomes:**
- Outreach to 20 micro-influencers for in-kind workout donations
- Secure 3–5 contributions, schedule filmings
- First grant application submitted (RWJ Foundation Health Equity)
- First corporate sponsorship pitch (gym equipment OEM)
- Stripe.org rate activated post-determination letter

**Cost:** $0 cash; ~10 hours/week on outreach.

### Months 7–9: Public launch + first grant cycle

**Outcomes:**
- Public launch — open to all users
- 5 celebrity-donated workouts in the app
- Apply: 2 more grants (NIH SBIR Phase I, Microsoft AI for Health)
- Year-end donation campaign (December)
- Target: 1,000 free users + 50 paying donors

**Cost:** Marketing — $1,000 (organic + targeted ad credits via
Google for Nonprofits Ad Grants — $10k/month free).

### Months 10–12: Sustainability check + scale prep

**Outcomes:**
- Year-1 budget review: hit conservative target ($13k cash + $20k
  in-kind)?
- Apply Stream 4 corporate sponsorships now that there's user
  traction data
- File Form 990-N (or 990 if revenue >$50k)
- Plan year-2 hiring: contract DPT for full catalog review (now
  affordable)
- Begin Wear OS dev (deferred to year-2)

**Cost:** Form 990-N is free; 990 has filing service fees of $0–500.

---

## Total year-1 cash budget (conservative)

| Category | Budget | Sources |
|---|---|---|
| Incorporation + legal | $1,000 | Bootstrap / first donor |
| ATC catalog review | $1,000 | First donor / first grant |
| Stock content (catalog scraper) | $1,500 | First donor / sponsor |
| D&O insurance | $700 | First quarter cash flow |
| Marketing (paid ads) | $500 | Recurring donations |
| Misc legal / compliance | $300 | Recurring donations |
| **Total cash spend** | **$5,000** | |
| **Cash income (conservative)** | **$13,450** | $8.5k subs + $5k one-time |
| **Surplus available for year 2** | **$8,450** | Builds reserve |

**The conservative case is self-sustaining in year 1.** Stretch case
(grants + corporate sponsor) accelerates everything: full DPT review,
hire one part-time PT contractor for ongoing catalog work, kick off
Wear OS dev a quarter early.

---

## Year 2–3 sustainability projection

By year 2, recurring-donor base + first NIH SBIR or RWJ grant should
fund:

- 1 part-time DPT contractor for ongoing exercise review + tagging
  (~$15–25k/yr at part-time rates)
- 1 part-time engineer for feature work beyond what volunteers
  contribute (~$30–60k/yr)
- Continued infrastructure ($0 — still under nonprofit credits)
- Year-end donor appreciation event ($1–3k)

**Year-2 cash target:** ~$80–120k (reachable with NIH Phase I + 200
recurring donors).

By year 3, target structure:

- 2 staff (executive director + product/eng lead) at $50–80k each
- Catalog up to 500 exercises with full DPT review
- 2–3 active grants (one NIH SBIR Phase II is $1M+)
- Insurance partnership pilot live
- 5,000+ free users, 500+ paying donors

**Year-3 cash target:** ~$300–500k.

---

## Concrete next-action tickets (replaces ../plans/NEXT_TICKETS.md priority for nonprofit pivot)

### Now (this week)

1. **Decide: 501(c)(3) direct or fiscal sponsorship.** I'd recommend
   fiscal sponsorship to start — 2-week setup vs 3-6 month wait.
   Action: research 3 candidate fiscal sponsors, pick one, send
   intake form.
2. **Apply Google for Nonprofits + Microsoft for Startups.** Both
   forms take ~1 hour; both grant credits worth $10k+.
3. **Recruit a DPT to the board.** Solves the physio-review problem
   for free + gives clinical credibility. LinkedIn search for "DPT,
   pro bono, nonprofit" yields candidates.

### Within 30 days

4. **Rewrite subscription page copy as donations.** ~1 day eng + 0.5
   day copy work.
5. **Build About / Mission page in app.** ~1 day eng + content.
6. **Set up Stripe.org account** (after fiscal sponsor or 501(c)(3)
   determination).
7. **Send 5 in-kind donation outreach emails to micro-influencers.**

### Within 90 days

8. **First grant application** (RWJ Foundation Health Equity is the
   easiest fit).
9. **First corporate sponsor pitch** (gym equipment OEM — Rogue,
   Eleiko, or Hammer Strength).
10. **Closed beta launches.**

### Cross-references

- Technical roadmap: [`../plans/ROADMAP_2026_V2.md`](../plans/ROADMAP_2026_V2.md)
- Engineering tickets: [`../plans/NEXT_TICKETS.md`](../plans/NEXT_TICKETS.md) — most
  still apply; the "external-resource blocked" section gets ~80%
  cheaper with the donation pivot
- Competitive analysis: [`COMPETITIVE_ASSESSMENT.md`](COMPETITIVE_ASSESSMENT.md) —
  pricing comparisons remain valid; the differentiation story shifts
  to mission + trust
- Stripe operational setup: [`PHASE_4B_STRIPE_SETUP.md`](PHASE_4B_STRIPE_SETUP.md) —
  add a Stripe.org switch step after 501(c)(3) approval

---

## Risks + mitigations

| Risk | Likelihood | Mitigation |
|---|---|---|
| 501(c)(3) determination delayed >6 months | Medium | Fiscal sponsorship eliminates this risk entirely |
| First-grant rejection (1-in-5 success rate baseline) | High | Apply to 4–6 grants in parallel year 1 |
| Donor base too small to sustain | Medium | Conservative budget assumes $13k year 1; that's only ~50 paying donors. Reachable. |
| Celebrity in-kind donations don't materialise | Medium | Branding stays "Premium / Pro Coach" not "Celebrity tier" until content lands. No marketing claims based on celebrities until they ship. |
| Volunteer engineering capacity insufficient | High | Plan for paid contractor work in stretch budget; don't rely on volunteers for critical path |
| Tax-deductibility messaging misleads users | Low | Clear disclaimer: "consult your tax advisor"; only state deductibility after IRS approval; Stripe.org receipts handle the legal language correctly |

---

## Closing

The nonprofit pivot turns the competitive picture from "we have a
budget gap vs Fitbod and Centr" into "we have a different category
they can't easily replicate." The same code we've been writing serves
the mission directly — injury-aware filtering for users who can't
afford a personal trainer is exactly the impact a 501(c)(3) is built
to fund. Year-1 cash needs are tiny ($5k all-in); recurring-donation
math is achievable with 50 paying donors out of 1,000 free users
(5% conversion is low for a nonprofit with this mission).

Ship the testnet at $0–2k of external spend. Get the first few
in-kind celebrity donations. Apply to grants in parallel. The path is
clear and almost entirely unblocked.
