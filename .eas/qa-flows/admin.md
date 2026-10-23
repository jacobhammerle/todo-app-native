Test the Admin tab. One preset load:

1. The app launches on the Tasks tab. Open the Admin tab. Verify the
   "This installation" and "Build provenance" sections are on screen and
   note the "Built by" value (expected: "EAS Build").
2. Swipe up to reach "Demo data". Verify the "Default" row reads
   "Loaded". Tap the "Fresh start" row. An alert titled
   "Load "Fresh start"?" opens with Cancel and Load; confirm it by
   tapping Load. Verify "Fresh start" now reads "Loaded".
3. Open the Tasks tab. Verify the summary card reads "3 tasks to do",
   "0 of 3 tasks done", and 0%, and that no "Recently done" section is
   shown.

Out of scope for this lane — do NOT touch these:

- The task rows and the "Add a task" field.
- The Done tab.
- The "Reset demo data" row.

Pass condition: Admin shows the build provenance, loading "Fresh start"
marks it Loaded, and the Tasks tab shows three open tasks and nothing
done.
