# Hosted108 investigation

Run40508823942 on7fbeab55f5dd875b997cc1b85d020563068a32c8 is terminal.
Map passes41 UI cases. Field fails native large-GPX reopening and Project
segment activation; library fails largest-night active-course control reveal.
Dedicated background steps after the failed field UI step were skipped.
Hosted107 remains the preceding fully green run on02d67f6, not proof of this
later source or the local follow-ups.

Verified artifact SHA-256 values before extraction:
- Field12738979054:
  `85e7f1b8f6eb2d4dc935b640b92af532e12df85cd3450ff24445ea7a1f207d8a`.
- Map12739993035:
  `f578149d8661e102e39a025716fe1576c00e8c6e46fe201d27858af14dd818e2`.
- Library12741821932:
  `223f2171415772643a8d7120f87a1869ddfdda03c55f532ead7768d1145d0060`.

Archives and extracted trees are `/tmp/mgrsgps-ci108-{field,map,library}`.
The library archive exceeds the connector512MiB limit; authenticated GitHub
CLI download was used. Native recordings, activities and trees were inspected.

The field failures both pass locally with unchanged test helpers in
`/tmp/mgrsgps-ci108-local-before.xcresult`. The same run passes existing
Settings persistence obstruction/retry. This is runtime-specific evidence,
not a resolution of the hosted failures.

Candidates under validation:
- Projection uses the existing bounded segment-selection acknowledgment on
  both Project and Coordinate. The hosted failure tree explicitly retained
  Coordinate selected after the original tap. Both projection workflows pass
  in `/tmp/mgrsgps-ci108-projection-final.xcresult`; night invalid-distance
  capture inspected. Exact coordinate, disabled Save and relaunch checks stay.
- Native Files prefers the exact filename text leaf within the chosen row and
  uses its visible frame; a provider with combined row accessibility retains
  the cell fallback. The old failure recording retained the document while
  taps targeted the area above the visible filename. No file is injected or
  substituted, and all native picker/save/reopen/count checks stay.
- The course test drags by the missing viewport distance, bounded to60% of the
  viewport with a slow release. Its old full-screen swipes oscillated around
  the tall rows: the failure tree leaves End course at750.7...844pt against
  an809pt test limit. Fully-visible assertions remain in force. This is a
  reveal repair, not removal of the large-text reachability requirement.

The first combined Files/course run exposed a flaw in the candidate reveal:
starting the drag near the viewport bottom hit Navigate's floating tab controls.
It failed the largest-night active case before opening the course sheet. The
corrected candidate constrains both endpoints around the content viewport centre,
with its top at least the scrolling surface's actual top. The first bundle is
retained. The centred candidate passes all scrolling/split/relaunch/End steps,
but its largest-night final assertion expected Start course to exist before
scrolling the new form. The native tree/video show Create course with Start
below the virtualized viewport. Final validation explicitly acknowledges Create
course, scrolls Start into full view and requires it to be tappable. Both active
cases pass in `/tmp/mgrsgps-ci108-course-render-final.xcresult`. The earlier
centred bundle remains failed at the offscreen Start assertion.

Screenshot review of the green hosted map also flagged low contrast on a tactical
route label over the night viewshed. Android uses the same dim-red affiliation
color in ControlMeasuresOverlay.kt; copying that palette alone does not close
this readability follow-up. No physical-device, independent-watch or real
enrolled-TAK gate is closed here.

Final local evidence:
- `/tmp/mgrsgps-ci108-file-course-final.xcresult`: all nine Files/export cases
  pass (ordinary/protected backups, complete large GPX, cancellation/retry,
  selected-track exports, protected GPX/KML and queued incoming confirmations).
  This bundle remains failed overall at the first course reveal candidate.
- `/tmp/mgrsgps-ci108-course-centred-final.xcresult`: both saved10,000-split
  log cases and ordinary active course pass; largest-night fails only the
  original non-scrolling Start assertion after successfully ending the course.
- `/tmp/mgrsgps-ci108-course-render-final.xcresult`: both final active-course
  cases, terrain LOS/profile/viewshed UI, and five tactical rendering cases pass.
  Final largest-night Start, night viewshed and30-type contact sheet inspected.
- All parent processes ended naturally. The owned iPhone simulator and fake
  location feed are stopped. Final unsigned phone/watch/widget Release succeeds
  in `/tmp/mgrsgps-night-label-release.log`. Ten Python harness checks pass.

These repairs still need the next full hosted run; local success cannot prove
reliability on the hosted26.5 runtime. No test counts, coordinate assertions,
password failures, destructive confirmations or saved-data checks were removed.
