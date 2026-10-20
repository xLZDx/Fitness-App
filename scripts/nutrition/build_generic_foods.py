#!/usr/bin/env python3
"""Build mobile/assets/nutrition/generic_foods_v1.json from USDA FoodData Central.

Ticket C21 (design section 17.5, D-71). NOT run in CI: an operator or an agent runs it
once, offline, and commits the output. The app only ever reads the committed JSON.

Sources (CC0 1.0, public domain): FDC "Foundation Foods" and "SR Legacy" JSON downloads
from https://fdc.nal.usda.gov/download-datasets . Nutrient ids kept: 1008 energy kcal,
1003 protein, 1005 carbohydrate, 1004 fat (all per 100 g). When 1008 is absent the
Atwater general-factor energy (2047, then 2048) is used, and if that is also absent the
energy is derived 4/4/9 from the macros and the row is flagged `derivedEnergy`.

Row shape (design 17.5):
  {id: "gen:<fdcId>", name, category, per100g: {kcal, proteinG, carbsG, fatG},
   sourceId: "usda_fdc", fdcId, tags: {...}}

Tags are authored by category and keyword rules below. UNCERTAIN TAGS DEFAULT TO THE
RESTRICTIVE SIDE: `animalProduct` / `pescatarianOk` are null when unknown, and
`allergenCertain` is false whenever the category is a mixed or processed food whose
ingredient list is not known. The Dart suggestion filter hides such rows from
suggestions (they stay searchable, with a warning).

Usage (from the repo root):
  python scripts/nutrition/build_generic_foods.py --download
  python scripts/nutrition/build_generic_foods.py \
      --foundation-zip F.zip --sr-legacy-zip S.zip
Standard library only. Output is deterministic (sorted, no timestamps).
"""
from __future__ import annotations

import argparse
import io
import json
import re
import sys
import urllib.request
import zipfile
from pathlib import Path

FOUNDATION_URL = (
    "https://fdc.nal.usda.gov/fdc-datasets/"
    "FoodData_Central_foundation_food_json_2024-10-31.zip"
)
SR_LEGACY_URL = (
    "https://fdc.nal.usda.gov/fdc-datasets/"
    "FoodData_Central_sr_legacy_food_json_2018-04.zip"
)

DEFAULT_OUT = Path("mobile/assets/nutrition/generic_foods_v1.json")

# Categories dropped outright: brand, restaurant or infant products are not "generic".
EXCLUDED_CATEGORIES = {
    "Baby Foods",
    "Fast Foods",
    "Restaurant Foods",
    "American Indian/Alaska Native Foods",
}

# Per-category row caps for SR Legacy (Foundation rows are always kept first). Rows are
# ranked simplest-name-first so that "Beef, ground, raw" wins over a long cut variant.
CATEGORY_CAP = {
    "Beef Products": 110,
    "Vegetables and Vegetable Products": 380,
    "Baked Products": 160,
    "Lamb, Veal, and Game Products": 60,
    "Poultry Products": 130,
    "Beverages": 110,
    "Sweets": 140,
    "Fruits and Fruit Juices": 230,
    "Pork Products": 100,
    "Dairy and Egg Products": 190,
    "Legumes and Legume Products": 150,
    "Finfish and Shellfish Products": 170,
    "Soups, Sauces, and Gravies": 90,
    "Fats and Oils": 80,
    "Breakfast Cereals": 90,
    "Cereal Grains and Pasta": 130,
    "Snacks": 70,
    "Sausages and Luncheon Meats": 70,
    "Nut and Seed Products": 110,
    "Meals, Entrees, and Side Dishes": 40,
    "Spices and Herbs": 40,
}

# Words that mark a brand or a manufacturer formulation; such rows are skipped.
BRAND_WORDS = re.compile(
    r"\b(pillsbury|kellogg|general mills|nabisco|campbell|heinz|kraft|nestle|mcdonald|"
    r"burger king|wendy|usda commodity|babyfood|gerber|post |quaker|keebler|"
    r"frito|oscar mayer|hormel|tyson|ocean spray|snapple|gatorade|"
    r"pepsi|coca|mars |hershey|cadbury|starbucks|subway|domino|pizza hut|taco bell|"
    r"kfc|popeyes|applebee|denny|ihop|olive garden|little caesars|school lunch)\b",
    re.IGNORECASE,
)

