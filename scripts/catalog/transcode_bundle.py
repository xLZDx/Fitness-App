# -*- coding: utf-8 -*-
"""Turn the purchased bundle into clips a phone can actually stream.

WHY THIS IS NOT OPTIONAL

Measured on the delivered archive, not guessed:

    vendor clip     3840x2160, 60 fps, ~26 Mbit/s, mean 13.9 MB
    our library     1920x1080, 30 fps, ~0.77 Mbit/s, mean 1.01 MB

The bundle ships 4K60. The app shows these in a block about 350 logical
points wide. Serving them raw would mean roughly 35 GB for 2,500 clips, at
$0.12/GB of egress — about four dollars every time somebody browsed the whole
catalog — and a phone spending fourteen megabytes to watch a five-second
demonstration of a cat stretch.

Re-encoded to 720p30 at CRF 24 the same clip is 0.25 MB. That is 66x smaller
than the source and four times smaller than what the app already serves, and
frames extracted from both are indistinguishable at the size they are
displayed. 720p is still twice the pixels the block can show; the headroom is
there so a tablet or a future full-screen player does not look soft.

WHITE BACKGROUND, AND THE GREEN-SCREEN FALLBACK

The bundle's main library renders on flat white, which is what the existing
653 posters and the app's video block already assume. The 1,413 green-screen
clips are a bonus, and for any exercise that exists ONLY as green screen,
`--key` composites it onto white so it matches everything else.

The key colour is sampled from the frame rather than assumed. The first
attempt used a guessed `0x00C800` with a 0.30 similarity and dissolved the
figure along with the background — these models are greyscale, so a loose key
takes the body too. The real background is `0x0FF906` and 0.10 is clean.
"""
from __future__ import annotations

import argparse
import concurrent.futures
import json
import subprocess
import sys
import tempfile
import threading
import zipfile
from pathlib import Path

from bundle_layout import plan_import

# Sampled from the delivered clips, not assumed. See the module docstring for
# what a guessed value did.
KEY_COLOUR = '0x0FF906'
KEY_SIMILARITY = '0.10'
KEY_BLEND = '0.02'

HEIGHT = 720
FPS = 30
CRF = 24


def probe(path: Path) -> dict:
    r = subprocess.run(
        ['ffprobe', '-v', 'error', '-select_streams', 'v:0',
         '-show_entries', 'stream=width,height,r_frame_rate',
         '-show_entries', 'format=duration,size',
         '-of', 'json', str(path)],
        capture_output=True, text=True)
    if r.returncode != 0:
        return {}
    return json.loads(r.stdout or '{}')


def build_filter(key: bool) -> tuple[list[str], str]:
    """ffmpeg args for the video filter, and a label for logging."""
    scale = f'scale=-2:{HEIGHT},fps={FPS}'
    if not key:
        return ['-vf', scale], 'white-source'
    # Scale FIRST, then key. Compositing at the source's 3840x2160 and scaling
    # afterwards is the textbook order — it avoids keying edge pixels that
    # downscaling has already blended — but it costs about thirty times the
    # work per clip, and across a 2,500-clip library that is the difference
    # between an afternoon and a week. On a flat synthetic background with no
    # motion blur there is nothing for the careful order to protect: the
    # sampled key is exact and the edges are hard.
    graph = (
        f'[0:v]{scale}[s];'
        f'color=white:s=1280x{HEIGHT}[bg];'
        f'[s]chromakey={KEY_COLOUR}:{KEY_SIMILARITY}:{KEY_BLEND}[k];'
        f'[bg][k]overlay=format=auto'
    )
    return ['-filter_complex', graph], 'chroma-keyed'


