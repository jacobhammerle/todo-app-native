Test the Tasks tab. One round trip only:

1. The app launches on the Tasks tab. Note the summary card's starting
   values: "N tasks to do", "X of Y tasks done", and the percent
   (round(X/Y*100)).
2. Complete ONE task under "To do": tap anywhere on its row. Verify the
   task leaves the "To do" list, the done count increases by one, and
   the percent updates to match.
3. Open the Done tab. Verify the task is listed under "Completed". Tap
   its row to uncheck it. Open the Tasks tab again and verify the summary
   card is back to the starting values and the task is back under
   "To do".

Out of scope for this lane — do NOT touch these:

- The "Add a task" field and the "Add task" row.
- The "Complete all" row at the end of "To do". Do not tap it.
- The "Clear history" row. Do not tap it, and do not report on it.
- The Admin tab.

Pass condition: the summary card tracks both toggles correctly and ends
at the starting values.
