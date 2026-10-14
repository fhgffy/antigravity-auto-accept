# Experimental Linux backend, 2026-10-14

Linux currently provides read-only capability diagnostics. Automatic approval is not implemented, enabled, or verified. The Windows PowerShell UIAutomation backend is unchanged. The extension routes explicit Linux Start/Restart commands to a one-shot diagnostic; activation never auto-starts it. The status reads DIAGNOSTIC while inspecting and returns OFF afterward, with no automatic retries.

## Architecture and boundaries

- `src/platformBackend.ts` selects the existing Windows backend, the experimental Linux diagnostic, or an unsupported result. It requires workspace trust and a recognized executable name. Linux process identity is checked again by the probe.
- `src/linux/atspi_probe.py` uses system Python 3, PyGObject and the AT-SPI 2 introspection typelib. Missing dependencies, desktop bus, host identity or accessibility tree produce an explicit unavailable result. The script never installs dependencies.
- The extension-host PID, its main-process ancestor, same-user ownership, canonical executable paths and process start times bind inspection to one application. Accessible objects must belong to that application's unique D-Bus owner and PID.
- The bus preflight uses `NO_AUTO_START` and requires an already running, enabled accessibility service. The subsequent standard libatspi connection is allowed only after that check. No settings are changed.
- Inspection is bounded by time, tree depth and node count. Stop signals and host exit cancel the scan. The extension retains child ownership and displays STOPPING until close; after a one-second SIGTERM grace period it sends SIGKILL only to that diagnostic child. Restart waits for close, and Stop or deactivation cancels a queued restart. Deactivation sends SIGKILL to the owned diagnostic child immediately, because the extension host may exit before a grace timer can run. Output includes only counts, allowlisted role categories and fixed approval labels; it omits window titles, commands, domains and conversation text.
- There is no production action invocation method, pointer input, keyboard injection, CDP connection, remote-debugging flag, security override, or option to enable approvals.
- X11 and Wayland are both potential AT-SPI environments, but neither is claimed to work without an exposed, verifiable application tree. No X11 coordinate fallback is used.

## Diagnostic use

Run through the extension's local UI host, using that process's desktop session and verified identity:

```sh
/usr/bin/python3 -I -B src/linux/atspi_probe.py --probe --parent-pid EXTENSION_HOST_PID --host-executable /absolute/path/to/antigravity-ide
```

`--dry-run` has the same read-only behavior. Successful inspection exits 0 with `status: diagnostic-only` and `actionsEnabled: false`. Unavailable capabilities exit 2. This is a one-shot diagnostic, not an approval scanner, and must not be restarted indefinitely or displayed as AutoAccept ON.

On Debian/Ubuntu, the typical separately managed prerequisites are system Python, `python3-gi` and `gir1.2-atspi-2.0`. Package names vary across distributions. The probe neither installs them nor enables desktop accessibility. It does not modify `org.a11y.Status`, GSettings, IDE security settings or launch flags.

## Evidence and remaining work

On 2026-10-14, isolated Antigravity IDE 2.5.5 reached Google sign-in on the cloud X11 desktop. A read-only CUA observation exposed only its X11 window, with no AT-SPI controls; the terminal did expose AT-SPI. No sign-in, approval, accessibility change or security override was performed as part of this diagnostic. This establishes a current tree-exposure blocker, not an unsupported claim about every Linux installation.

The code-execution shell is a distinct process environment: its Python has PyGObject but no AT-SPI typelib, and it does not inherit the desktop session bus. Running the standalone probe there correctly reported `missing-atspi`. It is not evidence of the dependencies inside the graphical session.

The browser-card JSON fixture is synthetic and derived from existing Windows card semantics. It does not prove Linux uses the same roles, hierarchy, labels or IDs. The fixture classifier is diagnostic-only and not connected to the live adapter. Terminal radio forms, narrow menus, generic Run/Accept buttons and translated variants remain unimplemented.

Before implementing any Linux action path:

1. Observe the real IDE 2.5.5 approval tree in an explicitly authorized disposable task. Verify process ownership, card/target identity, supported labels, selection state and semantic actions.
2. Revalidate immediately before acting and reject changed, detached, ambiguous, denied, cancelled, disabled or stale targets. Never choose persistent permission options.
3. Test cancellation, host/PID reuse, duplicated controls, target mutation, hidden controls, uncertain action outcomes, scanner ownership and repeated polls without live clicks.
4. Run separate X11 and Wayland integration checks; report exactly which combinations and approval types were tested. Preserve the Windows validation matrix.

## Local non-GUI tests

```sh
node --test tests/platform-backend.test.cjs
python3 -B tests/linux-backend.test.py
npm run typecheck
```

The production adapter is exercised using fake AT-SPI objects whose action method raises if called. No tests connect to the desktop.

## Primary references

- [GNOME AT-SPI API](https://gnome.pages.gitlab.gnome.org/at-spi2-core/libatspi/)
- [Accessible process identity](https://gnome.pages.gitlab.gnome.org/at-spi2-core/libatspi/method.Accessible.get_process_id.html)
- [AT-SPI bus lifecycle](https://github.com/GNOME/at-spi2-core/blob/main/bus/README.md)
- [AT-SPI Action interface](https://github.com/GNOME/at-spi2-core/blob/main/xml/Action.xml)
- [Electron accessibility API platform limits](https://www.electronjs.org/docs/latest/api/app#appsetaccessibilitysupportenabledenabled-macos-windows)

Electron currently documents its manual accessibility-toggle API for macOS and Windows. The extension must not assume that it can enable Linux accessibility through that API.
