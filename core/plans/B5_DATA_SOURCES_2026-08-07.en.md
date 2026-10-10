# B5 — Equipment Training Images: Measured Sources and Roboflow Update (English Translation)

**Original:** [B5 data-source investigation](B5_DATA_SOURCES_2026-08-07.md), original Git blob `3dc76b32737a08b74aecf587e18a86ac37775a5d`.  
**Checkpoint:** August 7, 2026, with an **appended update later the same day after the operator supplied Roboflow access**.  
**Status:** Historical data-source/licensing investigation, **not a new authorization to scrape, download, license or train models**.

The original gate had become blocked on data. This source recorded **what was measured**, with which pipeline, and which options remained. Crucially, the first part's conclusion that Roboflow required an owner action was **superseded by the appended update**. Both states are kept below.

## 1. Existing image crawler no longer worked

`crawl_dataset.py` using `icrawler` + Bing had produced model v1 on July 29. At the August 7 checkpoint it returned **zero** images.

The test deliberately compared license-filtered and unfiltered queries:

```text
hip abductor, no licence filter        0 images
hip abductor, commercial,modify        0 images
treadmill, commercial,modify           0 images
treadmill, creativecommons             0 images
```

Zero **even without a license filter** meant the filter alone did not explain the empty result.

Network reachability was not the issue: `bing.com/images/search` and `raw.githubusercontent.com` both returned **HTTP 200**. The source concluded the Bing markup parser in `icrawler` had stopped matching the search-results format since July 29.

Repairing a scraper for another site's moving HTML was inherently brittle. Furthermore a search engine's **license label** is not the same as license evidence from the actual file owner, so it would not meet the operator's requirement to use content only when legally usable source metadata supports it.

## 2. The crawler did support license filters

`icrawler.builtin.bing.BingFeeder.get_filter` supported the source's requested values `publicdomain`, `creativecommons`, `commercial` and `commercial,modify`. `crawl_v2.py` set such a filter.

**The filter's existence did not make data retrieval work** until the parser issue was solved, nor did it certify any downloaded image's rights.

## 3. Wikimedia Commons — attributable licenses, too little coverage

The source found file-level rights data in Wikimedia API `extmetadata.LicenseShortName`, with examples `CC BY 4.0`, `CC BY-SA 3.0` and `Public domain`. API calls needed an identifying User-Agent to avoid HTTP 403.

A search over **70 catalogue classes**, with `gsrlimit=100` and `filetype:bitmap`, reported:

```text
Total candidate images across 70 classes      561
Classes with at least 50 images                 2 / 70
Classes with no candidate images               25 / 70
```

Among the **25 empty classes** was `hip_abductor_adductor`, the same machine that earlier generated a wrong `treadmill 0.892` prediction.

**561 / 70 ≈ 8** images per class, while the historical training target wanted **100+** per class. Under that sampling approach the source concluded Wikimedia alone would **not** supply a sufficiently broad training corpus. This is a dated measurement with specific queries, not proof that no licensed photos could ever be found.

## 4. Original options before the Roboflow key arrived

The author ranked:

**A. Collect original gym photos with the operator.** Highest domain relevance and fewer third-party licensing issues because the team could control its own capture. The earlier 30 gym images gave the only realistic evaluation set in the project. The plan estimated roughly **69 machines × 20–30 perspectives** could be captured over several visits. Real-user angles were the differentiating data distribution missing from the catalogue.

**Important license/privacy nuance:** Ownership of the camera or a location does **not** automatically resolve privacy/portrait/property rights for bystanders. Capture rights, consent and data processing still require actual review. The existing **30 owner photos were a held-out TEST set**, not training data.

**B. Roboflow Universe.** Public datasets of gym equipment might provide thousands of frames, some with explicit CC BY license metadata. The initial source thought a Roboflow API key required an owner action and was not then available to the implementer.

**C. Repair Bing scraper.** It might restore volume, but the search results were catalogue-like, brittle, and only heuristically labeled for licensing. It was ranked lowest.

A and B were complementary: licensed external data for rare classes, original gym captures for realistic angles and background clutter.

## 5. Data pipeline already prepared

- `classes.py`: **70 catalogue classes + `none`**, with `bench` / `adjustable_bench` duplicate resolved.
- `crawl_v2.py`: license filter, resumable collection, identification of underrepresented classes.
- `eval_on_gym_photos.py`: evaluate on the **30 held-out owner photographs**, rejecting a model with mismatched output-label count (verified `FAIL` on v1).
- **Four of the 30** gym photographs had known labels at that point; no training on this protected test set.

