# Favorite Gyms and Their News — English Translation of an Unapproved Proposal

**Original:** [Favorite gyms and news — draft](PLAN_GYMS_AND_NEWS_2026-08-01.md), exact Git blob `92ddfa5d66c357f7f4a2b12c1b38af576cd6c179`.  
**Original date:** **August 1, 2026**.  
**Original status:** **PROPOSAL — no code may be written until separate owner GO**.

**Source owner request, translated, not re-authorized:** "Add the ability to remember my favorite gyms. AI should monitor social media and surface interesting news, events, discounts and promotions from those clubs. In the future we would like to extend this to all gyms in the surrounding area/city."

The original Russian quotation remains unchanged in the canonical source. This English companion is explanatory documentation and does **not** authorize the proposed product feature, surveillance of other users, social scraping, data collection, cost commitments, new Firebase schema or integrations.

---

## 1. What goes wrong if we implement the idea naively?

The request has two fundamentally different parts.

**Saving favorite gyms** is an ordinary application feature that the original author estimated could be developed without the social-media infrastructure problem.

**Having AI monitor gym social networks** is primarily an issue with external platforms' access rights, resilience and personal-data processing, **not** choosing an AI model.

### 1.1 Meta Instagram and Facebook automation restrictions — historical source interpretation

The original argued that unauthorized automated scraping of Instagram/Facebook content violates Meta platform terms, creates account/IP enforcement risks and can cause app-policy problems.

Supported official APIs were described as **permission-scoped**:

- **Instagram Graph API:** The source assumed access to participating gym business accounts that explicitly authorize the application, not the ability to read every account in a city.
- **Facebook Pages API:** It treated access similarly as consent/authorization dependent.

**Original conclusion:** Monitoring *every gym's posts in a city* was not a viable or permitted promise through the proposed official integration, and unsupported scraping would not be an acceptable substitute.

**Current-terms caution:** This is the source's **August 1, 2026 interpretation**, not a new legal opinion or current vendor API-access verification. Before any implementation, re-check current Meta terms, permitted endpoints, review requirements and required authorizations.

### 1.2 Scraping would be brittle even if it worked initially

Social layouts, login methods and anti-automation mechanisms change. A scraper can fail without clear user feedback.

A silently empty feed is worse than an unavailable feature because users cannot distinguish **"the gym published no news"** from **"our integration stopped working"**. The product must show source/retrieval status truthfully.

### 1.3 Personal data

Gym posts can include identifiable people and member photographs. Copying and redistributing those photographs is a distinct privacy, data-protection, copyright and permissions matter. **Linking to the original** may avoid some copying risks, but does not by itself prove complete GDPR compliance. Review the actual use, legal basis, retention and data subjects before collecting personal content.

---

## 2. Potentially workable sources

The source ranked three access patterns by reliability and scope:

| Candidate source | Intended information | Historical coverage assumption | Historical cost assumption |
| --- | --- | --- | --- |
| **Google Places API** | Name, address, hours, phone, site, rating, photo | Most gyms in a city | Billable after free allowance; source estimated ~$17 per 1,000 Place Details calls |
| **Official gym website / RSS / Open Graph** | News, event notices and promotions published by the gym | Maybe around half have a usable website | Regular HTTP retrieval was assumed free beyond infrastructure |
| **Instagram Graph API** | Posts made by an authorized gym | Only gym accounts that opt in/authorize | Source assumed no marginal API charge; gym authorization and platform review needed |

**Do not treat the costs, API capabilities, free credits or coverage guesses in this table as current prices or permission grants.** They are estimates in a dated proposal and require fresh vendor/product/legal validation.

### What AI would actually do

Ordinary authorized HTTP/API retrieval obtains text. The proposed role of a model was **interpretation**, for example:

- Is this a promotion, event or ordinary news item?
- What is the expiration date?
- Does it apply to new members or everyone?
- What discount terms or percentage are actually supported?

Produce a human-readable card with source link, retrieved/published date and optional user-controlled reminder.

The source suggested potentially reusing a Gemini integration already under development rather than deploying a separate AI stack. This is a **proposal**, not evidence that the current app offers reusable model quota, rights to ingest those pages or authorization to transmit personal information to that service.

---

## 3. Proposed implementation sequence

Each step was intended to be useful on its own, postponing costlier/external access.

### Step 1 — My Gyms (no AI required)

- Find gyms through authorized Places search and save selected gyms as favorites.
- Gym card: address, business hours, telephone, **Directions** link and website.
- Associate workouts with a gym through `WorkoutLogEntry.gymId`. This would later permit insights such as "Where do I train most often?" and possibly "Which equipment is available there?"
- Associate already recognized equipment with a gym so **My Machines** is no longer a single unscoped collection.