class ZipLibrary:
    """Feeds clips straight out of the archive, one at a time.

    Extracting the 4K bundle first would write 42 GB to disk, read it all back,
    and leave it there -- for a job whose entire output is under a gigabyte. So
    each worker pulls its own member to a temp file, encodes it, and deletes it:
    peak extra disk is `jobs` clips, about seventy megabytes, instead of forty
    gigabytes.

    A ZipFile is not safe to share across threads -- concurrent reads move one
    shared file position -- so each thread gets its own handle. Opening one
    re-reads the central directory, which for 2,578 entries is milliseconds and
    happens once per thread, not once per clip.
    """

    def __init__(self, path: Path):
        self.path = path
        self._local = threading.local()

    @property
    def _zip(self) -> zipfile.ZipFile:
        handle = getattr(self._local, "zip", None)
        if handle is None:
            handle = zipfile.ZipFile(self.path)
            self._local.zip = handle
        return handle

    def listing(self) -> dict[str, int]:
        with zipfile.ZipFile(self.path) as z:
            return {i.filename: i.file_size for i in z.infolist() if not i.is_dir()}

    def extract(self, member: str, into: Path) -> Path:
        # Suffix matters: ffmpeg picks its demuxer partly from the extension,
        # and a temp file called `tmp8kd2` makes it work harder to guess.
        fd, name = tempfile.mkstemp(suffix=".mp4", dir=into)
        target = Path(name)
        try:
            with self._zip.open(member) as src, open(fd, "wb") as dst:
                while chunk := src.read(1 << 20):
                    dst.write(chunk)
        except BaseException:
            target.unlink(missing_ok=True)
            raise
        return target


def transcode(src: Path, dst: Path, key: bool) -> tuple[Path, str]:
    dst.parent.mkdir(parents=True, exist_ok=True)
    # Written under a temporary name and renamed only on success.
    #
    # Not defensive plumbing — this bit me on the first dry run. The job was
    # killed part-way, ffmpeg left three files with no moov atom (unplayable,
    # "Invalid data found"), and the resume check below happily counted them
    # as done because they existed and were non-empty. An interrupted run
    # would have poisoned the output set silently.
    # `.partial.mp4`, not `.partial`: ffmpeg picks its output container from the
    # extension, and `x.partial` makes it give up with "unable to choose an
    # output format". The guard above was added after an interrupted run left
    # unplayable files, and until this dry run it had never itself been run --
    # so the fix for the silent-corruption bug was a total-failure bug.
    tmp = dst.with_suffix('.partial.mp4')
    vf, _ = build_filter(key)
    cmd = [
        'ffmpeg', '-v', 'error', '-i', str(src), *vf,
        '-c:v', 'libx264', '-crf', str(CRF), '-preset', 'slow',
        '-pix_fmt', 'yuv420p', '-profile:v', 'high', '-level', '4.0',
        # Moves the index to the front so a player can start on the first
        # bytes instead of waiting for the whole file. On a streamed clip this
        # is the difference between "instant" and "downloads, then plays".
        '-movflags', '+faststart',
        # Silent demonstrations. Dropping the track saves a little and removes
        # a whole class of "why is my phone making noise" report.
        '-an',
        str(tmp), '-y',
    ]
    try:
        r = subprocess.run(cmd, capture_output=True, text=True)
    except BaseException:
        tmp.unlink(missing_ok=True)
        raise
    if r.returncode != 0 or not tmp.exists() or tmp.stat().st_size == 0:
        tmp.unlink(missing_ok=True)
        return dst, r.stderr.strip()[:200] or 'ffmpeg produced nothing'
    tmp.replace(dst)
    return dst, ''


