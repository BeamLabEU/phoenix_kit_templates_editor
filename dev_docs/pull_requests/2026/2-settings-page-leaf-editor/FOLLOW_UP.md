# PR #2 follow-up

- A focused Leaf now receives a flush request before Save or a document switch. The editor waits for the matching document and request reference, then runs the original action with its authorization and unsaved-change checks. LiveView tests exercise a final edit arriving during the flush, a stale acknowledgement and a language switch.
- The full Markdown-to-text conversion runs in a single bounded task. A regression test checks that separate sections run in the same worker outside the LiveView.
- The layout-copy check sums the source directories before creating any destination. A regression test fills the root to its limit and verifies the copy leaves no new parts.
- The layouts, module emails, variables and preview now have function-component modules. Save operations, conflict detection and layout actions have separate modules. The remaining visible list buttons use the core button component.
- The catalogue test expects passkey notices starting with PhoenixKit 3.6 and still checks that both names are protected on every supported version.
- Parent updates resolve the language catalogue once for both switchers. Leaf updates reuse those entries and add the translated Default option when the selected template has a fallback.
- The folding-list hook preserves the open state across DOM patches and opens a section when its selected row changes. Invalid local-storage data falls back to the displayed defaults. A Node hook check exercised all three cases.

The full PostgreSQL suite passed with the locked PhoenixKit 3.6.1 and Leaf 0.12.0, and again with PhoenixKit 3.5.0 and Leaf 0.11.1. Each run completed 864 tests with zero failures.
