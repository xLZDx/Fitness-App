## Regulatory / compliance review — `D:\Repo\_wt-formcoach` (read-only, no files changed)

**Scope header (agent contract):**
- `jurisdictions`: EU (GDPR + MDR 2017/745), US (FDA general wellness), Google Play, Apple App Store. Controller is a sole developer in Moldova serving EU consumers → GDPR applies via Art. 3(2)(a).
- `intended_purpose` as coded: exercise catalogue, planner, machine scanner, on-device pose/rep counting, cloud technique text, health-questionnaire-driven exercise exclusion, Health Connect/HealthKit read + workout write-back.
- `official_sources_checked` (2026-08-15): [Play Health Permissions guidance &amp; FAQs](https://support.google.com/googleplay/android-developer/answer/12991134?hl=en), [Health Content and Services](https://support.google.com/googleplay/android-developer/answer/16679511?hl=en), [Plan compliance with privacy policies (Health Connect)](https://developer.android.com/health-and-fitness/guides/health-connect/plan/user-privacy), [Play policy announcement 15 Apr 2026](https://support.google.com/googleplay/android-developer/answer/16926792?hl=en), [FDA General Wellness: Policy for Low Risk Devices (reissued 6 Jan 2026)](https://www.fda.gov/regulatory-information/search-fda-guidance-documents/general-wellness-policy-low-risk-devices). MDR Rule 11 / Art. 2(1) and EDPB explicit-consent guidance were **not** re-verified live — see unresolved items.

---

# VERDICT

`REGULATORY_REVIEW_REQUIRED` — **DO NOT SHIP to Google Play or the App Store in current state.**

The *functional* boundary is in unusually good shape: the AI coach carries no health data, the load-prescription number was deliberately removed, Form Check and Posture report kinematics with explicit non-diagnostic disclaimers, and the health-questionnaire device-local split is real in code, not just in prose. That work is genuinely above the norm and I found no functional medical-device behavior.

The failures are in **claims and disclosure**, and two of them are hard release blockers: an entire live health-data source (Health Connect / HealthKit) is absent from every legal document in every locale, and the About page makes a rehabilitation-grade claim that the app's own Terms contradict.

`provisional_boundary`: LOWER_RISK_WELLNESS on function; **HIGH_RISK_CLAIM** on the About-page wording. Not a legal classification.

---

# Top 5 risks

1. Health Connect / HealthKit access is undisclosed in the privacy policy the store listing links to — a per-se Play Health Permissions rejection and a GDPR Art. 13 gap on special-category data.
2. "rehab-grade exercise guidance" on the About page is a therapeutic-quality claim, live in EN and RU, directly contradicted by the app's own Terms.
3. No explicit Art. 9(2)(a) consent event for the health questionnaire — collection sits behind a collapsed "More health details" accordion under a bundled login-screen agreement.
4. The privacy policy's export promise ("You get everything") is contradicted by the export artifact's own note.
5. The device-local health claim is stated in absolute present tense while the code documents a named population for whom it is not yet true.

---

# Findings

**R1 · BLOCKER | FACT | Health Connect / HealthKit data access appears in no legal document, in any locale, on the web or in the Play Data safety worksheet.**
`mobile/android/app/src/main/AndroidManifest.xml:17-23` declares `READ_STEPS`, `READ_ACTIVE_CALORIES_BURNED`, `READ_HEART_RATE`, `READ_RESTING_HEART_RATE`, `READ_SLEEP`, `READ_HEART_RATE_VARIABILITY`, `WRITE_EXERCISE`. `mobile/lib/core/health/platform_health_service.dart:19-30` reads steps, active energy, resting HR, sleep and HRV and writes workouts back. `mobile/lib/main.dart:365-366` binds `PlatformHealthService` in production; `mobile/lib/features/home/home_page.dart:142` puts the card on Home. Against that: `mobile/lib/l10n/app_en.arb:1758` and `app_ru.arb:985` (and the generated `public/privacy.html`, `scripts/legal/legal_text.py`) contain zero occurrences of "Health Connect", "HealthKit" or any of these metrics — grep returns 0 across all four. `core/PLAY_DATA_SAFETY_2026-08-05.md:49-90` has no Health Connect row at all; its "Health info: **No**" answer was derived solely from the questionnaire split.
*Failure scenario:* Play review opens the linked policy, finds no Health Connect disclosure, and rejects under the Health Connect by Android Permissions policy; separately an EU user's Art. 15 request surfaces resting-HR/HRV/sleep processing never named in the notice.
*Impact:* Store rejection or removal; GDPR Art. 13(1)(c) and 13(2) breach on Art. 9 data; the Data safety form contradicts the linked policy, which Play treats as a removal rather than a warning.
*Required change:* Add a Health Connect / Apple Health section to `scripts/legal/legal_text.py` (the single source) naming each data type read, each written, the purpose, that it stays on the device, and how to revoke; add a Health Connect row to the Data safety worksheet and re-derive the "Health info" answer; expand the pre-permission disclosure at `app_en.arb:166` beyond "steps, sleep + recovery" to name heart rate/HRV.
*Acceptance test:* Extend `test/features/legal/legal_pages_test.dart` to assert the rendered privacy body names each `HealthDataType` in `healthReadTypes` and `healthWriteTypes` — so adding a metric without adding a disclosure fails a test.

**R2 · BLOCKER | FACT (text) / INFERENCE (classification) | The About page claims "rehab-grade exercise guidance", contradicting the app's own Terms.**
`mobile/lib/l10n/app_en.arb:70` — "Our goal: make rehab-grade exercise guidance available to anyone with a phone"; RU equivalent at `app_ru.arb:56` ("руководство по упражнениям реабилитационного уровня"); rendered at `mobile/lib/features/about/about_page.dart:91`. The same corpus states at `app_en.arb:343` and `:1703`, and in the Terms at `:1759`, that "**The exercise library has not been reviewed by a physiotherapist**" and that nothing in the app is medical advice.
*Failure scenario:* A user with a healing injury reads "rehab-grade" as a rehabilitation-quality product, follows an unscreened programme, and is injured; the operator's own Terms are the evidence that the claim was known to be false.
*Impact:* "Rehabilitation" is an explicit medical purpose under MDR 2017/745 Art. 2(1) ("alleviation of ... injury") and pulls intended purpose toward Rule 11; under the FDA General Wellness guidance (reissued 6 Jan 2026) a rehabilitation claim is mitigation of a condition, outside the general-wellness compliance policy. It is also a misleading action under UCPD 2005/29/EC Art. 6(1)(b) on the product's principal characteristics. Note the guidance's own carve-out is worded as "may help reduce the risk of" / "may help living well with" — "rehab-grade" is not that shape.
*Required change:* Remove "rehab-grade". A wellness-safe rewrite states the mission without a therapeutic quality grade. Both locales in the same commit.
*Acceptance test:* Add an assertion to the legal/about test that no user-facing string in either `.arb` matches `/rehab|реабилит|therap|терап/i` — this is the same regression shape S0b already fixed for the nonprofit claims.

**R3 · MAJOR | FACT (mechanism) / INFERENCE (legal sufficiency) | No explicit Art. 9(2)(a) consent event for special-category health data.**
Health fields (conditions, allergies, medications, injuries, limitations, surgeries, blood pressure, free text) are collected at `mobile/lib/features/onboarding/steps/step_health.dart:96-174`, rendered inside a **collapsed** accordion titled "More health details" (`app_en.arb:1037`) at `mobile/lib/features/onboarding/steps/step_body.dart:172-181`, under the subtitle "We use this to keep your plan safe" (`app_en.arb:205`). The only agreement anywhere is the bundled login line "By continuing you agree to our Terms and Privacy Policy" (`app_en.arb:73`, `mobile/lib/features/auth/login_page.dart:230`). There is no checkbox, no separate affirmative act, and no privacy-policy link at the point of collection.
*Failure scenario:* A DPA or a Play health-app reviewer asks what the Art. 9 basis is; the answer is a bundled terms acceptance on a prior screen, which Art. 7(2) requires be separable and which explicit consent cannot be.
*Impact:* GDPR Art. 9(2)(a) has no valid alternative basis here (Art. 9(2)(h) needs a health professional; 9(2)(f)-(j) do not apply), so absent explicit consent the processing has no Art. 9 basis at all. Play's Health Content and Services policy separately requires prominent disclosure and consent before collecting health data.
*Required change:* A dedicated, unticked affirmative control immediately above the health fields, stating the category, the single purpose, that the answers stay on the device, that every field is optional, and linking `/privacy`. Record the consent version and timestamp alongside the answers so it is provable and withdrawable.
*Acceptance test:* Widget test — the health fields reject input and `SensitiveProfile` stays empty until the consent control is set; and a stored consent record carries a policy version.

**R4 · MAJOR | FACT | The privacy policy promises a complete export; the export deliberately is not complete and says so itself.**
`app_en.arb:1758` — "**Export** — Settings, then 'Export your data'. You get everything, in a machine-readable file." `mobile/lib/features/data_export/data_export.dart:60-62` writes into the very same file: "Progress photo image data is not included in this export," and `:14-22` documents the exclusion as intentional.
*Failure scenario:* A user exercising Art. 15/20 relies on the policy sentence, receives a file that omits their photo bytes, and the omission is only visible inside the artifact.
*Impact:* GDPR Art. 12(1) (transparent, accurate information) and Art. 5(1)(a) fairness; the notice overstates the right it describes. The export's internal handling of incompleteness (`progressPhotosIncomplete`, `serverIncomplete`) is exemplary — the policy sentence is the only thing out of step.
*Required change:* Change the policy sentence to state what is included and name the photo-bytes exclusion, or extend the export to carry decrypted photo bytes. The first is a one-line fix in `scripts/legal/legal_text.py`.
*Acceptance test:* `legal_pages_test.dart` asserts the privacy body's export paragraph names the same exclusion string that `buildExport`'s `notes` emits.

**R5 · MAJOR | FACT | The device-local health claim is absolute in the notice and conditional in the code.**
`app_en.arb:1758` states without qualification: "The health answers stay on your phone ... is stored on your device and **is not sent to this app's servers**." `mobile/lib/features/profile/data/device_health_profile_repository.dart:74-83` names the exact exception: migration runs on the user's next read, and "an account whose owner never opens the app again is never migrated by this path, so the server keeps their health block indefinitely." `core/PLAY_DATA_SAFETY_2026-08-05.md:70-76` records the ops script as having cleared 14 legacy documents in one project — good evidence, but it is a point-in-time measurement, not an invariant.
*Failure scenario:* A dormant legacy account's conditions/medications sit in Firestore while the policy tells that user they do not.
*Impact:* GDPR Art. 5(1)(a)/(d) and Art. 13 accuracy of the notice on Art. 9 data. Also destabilises the "Health info: No" Data safety answer, which is only true if the residue is genuinely zero.
*Required change:* Either re-run `scripts/ops/strip_health_from_profiles.py` across every project and record a dated zero-result query as the evidence for the absolute claim, or soften the sentence for pre-2026-08-06 accounts.
*Acceptance test:* A dated read-only query in the Data safety doc showing 0 profile documents carrying health fields across all projects, re-run as a release gate.

**R6 · MAJOR | FACT | `READ_HEART_RATE` is declared but no code path uses it.**
`AndroidManifest.xml:19` declares `android.permission.health.READ_HEART_RATE`. `platform_health_service.dart:19-27` requests `STEPS`, `ACTIVE_ENERGY_BURNED`, `RESTING_HEART_RATE`, `SLEEP_ASLEEP` and one HRV flavour — never `HEART_RATE`. Grep for `HEART_RATE` outside the HRV/resting constants returns nothing.
*Failure scenario:* Play's Health Connect access review rejects the declaration form for requesting a data type with no demonstrated in-app use — the exact "Inappropriate Health Connect Access Requested" rejection class.
*Impact:* Blocks the Health Connect access approval; also a data-minimisation problem under GDPR Art. 5(1)(c) since the permission grants continuous heart-rate history the app never reads.
*Required change:* Delete the `READ_HEART_RATE` line, or add a real consumer.
*Acceptance test:* A test asserting every `android.permission.health.READ_*` line in the manifest maps to a member of `healthReadTypes` for at least one platform — the same manifest-as-data pattern `font_bundle_test.dart` already uses.

**R7 · MAJOR | FACT (code) / INFERENCE (policy) | `insurance/data/insurance_partner.dart` designs exactly what the April 2026 Play update prohibits.**
`mobile/lib/features/insurance/data/insurance_partner.dart:1-7` documents an attestation flow sharing workout-adherence claims with an insurance carrier for "premium-discount eligibility". It is currently unreferenced outside its own test — no UI, no provider, no server endpoint. The [15 Apr 2026 Play policy announcement](https://support.google.com/googleplay/android-developer/answer/16926792?hl=en) explicitly forbids using sensitive health data to determine **insurance eligibility**. The privacy policy meanwhile states "Two processors are involved, and no others."
*Failure scenario:* Whoever wires this ships a prohibited use case and a fourth processor the notice denies exists.
*Impact:* Latent today (FACT: no call site), but it is a designed feature with a merged test, which is how it gets wired without a fresh review.
*Required change:* Delete the module, or mark it dormant with an explicit regulatory gate in its doc comment naming the April 2026 prohibition. Do not wire it without counsel.
*Acceptance test:* n/a while dormant; if retained, a test asserting no production provider references `InsurancePartner`.

**R8 · MINOR | FACT | Deletion pseudonymises rather than erases two shared collections, and the notice does not say so.**
`functions/src/index.ts:1596-1608` replaces `clientUid`/`coachUid`/`reporterUid` with `DELETED_UID` on `coach_bookings` and `equipment_reports` and retains the rows (the reasoning at `:1521-1540` is sound). The policy says "There is no separate retention timer and no archive copy kept afterwards" and "erases every document under your account". Free-text equipment-report and machine-note content is retained unexamined and can carry personal data; under Recital 26 pseudonymised data remains personal data.
*Required change:* One sentence in the deletion paragraph: shared records (bookings, equipment reports) are kept with the user's identifier removed, because a counterparty's record survives.
*Acceptance test:* Assert the privacy body's deletion paragraph names the two retained collections.

**R9 · MINOR | FACT | The About page shows a 25% "Clinical / physio review" budget line for a review that has not happened.**
`mobile/lib/features/about/about_page.dart:50` with `app_en.arb:56`, adjacent to a principle titled "Open clinical content" and a `medical_information` icon (`about_page.dart:32-34`). The principle *body* is honest ("It has not been reviewed by a physiotherapist"), and the caption at `app_en.arb:54` says "Approximate, year-1 conservative budget" — which mitigates but does not remove the implication that a clinical review programme exists. UCPD 2005/29/EC Art. 6(1)(b).
*Required change:* Label the line as planned rather than actual spend, or retitle the principle so the heading matches its own body.
*Acceptance test:* The About test asserts the forward-looking qualifier renders adjacent to the fund breakdown.

**R10 · MINOR | FACT | Crashlytics runs in release with disclosure but no in-app opt-out.**
`mobile/lib/main.dart:159` enables collection; disclosed at `app_en.arb:1758`. GDPR Art. 6(1)(f) is a defensible basis for crash diagnostics, and the policy does offer an Art. 21 objection route by email, so this is not a breach — but for a health app an in-app toggle is the low-cost defensible position.
*Required change:* Operator decision; no change strictly required.

**R11 · MINOR | FACT | Stale comment asserts progress photos are unencrypted mock-only.**
`mobile/lib/features/data_export/data_export.dart:57-59` — "there is no key: `AesPhotoCipher` has no caller and the only repository bound is the in-memory mock." A2-sec falsified this: `progress_photos_providers.dart:152-153,195-198` binds `LocalProgressPhotosRepository` over `PhotoStore(cipher: AesPhotoCipher(key))` with a Keystore-held per-uid key, which makes the user-facing claim at `app_en.arb:236` true. `core/PLAY_DATA_SAFETY_2026-08-05.md:105-107` carries the same stale evidence.
*Impact:* No user-facing error today — the risk is that this comment is the stated reason a future author would *not* restore an encryption sentence that is now accurate, or would re-derive a Data safety answer from false evidence.
*Required change:* Correct both comments to the current wiring.

**R12 · MINOR | FACT | BMI bands label users with an ICD category.**
`app_en.arb:1941-1944` renders "Obese range" / "Overweight range" against the user's own figure (`body_metric_cards.dart:71-74`). Mitigated as far as it reasonably can be: `app_en.arb:1945` states BMI cannot tell muscle from fat and that nothing in the plan uses it, and `body_metrics.dart:29` confirms no consumer acts on it. Standard general-wellness practice; recorded as a boundary observation, not a defect.

**No material issue found** in: the AI coach path (`ai_coach_context.dart:22-34,105-124` — no health data reaches the model, and the starting-load number was removed for exactly the right reason), the exercise generator, Form Check wording (`app_en.arb:955-1000, 2021, 2099` stay on kinematics and explicitly disclaim safety judgement), Posture (`app_en.arb:1828, 2022`), the scanner's bystander disclosure, marketplace demo-listing honesty (`app_en.arb:1729`), donor-wall opt-in and its server-side limits, subscription/nonprofit wording (S0b's corrections hold in both locales — only the stale *key names* survive, which never render), and the local-wipe/deletion mechanics.

---

# Unresolved decisions for the operator

1. **Art. 9 legal basis.** I am asserting explicit consent is the only available basis. If counsel prefers Art. 6(1)(b) contract for the Art. 6 layer, Art. 9 still needs its own basis — confirm with counsel before R3 is designed, because the answer decides whether the control is a consent checkbox or something else.
2. **MDR Rule 11 and EDPB explicit-consent guidance were not re-verified live** in this pass (I verified the Play and FDA sources directly; the MDR and EDPB citations rest on the bundled `fitness-regulatory-reference` skill). Re-verify before treating R2/R3's regulatory framing as settled.
3. **Is Health Connect data "collected" for the Play Data safety form?** It never leaves the device (`health_providers.dart` holds it in memory only; `deload_detector.dart` is the sole consumer), so "not collected" is arguable — but the *permissions* disclosure in R1 is required regardless. Named regulatory owner should decide the form answer; the disclosure is not optional either way.
4. **The Gemini retention open item at `core/PLAY_DATA_SAFETY_2026-08-05.md:98-104` is still open.** Gym photos can contain non-users; "processed ephemerally" asserts something about Google's retention on the current billing tier that has not been confirmed. That is an Art. 6 question about bystanders, not only a form tick.
5. **Insurance module: delete or gate?** (R7) — my recommendation is delete, but it is a product decision.
6. **Named human owner.** Per this role's contract I cannot make a binding classification. R1, R2 and R3 need a named legal/regulatory owner's sign-off before store submission; R2 in particular should not ship in either locale pending that.

`release_blockers`: R1, R2. `required_human_review`: R1, R2, R3, R7, plus open items 1–4.

**Sources:** [Play Console — Android Health Permissions: Guidance and FAQs](https://support.google.com/googleplay/android-developer/answer/12991134?hl=en) · [Play Console — Health Content and Services](https://support.google.com/googleplay/android-developer/answer/16679511?hl=en) · [Android Developers — Plan compliance with privacy policies (Health Connect)](https://developer.android.com/health-and-fitness/guides/health-connect/plan/user-privacy) · [Play Console — Policy announcement, 15 April 2026](https://support.google.com/googleplay/android-developer/answer/16926792?hl=en) · [FDA — General Wellness: Policy for Low Risk Devices (reissued 6 Jan 2026)](https://www.fda.gov/regulatory-information/search-fda-guidance-documents/general-wellness-policy-low-risk-devices)
