# PR #2 review

Reviewed `be4a11a`, which moves the templates editor to Settings and introduces Leaf for letter bodies.

- **BUG - HIGH.** Save and document switches used the most recent change Leaf had reported. Its browser hook debounces keystrokes and schedules its blur handler asynchronously. Both actions could run while the final edit was still in the browser, and opening the next document would invalidate the late notification.
- **BUG - MEDIUM.** Generating plain text for a letter with multiple blank-line sections ran the converter separately for each section. The standard converter had a deadline per invocation, and a custom converter could block the LiveView directly. There was no deadline for the whole conversion.
- **BUG - MEDIUM.** Copying a layout passed zero additional bytes to the root quota check, even when the new header and footer contained files. A copy could exceed the configured storage limit.
- **IMPROVEMENT - HIGH.** The new feature expanded the editor while its four panels and disk actions still lived in the LiveComponent. The repository requires splitting these responsibilities when adding an editor feature.
- **IMPROVEMENT - MEDIUM.** The catalogue test required two passkey notifications introduced in PhoenixKit 3.6. This made the suite fail on the declared 3.5 floor.
- **IMPROVEMENT - MEDIUM.** Rendering both language switchers asked core for the enabled language catalogue twice on every editor render. Typing in Leaf could trigger these settings lookups.
- **BUG - MEDIUM.** The browser hook restored a folding section only the first time it saw its ID. A later DOM patch could reset a reader's choice, and a new selection in a previously closed section could stay hidden.
