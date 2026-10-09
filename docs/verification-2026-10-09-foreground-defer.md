# 5.3.6 foreground deferral verification — 2026-10-09

Evidence levels: source review, executed regression tests, and a controlled native Windows Computer Use run. This record covers the new narrow browser-menu deferral. It does not certify every background approval or complete multi-window acceptance.

## Change and regression evidence

The narrow `More actions` path waits for the exact IDE window to be foreground with no held mouse/keyboard key and at least 500 ms of input inactivity. It rechecks immediately before scrolling, expanding, and submitting. Wide `Allow Once` and existing ordinary approval routes retain their background action path.

A menu opened just before a final deferral can resume only with its recorded process, window, card, text, trigger, menu, and item identities. Changed identities and unrelated old unlabelled menus are rejected. Text uses ordinal equality; an independent regression showed that PowerShell culture comparison could ignore an inserted soft hyphen.

Three independently reproduced regressions were closed: an opened unlabelled menu that could not resume, held ordinary keys missed by the original key subset, and Unicode text changes accepted by culture comparison. Tests execute production function bodies with controlled dependency boundaries.

- `npm test`: exit 0; compile/typecheck, repository 3, publication 26, self-test 95, lifecycle 28, scanner 167, host 131 per engine, mouse 97 per engine, concurrency 22.
- Independent final review: no unresolved P1/P2. Windows PowerShell 5.1 x86/x64 and PowerShell 7 x64 scanner 166 each (single self-test engine); identical C# mouse 97 each. Additional continuation, pruning, held-key, and Unicode cases passed.
- UTF-8 without BOM and CRLF retained; `git diff --check` passed.
- Official VSCE package and archive byte validation passed, version 5.3.6, 8 entries.

## Native Computer Use run

The official IDE CLI installed the frozen VSIX; installed scanner and JavaScript hashes matched. A normal status-bar Start launched scanner PID 39624 under extension host 14816. The existing narrow TypeScript browser approval remained pending while a separate test Notepad document was foreground.

- Notepad baseline: 47 characters. Three actual Chinese/ASCII typing bursts produced exactly the expected 104 characters. No manual permission button was clicked.
- The scanner emitted 10 fixed deferral diagnostics while Notepad was foreground.
- The background interval was 104.232 seconds. Its 501 covered foreground samples all showed the same Notepad HWND/PID with stable reads. The final 3.941 seconds were outside the observer deadline and are explicitly excluded from the sampled focus result.
- A 24.380-second hands-off interval contained 102 covered, stable Notepad samples; its tail was likewise outside capture.
- Returning normally to the IDE triggered one `Allow Once (browser domain permission)` success at 17:21:16 local time. The approval card disappeared and the agent opened/read the TypeScript Handbook page. The return and approval occurred after the observer ended, so their focus behavior is not certified by that observer.
- Normal Stop was recorded; the owned scanner PID and extension-host PowerShell children were absent afterward, and refreshed UI showed OFF.
- Before/after HEAD, status, and all 8 dirty-file hashes across the three existing user repositories matched exactly.

The first immediate Notepad accessibility snapshot lagged the visible text; a fresh read confirmed the exact text without retrying input. Start/Stop accessibility snapshots also lagged once; logs, process identity, screenshots, and fresh reads resolved the state.

## Frozen artifacts

- Scanner SHA256: `71035C3F3C07717BA5B7EC6174D4A323014D985046149C73D1C47750D569FFBF`.
- JavaScript SHA256: `2F85FBE50F0DF4EF35CC7C688602EA2B5D822951777B0159040057AE392EA1AD`.
- Tested VSIX SHA256: `6BDC10340721BF9AEC5BFA4A7E16EBFE2BB7E1F533FF6DB95287AFD4846FDE4A`.
- Independent review SHA256: `72C7F04F06212248123D7E0F3E0098CCFB5296143E2F959C2E58CC3BF2AB4633`.

Local native raw logs, actual UI event times, process snapshots, observer JSONL, repository hashes, and aggregate are archived under the owned `AntigravityAA-native-foreground-defer-536-9916fd48681e4ef7bd2bb586ef79b5a8/ordinal-final` temporary directory. Red/green test and package logs are in `AntigravityAA-foreground-defer-536-1bec8d2157ff4e1bb30b874b6de356a1`.

## Remaining limits

This run contains three short input bursts, not minutes of sustained typing. The observer sampled the main IDE process, not scanner memory or resource ownership. External UIA calls and foreground queries cannot be made atomic, so this is not an absolute focus-race guarantee. Real browser distractions, multiple IDE windows, scanner takeover, the new commit's CI, merge, GitHub release, and both stores still require separate current verification.
