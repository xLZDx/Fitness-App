# docs/ — screenshot index

Emulator screenshots captured while verifying phases on `Pixel_API_34`.

**For AI agents: these are historical verification artefacts, not a UI spec.** They record what a
screen looked like at the moment a phase was signed off, which may be many commits ago. Do not treat
them as the current design, and do not open them to "check the UI" — build and run the app instead
(`scripts/dev/run_app.ps1`). Reading images is expensive and these will mislead you if stale.

The only reason to open one: comparing against a specific past phase during a regression hunt.

## Naming convention

Files are prefixed by the phase whose verification produced them.

| Prefix | Phase | Subject |
|---|---|---|
| `fb_*` | Firebase wiring | Sign-in flow — clean login, post-signin, post-finish states. See `core/PHASE_1B_FIREBASE_SETUP.md` |
| `p1_*` | Phase 1 | Login + the 7 onboarding steps (`p1_step2` … `p1_step7`) |
| `p2_*`, `p2c_*` | Phase 2 | Home, login, onboarding, scan + scan-camera. `p2c_` = the continue-flow pass |
| `p3d_*` | Phase 3d | Boot + login regression pass |
| `p4b_*` | Phase 4B | Stripe subscription flow incl. relaunch checks. See `core/PHASE_4B_STRIPE_SETUP.md` |

## Tracked vs ignored

34 curated screenshots are **tracked**. The rest (~64: `01_*` … `06_*`, `home_*`, `train_*`,
`login_*`, `v3_*`, `rec_frames/`, `app_screenshot.png`, `reference_full.png`) are **gitignored**
scratch captures — see the `.gitignore` block. They exist only on the machine that captured them, so
never reference them from a doc.

Per-session debug captures live elsewhere entirely: `logs/sessions/<latest>/` (also gitignored),
written by `scripts/dev/debug_daemon.ps1`.
