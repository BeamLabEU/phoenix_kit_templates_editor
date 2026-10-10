# Follow-up — PR #1

| Finding | Severity | Resolution |
|---|---|---|
| `neutral_filters/2` regex unescaped; `MatchError` for `filter*` config sections | BUG - MEDIUM | Fixed: string regex `^filter\.`, tolerant comprehension; test added |
| `realpath/1` lexical `..` in link targets | BUG - LOW | Fixed: component-wise resolution; test added |
| `Section.update/2` rereads config/README each update | NITPICK | Left; cache by mtime if it shows up |
| `authorized?(nil, _) -> true` | NITPICK | Left; documented behaviour |

## Codex follow-up

Details and validation: [CODEX_REVIEW.md](CODEX_REVIEW.md).

| Finding | Severity | Resolution |
|---|---|---|
| Sources view reads/caches unchecked email and chrome files | BUG - HIGH | Check the email and lazily resolved chrome before core's lookups; linked-file/cache regressions added |
| Module test send checks the host's layout instead of the entry's explicit group | BUG - HIGH | Prefer the module's explicit layout; regression verifies no send callback for unsafe chrome |
| Oversized files reach renderer reads before size checks | BUG - MEDIUM | Check visible regular-file sizes in `Files.check_template/2`; verify preview does not cache refused files |
| `realpath/1` still normalizes input `..`, permits file traversal and misses a terminal link-limit case | BUG - MEDIUM | Preserve input components, require intermediate directories, check the limit before success; boundary regressions added |
| Override creation ignores `max_root_bytes` | BUG - MEDIUM | Check the complete built-in/database/layout plan before writing; exact-limit and LiveView regressions added |
| Saves add replacement bytes to usage already containing the old bytes | BUG - MEDIUM | Count each part's positive growth; smaller replacements work at capacity |
| Choosing a layout writes `layout.txt` without checking capacity | BUG - MEDIUM | Check positive growth before writing; creation-at-capacity and smaller-replacement regressions added |
| Override freshness uses an existence check that overlooks dangling links | IMPROVEMENT - MEDIUM | Check the destination directory explicitly before planning and writing; dangling-link regression added |
