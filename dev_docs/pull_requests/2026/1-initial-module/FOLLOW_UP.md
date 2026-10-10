# Follow-up — PR #1

| Finding | Severity | Resolution |
|---|---|---|
| `neutral_filters/2` regex unescaped; `MatchError` for `filter*` config sections | BUG - MEDIUM | Fixed: string regex `^filter\.`, tolerant comprehension; test added |
| `realpath/1` lexical `..` in link targets | BUG - LOW | Fixed: component-wise resolution; test added |
| `Section.update/2` rereads config/README each update | NITPICK | Left; cache by mtime if it shows up |
| `authorized?(nil, _) -> true` | NITPICK | Left; documented behaviour |
