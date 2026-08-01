# -*- coding: utf-8 -*-
"""Create the public bucket the exercise videos are served from.

WHY A PLAIN GCS BUCKET AND NOT FIREBASE STORAGE

Firebase Storage's default bucket requires the project's DEFAULT RESOURCE
LOCATION to be set, and `traidingbot-b4061` has never had one — its
`resources` block holds a hosting site and nothing else. That setting is
permanent: it decides where Firestore and Storage data live for the life of the
project and Google provides no way to change it afterwards. Making that choice
as a side effect of uploading some demonstration videos would be deciding
something much larger than the task.

A plain bucket needs no such choice, is deleted in one command, and gives the
app exactly what it needs: an HTTPS url a video player can open. Firebase
Storage's SDK, security rules and console are all things this content does not
use — the clips are public demonstration footage listed in a catalog that ships
inside the APK.

THE COST DIFFERENCE, STATED RATHER THAN HIDDEN

The Firebase-managed bucket would have given 100 GB/month of free egress. A
plain bucket's always-free tier is 1 GB/month from North America — about a
thousand clip plays at this library's ~1 MB average. Past that the project is
on Blaze (Cloud Functions v2 is deployed, which requires it) and egress bills
at roughly $0.12/GB, so the next thousand plays cost about twelve cents.

That is the right trade while the app has one user, and if traffic ever makes
it wrong the answer was never Firebase — it is Cloudflare R2, whose egress is
free at any volume. Moving there is one constant, by design.

REGION: us-central1, matching the project's existing Cloud Functions buckets.
Serving from the same region as the rest of the project is one less thing that
surprises someone later.
"""
from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from firebase_api import PROJECT, access_token, api  # noqa: E402

BUCKET = f'{PROJECT}-videos-eu'
# EUROPE-WEST1, not us-central1.
#
# The first version of this matched the project's Cloud Functions buckets,
# which was tidy and wrong: functions are called by other Google services,
# video is fetched by a phone. The phone is in Moldova, and the round trip
# to Iowa costs about 80 ms on every first byte — paid once per clip, on a
# screen whose whole job is to start playing quickly. Firestore is already
# in eur3, so this also puts the two in the same part of the world.
LOCATION = 'EUROPE-WEST1'


def main() -> None:
    t = access_token()

    existing = api(f'https://storage.googleapis.com/storage/v1/b/{BUCKET}', t)
    if '_httpError' not in existing:
        print(f'bucket already exists: {BUCKET} ({existing.get("location")})')
    else:
        made = api(
            f'https://storage.googleapis.com/storage/v1/b?project={PROJECT}',
            t,
            method='POST',
            payload={
                'name': BUCKET,
                'location': LOCATION,
                'storageClass': 'STANDARD',
                # Uniform access: per-object ACLs are the older model and the
                # usual way a bucket ends up with objects nobody can read and
                # nobody can explain.
                'iamConfiguration': {
                    'uniformBucketLevelAccess': {'enabled': True},
                    # The org policy that blocks `allUsers` grants. Off, because
                    # the whole point is that a phone with no credentials can
                    # fetch a clip.
                    'publicAccessPrevention': 'inherited',
                },
            })
        if '_httpError' in made:
            sys.exit(f'create failed {made["_httpError"]}: {made["_body"]}')
        print(f'created {BUCKET} in {made.get("location")}')

    # Public read, and ONLY read. `objectViewer` cannot list the bucket, cannot
    # write and cannot delete; the catalog carries every path the app needs, so
    # listing buys nothing and hands an index to anyone who asks.
    policy = api(f'https://storage.googleapis.com/storage/v1/b/{BUCKET}/iam', t)
    if '_httpError' in policy:
        sys.exit(f'iam read failed {policy["_httpError"]}: {policy["_body"]}')
    bindings = policy.get('bindings', [])
    already = any(b['role'] == 'roles/storage.objectViewer'
                  and 'allUsers' in b.get('members', []) for b in bindings)
    if already:
        print('public read already granted')
    else:
        bindings.append({'role': 'roles/storage.objectViewer',
                         'members': ['allUsers']})
        policy['bindings'] = bindings
        out = api(f'https://storage.googleapis.com/storage/v1/b/{BUCKET}/iam',
                  t, method='PUT', payload=policy)
        if '_httpError' in out:
            sys.exit(f'iam write failed {out["_httpError"]}: {out["_body"]}')
        print('granted public read to allUsers')

    print(f'\nbase url: https://storage.googleapis.com/{BUCKET}/exercises')


if __name__ == '__main__':
    main()
