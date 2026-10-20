# Move the SPTR site prototype out of the Firebase hosting root

Why: firebase.json has hosting.public = "public" with an ignore list that does not exclude index.html or assets, so the previous commit (marketing merge) would have published the internal, noindex site prototype (public/index.html and public/assets/sptr/*) on the next hosting deploy.
What: git mv public/index.html -> marketing/site-prototype/index.html; git mv public/assets/sptr -> marketing/site-prototype/assets/sptr (content unchanged, renames only; the HTML uses root-absolute /assets/sptr/... URLs, which keep working when marketing/site-prototype/ is served as the web root for a preview). public/ keeps only the original BASE files (checkout/portal pages, privacy, terms, coach).
Updated: scripts/marketing/claim_lint.py (HTML_PATH, JS_PATH and doc text), core/marketing/claim_register.json (note line), regenerated core/marketing/SPTR_MARKETING_SITE_CLAIM_REGISTER_2026-08-19.md with --write-register.
Not changed: historical prose in core/marketing/*IMPLEMENTATION/GOVERNANCE/QA docs, reports/SPTR_SITE_BUILD_2026-08-19.html and the previous change record still say public/index.html; they describe the branch at the time it was written.
Checks: claim_lint.py PASS (22 claims, 0 issues); --self-test run; no deleted files (renames only); git ls-files public shows no sptr or index.html.