ANIMAL_CATEGORIES = {
    "Beef Products",
    "Lamb, Veal, and Game Products",
    "Poultry Products",
    "Pork Products",
    "Sausages and Luncheon Meats",
}
PLANT_CATEGORIES = {
    "Vegetables and Vegetable Products",
    "Fruits and Fruit Juices",
    "Legumes and Legume Products",
    "Nut and Seed Products",
    "Spices and Herbs",
    "Cereal Grains and Pasta",
}
# Mixed or processed: ingredient list unknown -> allergens never "certain".
UNCERTAIN_ALLERGEN_CATEGORIES = {
    "Baked Products",
    "Breakfast Cereals",
    "Snacks",
    "Sweets",
    "Soups, Sauces, and Gravies",
    "Meals, Entrees, and Side Dishes",
    "Sausages and Luncheon Meats",
}

ANIMAL_WORDS = re.compile(
    r"\b(beef|pork|bacon|ham|lamb|veal|chicken|turkey|duck|goose|egg|eggs|milk|cheese|"
    r"cream|butter|whey|casein|yogurt|yoghurt|meat|fish|tuna|salmon|shrimp|lard|tallow|"
    r"gelatin|honey|liver|sausage|broth|bouillon)\b",
    re.IGNORECASE,
)
PORK_WORDS = re.compile(r"\b(pork|bacon|ham|lard|prosciutto|salami|pepperoni|swine)\b", re.I)
ALCOHOL_WORDS = re.compile(
    r"\b(alcoholic|beer|wine|liqueur|liquor|whiskey|vodka|rum|gin|brandy|sake|cider, alcoholic)\b",
    re.I,
)
GLUTEN_WORDS = re.compile(
    r"\b(wheat|barley|rye|oat|oats|bread|pasta|macaroni|spaghetti|noodle|noodles|flour|"
    r"bulgur|couscous|semolina|spelt|triticale|kamut|malt|biscuit|cracker|crackers|cake|"
    r"cookie|cookies|muffin|pie|pastry|bagel|roll|rolls|pretzel|pretzels|croissant|"
    r"pancake|waffle|tortilla|pita|seitan|farina|cereal|granola|stuffing|crouton)\b",
    re.I,
)
GLUTEN_FREE_WORDS = re.compile(r"\b(rice|corn|cornmeal|gluten.free|buckwheat|millet|quinoa|amaranth|sorghum)\b", re.I)
SHELLFISH_CRUST = re.compile(r"\b(crab|lobster|shrimp|crayfish|crawfish|prawn|krill)\b", re.I)
SHELLFISH_MOLL = re.compile(
    r"\b(clam|clams|oyster|oysters|mussel|mussels|scallop|scallops|squid|octopus|"
    r"abalone|snail|cuttlefish|whelk|conch)\b",
    re.I,
)
TREE_NUTS = re.compile(
    r"\b(almond|almonds|walnut|walnuts|cashew|cashews|pecan|pecans|pistachio|pistachios|"
    r"hazelnut|hazelnuts|filbert|filberts|brazil|macadamia|pine nuts?|mixed nuts|chestnuts?|"
    r"beechnuts?|ginkgo|hickory)\b",
    re.I,
)
SOY_WORDS = re.compile(r"\b(soy|soya|soybean|soybeans|tofu|tempeh|miso|natto|edamame)\b", re.I)
PLANT_FAT_WORDS = re.compile(r"^(oil|shortening|margarine)\b", re.I)
ANIMAL_FAT_WORDS = re.compile(
    r"\b(butter|lard|tallow|ghee|fish|cod liver|chicken|beef|pork|duck|goose|mutton|"
    r"mayonnaise|cream|bacon)\b",
    re.I,
)
PLAIN_BEVERAGE = re.compile(
    r"^beverages?, (coffee|tea|water|carbonated|club soda|tonic|lemonade|fruit juice)",
    re.I,
)


# An ALL-CAPS token of 3+ letters in an SR Legacy description is a brand (BULL'S-EYE).
BRAND_CAPS = re.compile(r"\b(?!USDA\b|UHT\b|BBQ\b|NFS\b|NS\b)[A-Z][A-Z'&-]{2,}\b")


