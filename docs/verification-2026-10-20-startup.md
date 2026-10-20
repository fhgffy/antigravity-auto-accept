# Startup recovery verification — 2026-10-20

Version: 5.3.9. Native host: Windows, Antigravity IDE 2.5.5.

## Trigger and result

A scanner process can remain alive without sending READY or WAITING. Previously the extension stayed at STARTING indefinitely. Startup now has a 60-second deadline, followed by the existing cancellable restart path. A normal WAITING owner handoff has no startup deadline once acknowledged.

This changes scanner startup recovery only. Approval matching, foreground/input protection, workspace trust and native IDE permissions are unchanged.

## Regression evidence

- The new timeout regression failed against the previous implementation: advancing the virtual clock past one minute left the first child unmodified (`killCalls` was 0 rather than 1).
- 33 lifecycle tests passed. They execute the production TypeScript entry with controlled IDE/process dependencies and a deterministic timer queue.
- The deadline tests cover partial handshake lines, READY, both WAITING protocols, stop/unload cancellation, replacement deadlines, stale callbacks and cancellation of the scheduled recovery.
- Notifications remain silent during automatic recovery even with notifications enabled. Ordinary output immediately before the deadline does not extend it.
- The complete local `npm test` command passed, including both PowerShell engines, host-wrapper failure diagnostics, physical-input boundaries and concurrent handoff tests. The final lifecycle and repository checks were repeated after review and the version update.
- Compilation, type checking, strict UTF-8 without BOM, CRLF preservation, `git diff --check` and VSIX runtime-byte validation passed.

## Native IDE evidence

The IDE used a separate user-data directory and extension directory. The extension entry came from the packaged candidate. A wrapper in this test installation held only the first owned PowerShell child for 90 seconds; replacement children loaded an unchanged copy of the packaged production scanner. The release VSIX contains no wrapper or injection gate.

Sanitized extension output, local time:

```text
[11:34:15] Starting UIAutomation scanner: [isolated test install]
[11:34:15] ___TEST_STARTUP_HOLD___
[11:35:15] Scanner startup timed out after 60s; restarting.
[11:35:15] Restarting scanner (startup timeout)...
[11:35:15] Stopping scanner...
[11:35:15] Starting UIAutomation scanner: [isolated test install]
[11:35:16] UIAutomation scanner ready
[11:36:44] Auto-accepted (Invoke): "Submit (one-time permission)"
```

The first child PID was gone after recovery. A subsequent real `run_command` request printed `AAA-STARTUP-539-20261020` and exited 0; the extension recorded exactly one approval. There was no manual approval or settings change during recovery. Test IDE, controller and helper processes exited, and the isolated configuration directories were removed.

The release scanner, extracted scanner and unchanged test scanner copy shared SHA-256 `b4221d2e71fe3a82e64c11b9066ee379d87839f96ffdb37c77c20dfa97d69782`. The packaged extension entry tested in the IDE had SHA-256 `d40e0730152830471c08227e379f9ee425c5f0358b6abd7f1a18d11639bce73e`.

## Boundaries

This was an intentional startup fault in a separate test installation, not an observed failure of a user's IDE. An initial status-item read by a separate UIA reader returned no element; native recovery is supported by the process snapshot, extension timeline and final command-result screenshot rather than that unavailable text read. This run does not revalidate every approval layout or provide ongoing health checks after a READY/WAITING handshake. Public store availability must be verified separately after release.
