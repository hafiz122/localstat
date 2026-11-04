# Maintaining the offline Help

The manual lives in `Sources/LocalStat/Resources/Help`. Its `contents.json` lists
articles in reading order. Articles use local HTML and the shared stylesheet.
Use `localstat-help:article-id` for article links. No remote resources are needed.
Example files belong in the `Examples` subfolder and are referenced by filename
in the manifest. They must work in a fresh process and a temporary project.

`compatibility.html` is generated from `docs/COMPATIBILITY.md`. The reference
index and inventory are generated from the pinned OpenSAS function checklist,
explicit runtime names, CALL dispatch, and procedure dispatch. Known partial
entries have specific explanations. This inventory is not a claim of complete
SAS compatibility or validation against an installed SAS engine.

After changing those sources, run:

```sh
python3 scripts/generate-help.py
./scripts/test.sh
```

The tests reject stale generated pages, missing internal links, remote assets,
duplicate or missing inventory entries, and em dashes in tracked text files.
They also run both the article code blocks and the Open Example programs in
temporary project directories.
Keep prose original, concise, and aligned with the behavior exercised by tests.
Use no em dashes in source, fixtures, app text, or documentation.