def classify(name: str, category: str) -> dict:
    """Author diet/allergen tags from category and keyword rules.

    Restrictive on doubt: unknown animal/pescatarian status is None (not False).
    """
    lower = name.lower()
    allergens: set[str] = set()
    animal: bool | None = None
    pesc: bool | None = None
    certain = category not in UNCERTAIN_ALLERGEN_CATEGORIES
    pork = bool(PORK_WORDS.search(lower)) or category == "Pork Products"
    alcohol = bool(ALCOHOL_WORDS.search(lower))

    if category in ANIMAL_CATEGORIES:
        animal, pesc = True, False
    elif category == "Finfish and Shellfish Products":
        animal, pesc = True, True
        if SHELLFISH_CRUST.search(lower):
            allergens.add("crustaceans")
        elif SHELLFISH_MOLL.search(lower):
            allergens.add("molluscs")
        else:
            allergens.add("fish")
        if re.search(r"\b(breaded|battered|fried|sticks|cakes|salad|paste|spread|sauce)\b", lower):
            certain = False
    elif category == "Dairy and Egg Products":
        animal, pesc = True, True
        if re.search(r"\begg\b|\beggs\b", lower):
            allergens.add("eggs")
        else:
            allergens.add("milk")
        if re.search(r"\b(substitute|imitation|non.?dairy|replacement|analog)\b", lower):
            allergens.update({"milk", "eggs"})
            animal, pesc, certain = None, None, False
    elif category in PLANT_CATEGORIES:
        animal, pesc = False, True
        if ANIMAL_WORDS.search(lower):
            animal, pesc, certain = None, None, False
    elif category == "Fats and Oils":
        if ANIMAL_FAT_WORDS.search(lower):
            animal, pesc = True, False
            if re.search(r"\bfish|cod liver\b", lower):
                pesc = True
                allergens.add("fish")
            if re.search(r"\b(butter|ghee|cream)\b", lower):
                pesc = True
                allergens.add("milk")
            if "mayonnaise" in lower:
                pesc = True
                allergens.add("eggs")
        elif PLANT_FAT_WORDS.search(lower) and not re.search(r"margarine|shortening", lower):
            animal, pesc = False, True
        else:
            certain = False  # margarines, dressings, spreads: often contain milk or egg
            allergens.update({"milk", "eggs"})
    elif category == "Beverages":
        if PLAIN_BEVERAGE.search(name) and not ANIMAL_WORDS.search(lower):
            animal, pesc = False, True
        else:
            certain = False
        if ANIMAL_WORDS.search(lower):
            animal, pesc = None, None
            certain = False
    else:
        # Baked, cereals, snacks, sweets, soups, meals: unknown composition.
        animal, pesc, certain = None, None, False

    # Keyword allergens that apply across categories.
    if SOY_WORDS.search(lower):
        allergens.add("soy")
    if re.search(r"\bpeanut|peanuts\b", lower):
        allergens.add("peanuts")
    if TREE_NUTS.search(lower):
        allergens.add("treeNuts")
    if re.search(r"\bsesame|tahini\b", lower):
        allergens.add("sesame")
    if re.search(r"\blupin|lupine\b", lower):
        allergens.add("lupin")
    if re.search(r"\bcelery|celeriac\b", lower):
        allergens.add("celery")
    if re.search(r"\bmustard\b", lower):
        allergens.add("mustard")
    if re.search(r"\bsulfite|sulphite|sulfured|dried (apricots|fruit)|wine\b", lower):
        allergens.add("sulphites")
    if re.search(r"\b(milk|cheese|cream|yogurt|whey|butter)\b", lower) and category not in (
        "Dairy and Egg Products",
    ):
        allergens.add("milk")
        if category in PLANT_CATEGORIES or category == "Beverages":
            certain = False
    if re.search(r"\beggs?\b", lower):
        allergens.add("eggs")
    if GLUTEN_WORDS.search(lower) or (
        category in {"Baked Products", "Breakfast Cereals", "Snacks", "Soups, Sauces, and Gravies",
                     "Meals, Entrees, and Side Dishes"}
        and not GLUTEN_FREE_WORDS.search(lower)
    ):
        if not (GLUTEN_FREE_WORDS.search(lower) and not re.search(r"wheat|barley|rye|oat", lower)):
            allergens.add("gluten")
    if category == "Sweets" and not GLUTEN_FREE_WORDS.search(lower):
        # Sweets (cookies, bars, candy) may carry gluten, milk, nuts: never "certain".
        certain = False

    tags = {
        "allergens": sorted(allergens),
        "allergenCertain": bool(certain),
        "animalProduct": animal,
        "pescatarianOk": pesc,
    }
    if pork:
        tags["pork"] = True
    if alcohol:
        tags["alcohol"] = True
    return tags


def nutrient_map(food: dict) -> dict[int, float]:
    out: dict[int, float] = {}
    for fn in food.get("foodNutrients", []):
        nid = fn.get("nutrient", {}).get("id")
        amount = fn.get("amount")
        if nid in (1008, 1003, 1005, 1004, 2047, 2048) and amount is not None:
            out[int(nid)] = float(amount)
    return out


