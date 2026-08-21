# App diagnostic logging patterns

Use this reference only when the task requires changing application code to improve diagnostics.

## Design contract

Every diagnostic event should contain:

```text
timestamp, runId, level, event, screen/activity, thread, message, safe fields
```

Use a rolling UTF-8 file under the app's app-specific external files directory. Export a copy to `Download/<package>-diagnostics/<runId>/` only when requested. Keep file writes asynchronous, bounded, and resilient to low storage. Send severe events to Logcat too.

Recommended event names include:

```text
app_start, activity_resume, screen_enter, screen_exit,
user_action, request_start, request_success, request_failure,
state_transition, background_job, permission_result, uncaught_exception
```

Never record secrets or full request/response bodies. Hash or redact identifiers when they are not needed for diagnosis.

## Kotlin/Java Android

Inspect the existing logging abstraction first. Extend it instead of creating a second competing logger. A minimal implementation should provide:

```text
diagnostic.info(event, fields)
diagnostic.warn(event, fields)
diagnostic.error(event, throwable, fields)
diagnostic.startRun(runId)
diagnostic.exportRun(runId)
```

Use `context.getExternalFilesDir("diagnostics")` for routine files. Add an uncaught-exception handler only if it preserves the existing handler and delegates after writing a bounded crash record. For Compose, log screen-entry and user-intent boundaries rather than every recomposition.

## Flutter

Inspect the existing logging package and isolate file I/O from widget code. Log route transitions, bloc/cubit state transitions, platform-channel failures, isolate errors, and uncaught Flutter errors. Keep the logger injectable so tests can use a temporary sink.

## Verification checklist

1. Build the debug/test variant.
2. Start a new run-id.
3. Execute the smallest reproducer.
4. Confirm Logcat contains the same event IDs as the file.
5. Pull the diagnostic directory and inspect ordering, timestamps, redaction, and crash details.
6. Confirm normal behavior and UI responsiveness are unchanged.
