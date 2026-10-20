# Figma — Final Minimum Scope Before Development, v1.5 (English Translation)

**Original:** [`FIGMA_FINAL_MINIMUM_SCOPE_PROMPT_v1.5.md`](FIGMA_FINAL_MINIMUM_SCOPE_PROMPT_v1.5.md), Git blob `e1d91e5eddd2fb71350794ff5e80d72579faf219`. The identically hashed copy with ` (1)` in its filename is historical source duplication, not another independent set of requirements.

**Historical design constraint:** Most Fitness App design work was described as already completed at this checkpoint. **Do not** continue building a complete clickable prototype, spending Figma tokens on route wiring, every offline branch, or duplicate platform screen copies. Complete **only one critical missing design block** before handing the work back to engineering.

# Exercise Page

This is a standalone exercise details screen reachable from **Equipment Page, Search, Programs and Workout context**.

## Mandatory loaded state

Display all **eleven** functional groups:

1. **Hero media:** Poster before playback; anatomical animation/video playing state; play/pause; mute/sound only when available; media-unavailable fallback.
2. Exercise name.
3. Primary and secondary muscles.
4. Required equipment, experience level and movement category.
5. **Personal suitability:** "Suitable for you", "Suitable with restrictions", and an understandable reason supporting the state.
6. **"Why this was recommended to you"** section.
7. **Technique:** Three primary steps first; the complete instructions can be expanded on request.
8. **Common mistakes:** Concise list, optional highlighting of a problem area only if useful.
9. Restrictions and safety notes.
10. **Previous performance and history:** Last weight, repetitions and sets, last performed date, personal record if actually recorded, and an empty state **without fake data**.
11. Primary contextual actions: **Start exercise**, **Add to workout**, **Technique Coach**, **Ask AI Coach**.

**Technique Coach must be visibly accessible** next to the technique area or main action group; it must not be buried in the overflow menu. This source requests a design entry point, not proof that technique recognition is implemented.

## Critical states

Create **only** these variants:

- Loaded
- Loading / skeleton
- Media unavailable
- No history
- Restriction warning
- Long Russian UI text / **1.6** text scale

Do not spend the remaining design budget on unrelated variants.

## Light theme — optional only if budget remains

**Do not redraw the entire application.** If enough tokens/resources remain, provide only:

1. Light semantic color palette
2. Exercise Page in light theme
3. Home in light theme
4. One representative camera/workout light-theme anchor

This is optional at the checkpoint, not a weakening of later accessibility or brand requirements.

## Developer handoff

Mark the frames **Ready for development**, with annotations covering:

- Route intent
- Source of media assets
- Expand/collapse behavior
- Technique Coach entry
- AI Coach entry
- Loading/error rules
- Sticky CTA behavior
- Accessibility notes

**After this, STOP. Do not add other screens.** The original Figma STOP remains binding for this historical design gate; an English companion does not authorize further implementation or acceptance.

**Status:** Faithful English design-brief companion. Original source unchanged. No Figma rendering, Flutter development, real-user data processing or gate signoff performed.