The author described this as a standalone user-value feature, even if Steps 2–3 were never built.

**Historical effort estimate:** 2–3 days, one external dependency (Places) and one proposed new Firestore collection.

**Important gate:** Any real Firestore schema, location processing, gym association or external API billing still requires its separate owner/product/privacy approval. The original was explicitly **not yet authorized for code changes**.

### Step 2 — News from gyms' own websites

- Read the `website` URL for each saved gym from Places, then look for `/news`, `/blog`, RSS and Open Graph metadata.
- Retrieve at most daily, through a scheduled server/cloud function, not continuous mobile polling.
- Extract structured headline, one-line summary, category (promotion/event/news), validity deadline and publication date.
- Display a **link to the original**. Do **not** archive or republish other people's photographs.
- Attribute with a timestamp: **"According to the gym's website, as of [date]"** so a stale offer is not presented as currently valid.

**Historical estimate:** 3–4 days; major risk that many gyms have no regularly updated website, or only image-based pages.

**Safety note:** Respect robots/site terms, copyright, privacy, server costs, content permissions and inaccurate model summaries.

### Step 3 — Instagram only with gym authorization

- Add an owner-claim/verification workflow in the gym card, conceptually "We manage this gym".
- An authorized gym representative connects the business account through the permitted Instagram Graph OAuth flow.
- Authorized posts may then appear to users who have favorited that gym, **only within the approved API permissions and use cases**.
- Without authorization, show no post feed and do not pretend the feed exists.

**Historical estimate:** 3 implementation days **plus unpredictable Meta app-review time**.

The original rationale was that gym owners could view the app as a free channel to their own customers. This is a hypothesis, not demonstrated partner interest.

### What the proposal deliberately excluded

The original blanket request to **monitor every gym's social accounts across the district/city** was marked nonviable under the assumed API restrictions.

Steps 1–3 were an alternative: allow users to discover city gyms (Places), read published website information when available, and view richer feeds from **opted-in** accounts. **Never promise complete feed coverage for every gym.**

---

## 4. Historical cost assumptions — NOT current vendor prices

The original August 1 calculation stated:

- **Google Places:** It assumed a **$200/month credit** and roughly **$17 per 1,000 Place Details requests** after free usage. With one-day result caching, it estimated virtually zero additional cost at one user or about one hundred users, with serious cost evaluation at thousands.
- **Gemini:** At one news page per gym per day, ten gyms would produce **300 model requests/month**, which the source considered below its then-assumed free quota.

**These pricing and free-credit assertions are dated, explicitly unverified estimates. They must not be used as current Google Maps Platform or Gemini billing guidance.** Different API SKUs, quota tiers, caching policies, model costs, legal restrictions and actual traffic can materially alter the outcome.

A production gate requires current prices, measured traffic, retry costs, abuse protection and explicit budget limits.

---

## 5. Questions requiring answers before Step 1

1. **Are gyms personal or shared?** If two users add the same gym, do they share one gym record/news feed or have separate records? Shared data may be cheaper and help Step 3, but requires rules, owner claims, moderation, privacy and tenant isolation. Personal records are simpler.
2. **Is Step 3 necessary?** It requires external collaboration and gym representative permission. For a personal-use app, Steps 1–2 might suffice.
3. **Which geography?** Places discovery works in many areas, but should users search cities other than their current location for travel or vacation?

These questions were **open** at the source checkpoint; the translation does not invent decisions.

---

## 6. Original recommendation

**Start with the favorite-gyms concept (Step 1), subject to separate explicit owner GO.** It potentially delivers value independently and enables the app to know where users train.

Discuss Steps 2–3 **after** measuring real favorites and checking how many added gyms actually maintain websites; those observations are needed to decide whether more complex distribution/integration work is worthwhile.

Do not start with an unsupported citywide social-media scraper.

## Review/translation boundary

- All **six** source sections and **three** suggested implementation steps are preserved, including the explicit **no code without a separate GO** rule.
- The original first-person owner request remains an immutable Russian quotation in the linked source, and the English quote is labeled a translation rather than a new owner instruction.
- Legal/API limitations and pricing were **historical claims**, not independently reverified in this translation. The cost figures are dated and must not be treated as a current quotation.
- No app, gym provider account, social-media account, website, location record, Firestore document, scheduled job, AI provider, user data or repository runtime code was changed.
- The owner must separately authorize architecture, data collection, external API rights, legal bases, budget and implementation scope.

**Status: FULL SIX-SECTION HISTORICAL ENGLISH COMPANION FOR SEMANTIC REVIEW; NOT CODE APPROVAL OR DEPLOYMENT GO.**
