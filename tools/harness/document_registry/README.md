# Document registry - how a page gets announced

`docs/DOCUMENT_REGISTRY.jsonl` is the source of truth for maintained documents and site pages.
`generate.ps1` renders `docs/DOCS_MAP.md` and `sitemap.xml` from it; `validate.ps1` guards it; both are
invoked by the closure facade whenever a registered document changes. Never hand-edit the two
generated files.

## The model (S1803)

Four sentences, and they are the whole contract:

1. **The page declares its own address.** A `permalink:` line in the page's front matter is what puts
   it in the sitemap. Adding a page to a group that already exists needs no registry edit.
2. **The record decides publication for the group.** `published` and `indexable` are properties of the
   group, not of any one page; a record that is not indexable announces nothing.
3. **A page that must not be announced is named in its record, with a reason.** That is the
   `sitemap_exclude` field: a list of `{path, reason}`. The reason is written for someone re-judging it
   a year later - say what the file is and who it is for. "Internal" is not a reason, and `validate.ps1`
   refuses a reason shorter than four words.
4. **A file without a declared address is not a page.** JSON inputs, generated dumps and notes live
   under the same globs as real pages; they are named in `sitemap_exclude` so the record says out loud
   that they were considered and are not pages, rather than leaving them silently absent.

## What the validator enforces

- Every file under an indexable record is one of three things: it declares a permalink, it is named in
  `sitemap_exclude`, or it is the source of an address the record itself declares (the site root is
  backed by `index.html` / `README.md`). Anything else fails with the file named and the fix spelled
  out - that is the check that stops an internal note from reaching a search engine.
- Every address a record declares by hand resolves to a page that exists. An address answering with an
  error is worse than a page nobody announced.
- Every `sitemap_exclude` entry names a file that exists and carries a reason of at least four words.

## The local registry and generated records

- **A local, ignored corpus has its own registry** (`DOC-INTERNAL-QUALITY` item K). Declare its path in
  `.sza-profile.json` as `paths.localDocumentRegistry` (HARNESS-PROFILE rule 18; empty by default, which means
  none). `validate.ps1` and `query.ps1` read it beside the tracked registry when the file exists and say nothing
  when it does not, because a clone does not carry it; `generate.ps1` never reads it, so no published map or
  sitemap names a file a reader cannot open. A local record is never `published` or `indexable`, an id is
  unique across both registries, and `query.ps1` prints a local record as `local:<id>`.
- **A generated record names its generator and its drift check** (`DOC-INTERNAL-QUALITY` item W) in two fields,
  `generator` and `check`, each a command line; a `check` of `none` (optionally `none` and a reason) says no
  drift check exists yet and is printed as an advisory. A field that is present is always judged: a non-empty
  string whose first script exists, both or neither on a generated record, and no `generator` on a source
  record (a source may carry the `check` that validates it). A generated record with neither field is an
  advisory, and an error under `validate.ps1 -Strict`.

## Adding a page

Drop it under an existing group's globs with a `permalink:` and you are done - the sitemap picks it up
on the next `generate.ps1`. If it should not be announced, add it to that record's `sitemap_exclude`
with a reason. If it belongs to no existing group, add a record.