def _plan_from_zip(source: Path, dest: Path) -> tuple[list, dict, ZipLibrary]:
    """Every clip worth encoding, under the object key it will be served from."""
    library = ZipLibrary(source)
    listing = library.listing()
    plan = plan_import(listing)

    print(f'{len(listing)} members -> {len(plan.chosen)} clips '
          f'({plan.total_discarded} duplicate renders dropped)')
    if plan.ambiguous:
        # Not a warning to be scrolled past: the frames showed two different
        # machines, so one real exercise is being left out of the library.
        print('  AMBIGUOUS (two different machines, larger kept):')
        for key in plan.ambiguous:
            print(f'    {key}')

    todo = [(member, dest / key) for key, member in sorted(plan.chosen.items())]
    manifest = {
        'source': source.name,
        'chosen': plan.chosen,
        'discarded': plan.discarded,
        'ambiguous': plan.ambiguous,
    }
    return todo, manifest, library


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument('source', type=Path,
                    help='directory of .mp4 files, or a .zip of them')
    ap.add_argument('dest', type=Path)
    ap.add_argument('--key', action='store_true',
                    help='composite a green screen onto white')
    ap.add_argument('--jobs', type=int, default=4)
    ap.add_argument('--limit', type=int, default=0,
                    help='stop after N files (for a dry run)')
    args = ap.parse_args()

    library: ZipLibrary | None = None
    manifest: dict = {}
    if args.source.is_file() and args.source.suffix.lower() == '.zip':
        todo_all, manifest, library = _plan_from_zip(args.source, args.dest)
    elif args.source.is_dir():
        files = sorted(args.source.rglob('*.mp4'))
        todo_all = [(f, args.dest / f.relative_to(args.source)) for f in files]
    else:
        sys.exit(f'not a directory or .zip: {args.source}')

    if not todo_all:
        sys.exit('no .mp4 found')
    if args.limit:
        todo_all = todo_all[:args.limit]

    _, label = build_filter(args.key)
    print(f'{len(todo_all)} clips, {label}, {HEIGHT}p{FPS} crf{CRF}, '
          f'{args.jobs} at a time')

    todo = []
    for src, out in todo_all:
        # Re-runnable: a clip already transcoded is left alone, so an
        # interrupted 2,500-file run resumes instead of starting over. Safe
        # only because a partial encode never reaches this name.
        if out.exists() and out.stat().st_size > 0:
            continue
        # A leftover .partial from a killed run is garbage, not progress.
        out.with_suffix('.partial.mp4').unlink(missing_ok=True)
        todo.append((src, out))
    print(f'{len(todo_all) - len(todo)} already done, {len(todo)} to do')

    scratch = args.dest / '_scratch'
    if library:
        scratch.mkdir(parents=True, exist_ok=True)

    def run_one(src, out: Path) -> tuple[Path, str, int]:
        """Returns (output, error, source bytes)."""
        if library is None:
            return (*transcode(src, out, args.key), src.stat().st_size)
        local = library.extract(src, scratch)
        try:
            size = local.stat().st_size
            dst, err = transcode(local, out, args.key)
            return dst, err, size
        finally:
            # The whole point of streaming from the archive: the copy does not
            # outlive the encode.
            local.unlink(missing_ok=True)

    done = failed = 0
    src_bytes = out_bytes = 0
    try:
        with concurrent.futures.ThreadPoolExecutor(max_workers=args.jobs) as pool:
            futures = {pool.submit(run_one, s, d): (s, d) for s, d in todo}
            for fut in concurrent.futures.as_completed(futures):
                s, d = futures[fut]
                name = s if isinstance(s, str) else s.name
                try:
                    _, err, size = fut.result()
                except Exception as exc:  # noqa: BLE001 - one clip must not end the run
                    failed += 1
                    print(f'  FAILED {name}: {exc}')
                    continue
                if err:
                    failed += 1
                    print(f'  FAILED {name}: {err}')
                    continue
                done += 1
                src_bytes += size
                out_bytes += d.stat().st_size
                if done % 25 == 0:
                    print(f'  {done}/{len(todo)}  '
                          f'{src_bytes / 2**30:.1f} GB -> {out_bytes / 2**30:.2f} GB',
                          flush=True)
    finally:
        if library:
            for leftover in scratch.glob('*.mp4'):
                leftover.unlink(missing_ok=True)
            scratch.rmdir() if not any(scratch.iterdir()) else None

    if manifest:
        # Written after the run so it describes what actually exists. The
        # vendor assigns no stable ids and recommends we assign our own; this
        # file is the only record of which delivered name became which object.
        manifest_path = args.dest / 'import_map.json'
        manifest_path.write_text(json.dumps(manifest, indent=1, sort_keys=True),
                                 encoding='utf-8')
        print(f'wrote {manifest_path}')

    print(f'\ntranscoded {done}, failed {failed}')
    if done:
        print(f'{src_bytes / 2**30:.1f} GB -> {out_bytes / 2**30:.2f} GB '
              f'({src_bytes / max(1, out_bytes):.0f}x smaller)')
        print(f'mean out {out_bytes / done / 2**20:.2f} MB')
    if failed:
        sys.exit(1)


if __name__ == '__main__':
    main()