def to_row(food: dict) -> dict | None:
    cat = food.get("foodCategory", {}).get("description", "")
    name = (food.get("description") or "").strip()
    if not name or cat in EXCLUDED_CATEGORIES or BRAND_WORDS.search(name) or BRAND_CAPS.search(name):
        return None
    n = nutrient_map(food)
    if not all(k in n for k in (1003, 1004, 1005)):
        return None
    protein, fat, carbs = n[1003], n[1004], n[1005]
    derived = False
    if 1008 in n:
        kcal = n[1008]
    elif 2047 in n:
        kcal = n[2047]
    elif 2048 in n:
        kcal = n[2048]
    else:
        kcal = 4 * protein + 4 * carbs + 9 * fat
        derived = True
    if not (0 <= kcal <= 900) or max(protein, carbs, fat) > 100:
        return None
    display = re.sub(r"\s*\(Includes foods for USDA's Food Distribution Program\)", "", name)
    display = display[0].upper() + display[1:]
    row = {
        "id": f"gen:{food['fdcId']}",
        "name": display,
        "category": cat,
        "per100g": {
            "kcal": round(kcal, 1),
            "proteinG": round(protein, 2),
            "carbsG": round(carbs, 2),
            "fatG": round(fat, 2),
        },
        "sourceId": "usda_fdc",
        "fdcId": int(food["fdcId"]),
        "tags": classify(display, cat),
    }
    if derived:
        row["derivedEnergy"] = True
    return row


def simplicity(row: dict) -> tuple:
    name = row["name"]
    return (name.count(","), len(name), name)


def _load_zip(source: str | Path, url: str, key: str) -> list[dict]:
    if source:
        data = Path(source).read_bytes()
    else:
        print(f"downloading {url}", file=sys.stderr)
        with urllib.request.urlopen(url, timeout=300) as resp:  # noqa: S310 (fixed https URL)
            data = resp.read()
    with zipfile.ZipFile(io.BytesIO(data)) as z:
        member = z.namelist()[0]
        return json.loads(z.read(member).decode("utf-8"))[key]


def build(foundation: list[dict], sr_legacy: list[dict]) -> list[dict]:
    rows: dict[str, dict] = {}
    seen_names: set[str] = set()
    for food in sorted(foundation, key=lambda f: f["fdcId"]):
        row = to_row(food)
        if row and row["name"].lower() not in seen_names:
            rows[row["id"]] = row
            seen_names.add(row["name"].lower())
    by_cat: dict[str, list[dict]] = {}
    for food in sr_legacy:
        row = to_row(food)
        if row:
            by_cat.setdefault(row["category"], []).append(row)
    for cat, items in by_cat.items():
        cap = CATEGORY_CAP.get(cat, 0)
        kept = sum(1 for r in rows.values() if r["category"] == cat)
        for row in sorted(items, key=simplicity):
            if kept >= cap:
                break
            key = row["name"].lower()
            if key in seen_names:
                continue
            rows[row["id"]] = row
            seen_names.add(key)
            kept += 1
    return sorted(rows.values(), key=lambda r: (r["category"], r["name"], r["fdcId"]))


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--foundation-zip", default="", help="local Foundation JSON zip")
    ap.add_argument("--sr-legacy-zip", default="", help="local SR Legacy JSON zip")
    ap.add_argument("--download", action="store_true", help="fetch missing zips from fdc.nal.usda.gov")
    ap.add_argument("--out", default=str(DEFAULT_OUT))
    args = ap.parse_args()
    if not args.download and not (args.foundation_zip and args.sr_legacy_zip):
        ap.error("pass --download or both --foundation-zip and --sr-legacy-zip")
    foundation = _load_zip(args.foundation_zip, FOUNDATION_URL, "FoundationFoods")
    sr_legacy = _load_zip(args.sr_legacy_zip, SR_LEGACY_URL, "SRLegacyFoods")
    rows = build(foundation, sr_legacy)
    doc = {
        "version": 1,
        "source": "USDA FoodData Central, Foundation Foods and SR Legacy (CC0 1.0)",
        "nutrientIds": {"kcal": 1008, "proteinG": 1003, "carbsG": 1005, "fatG": 1004},
        "foods": rows,
    }
    out = Path(args.out)
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(json.dumps(doc, ensure_ascii=False, separators=(",", ":")) + "\n", encoding="utf-8", newline="\n")
    print(f"wrote {len(rows)} rows to {out}", file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main())