Once authorized data was actually available: collect, train, export and evaluate. Source readiness of scripts was **not** proof of licensed data readiness or model quality.

---

# Appended August 7 update — source found after Roboflow access

The original reported that the owner provided a Roboflow API key **later in the conversation**. This superseded the earlier "owner decision/key still needed" statement in Section 4: **Option B was selected**.

**Security requirement:** The key had been pasted in cleartext into chat and logs. The source explicitly recommended **rotating/reissuing it after collection**. This translation intentionally neither reads nor reproduces the secret. Whether it was later rotated must be independently checked.

## Measured Roboflow inventory at that checkpoint

```text
Roboflow Universe datasets labeled CC BY 4.0     36
Total candidate images                        44,524
Catalogue classes covered by naive name map   45 / 69
```

Compared with **561** Wikimedia candidates, this represented about **79×** more source images. The source claimed dataset metadata explicitly labeled `license: CC BY 4.0` rather than relying on a search engine's conjecture.

**Rights caveat:** Dataset labels are candidate evidence, not a complete guarantee of provenance, commercial sublicense, bystander consent or fitness-app use rights. Review every dataset and distribution permission before downloading/retraining/releasing.

### Four historical failure machines had candidate Roboflow coverage

| Actual machine / proposed class | Wrong v1 outcome | Dataset contained candidate examples |
| --- | --- | --- |
| `hip_abductor_adductor` | `treadmill` 0.892 | Yes |
| `shoulder_press_machine` | `leg_press` 0.897 | Yes |
| `ab_crunch_machine` | `treadmill` 0.742 | Yes |
| `leg_extension` | `treadmill` 0.23 | Yes |

Largest source datasets the record listed:

- `xiaoshis-workspace/gym-equipment-t6kck` — **10,615** images, 20+ classes.
- `bangkit-academy-ognnb/gym-equipment-object-detection` — **6,620** images, 13 classes.
- `thestalkers-project/gym-equipment-ersfc` — **5,158** images, overlapping those 13 classes.
- `fitfuel/all-gym-equipment` — **1,947** images, 20+ classes.

### The 24 classes not matched by naive names

`squat_rack`, `ab_mat`, `ab_wheel`, `balance_board`, `captains_chair`, `ez_curl_bar`, `foam_roller`, `gymnastic_rings`, `mini_trampoline`, `outdoor_air_walker`, `parallettes`, `plyo_box`, `preacher_curl_bench`, `punching_bag`, `recumbent_bike`, `sandbag`, `ski_erg`, `skipping_rope`, `sliding_disc`, `stability_ball`, `trx`, `tyre`, `vertical_pole` and `yoga_blocks`.

Most were small equipment rather than weight machines. The absence of `squat_rack` was suspicious: naive name matching would miss aliases such as **power rack** or **rack**. **Check synonyms before declaring a class unrepresented.**

### Proposed next data step — detection versus classification

The collected datasets were annotated for **object detection**, but the app needed **classification**. The source treated bounding-box cropping as helpful: crop the actual machine from a gym photo instead of letting empty background dominate.

Proposed order:

1. Obtain authorized, properly licensed datasets.
2. Crop by detection bounding boxes.
3. Map original Roboflow labels to canonical catalogue IDs.
4. Add negative examples for the explicit `none` class.
5. Train a new classifier on training data.
6. Evaluate it on the **unchanged, reserved 30 owner gym photos** through `eval_on_gym_photos.py`.

This plan must account for dataset splits, duplicate leakage, per-machine/per-gym holdouts, class imbalance, license provenance and consent. The historic record did not prove these safeguards were all complete.

## Original API-key warning

The operator-supplied Roboflow key had appeared **in plain chat and logs**. After gathering data, the source recommended rotating it in Roboflow account settings. No key value is reproduced here and no secret rotation is claimed as complete.

## Translation and verification boundary

This companion preserves the original Sections 1–5 and chronological Roboflow update, all source measurements (561, 25/70 empty, 36 datasets, 44,524 images, 45/69 name-based coverage and four failure cases), **historical supersession** of the initial access blocker, and the absolute distinction between held-out **TEST** and training images.

The dates, source API rules and licensing assumptions were **not newly revalidated**. No third-party images, protected owner photos, vendor credential, training jobs, customer data or model/application code were accessed or modified by this translation.

**Status: COMPLETE SOURCE-LINKED HISTORICAL ENGLISH COMPANION FOR REVIEW; NOT TRAINING/DATA-USE AUTHORIZATION.**
