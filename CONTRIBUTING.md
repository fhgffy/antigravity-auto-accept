# Contributing

Maintained by **fhgffy**, with **Codex** assisting the current repair and verification work. AI-assisted patches receive the same review and test requirements as other contributions. Git history retains its original authors.

## Development

Use Windows 10/11, Node.js 22 or newer, npm, and Windows PowerShell 5.1.

```powershell
npm ci
npm test
npm run package
```

The tests cover lifecycle races, button matching, scanner ownership and click boundaries without running arbitrary commands or clicking other applications. Type checking does not replace an IDE integration test.

For a real IDE test, install the generated VSIX with the Antigravity IDE CLI, reload the test window, and use an empty temporary workspace. First disable the scanner and record a pending harmless command approval; enable it and compare the scanner log and command result. Do not test against a directory containing private or important files.

## Pull requests

- Explain the trigger, old behavior, expected result, and IDE version.
- Preserve the TypeScript/PowerShell structure and UTF-8 encoding. Existing files use CRLF.
- New code comments should be Chinese and include the change date; user-facing strings and logs are English.
- Add a regression case for behavior changes. Run `npm test` and inspect the VSIX contents.
- Include sanitized logs for a real approval test, and distinguish mock tests from IDE tests.
- Never commit tokens, credentials, IDE databases, user settings, local app logs, or test workspace contents.

For issues, include Windows/IDE/extension versions, local or remote mode, the exact approval label, minimized/covered-window state, and sanitized extension output. Do not attach private source code or command secrets.
