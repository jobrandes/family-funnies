# Family setup and management

The Create family action opens a native modal dialog with focus containment,
Back/Next navigation and four steps: name, people/pets, photos, optional
personality/boundaries. Phones use the full screen. Close keeps completed steps;
unsaved form edits are only saved by the form's save/next/finish action. The
bookshelf and family view show Continue setup while setup remains incomplete.

Each new member needs a photo. Profiles and photos already accessible to the
signed-in manager can be explicitly copied into the new family. Copies have
separate records and storage paths; future edits are independent. Memorial
members remain available with explicit remembrance settings. Existing photo
upload and Google Photos controls are reused.

Finish saves setup and explains the real 7 a.m. Pacific cast-check cadence.
It does not pretend artwork is currently generating. Managers review the cast
in the existing Cast section, then explicitly enable daily 8 a.m. production.
It does not silently enable production or promise immediate first-comic creation.

Managers can move a family to Trash with a typed-name confirmation in Settings.
Trashed families disappear for all members, production pauses, and in-flight jobs
are invalidated. Only managers can list/restore their own Trash. Restoration
preserves the archive and setup checkpoints but leaves production paused.
No automatic purge is scheduled. Trash is recoverable; it is not a data-erasure
promise. Cast members can be removed by managers with typed-name confirmation;
their profile/reference records are removed and stored reference cleanup is
attempted. Past comics remain. A storage cleanup failure is surfaced to the user.

Deleting one redundant reference photo keeps a current approved cast active if
another reference remains. Removing the last reference or a member still creates
a new visual revision and pauses production for review. Status labels distinguish
refresh queued, draft ready, approved, and daily comics off. The Cast view polls
status every fifteen seconds while visible.

Validation: build and eleven Node tests pass; transaction-rolled-back database
tests cover checkpoints, missing-reference gates, owner-only Trash/restore and
member removal, outsider isolation and preserving approved art after extra-photo
removal. New functions use private guarded implementations and invoker wrappers.
No new security-advisor warning findings. Existing owner-private Site is untouched.
