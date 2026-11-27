# Knowledge pack

Short Markdown documents the assistant searches before answering.

- `manifest.json`: `{"version": 1, "minFerry": "1.3.0", "files": ["how-it-works/wine.md", ...]}`. `files` are paths relative to this folder; a document's id is its path without `.md`.
- Each document starts with a front-matter block, then the text:

```
---
title: Objects blink or vanish on DirectX 11 games
tags: dx11, shards
---
Body text, a few short paragraphs.
```

- Search scores title hits x3, tag hits x2, body hits x1.
- Settings and Troubleshoot entries are generated from `SettingsCatalog` and `Symptom.guide`, not written here.
