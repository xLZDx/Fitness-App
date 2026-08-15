#!/usr/bin/env python3
"""Template for wiring evals to the REAL Fitness-App recommendation runtime.

Do not make this return canned case expectations. Replace the bridge only after the
Recommendation Engine exists and can be invoked from a test seam.
"""

def recommend(case_input: dict) -> dict:
    raise RuntimeError(
        "REAL FITNESS-APP ADAPTER NOT CONNECTED. Implement a bridge to the app/runtime; "
        "the bundled reference adapter is not a release substitute."
    )
