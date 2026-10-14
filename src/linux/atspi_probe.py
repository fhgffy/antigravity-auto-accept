"""Read-only Linux AT-SPI capability probe. No approval actions are implemented."""

import argparse
from collections import Counter
from dataclasses import dataclass
import json
import os
from pathlib import Path
import signal
import sys
import time


# 2026-10-14：本后端只读诊断，任何命令行开关都不能启用真实审批动作。
ACTIONS_ENABLED = False
MAX_NODES = 2000
MAX_DEPTH = 32
MAX_SECONDS = 8
HOST_NAMES = {"antigravity", "antigravity-ide"}
# 2026-10-14：提供者可能为扩展角色返回私有文本，诊断仅输出固定类别。
ROLE_CATEGORIES = {
    "application", "frame", "panel", "section", "document web", "text", "label",
    "push button", "radio button", "entry", "menu", "menu item", "scroll pane",
    "list", "list item", "page tab", "page tab list", "tool bar", "dialog",
}
FIXED_LABELS = {
    "Allow Once", "More actions", "Configure", "Deny", "Always Allow",
    "Edit permission target", "Submit", "Submit ↵", "Submit ⏎", "提交",
    "1 Yes, allow this time", "Yes, allow this time",
    "1 是，仅本次允许", "是，仅本次允许", "1 是，允许本次", "是，允许本次",
}
ONCE_LABELS = FIXED_LABELS.intersection({
    "1 Yes, allow this time", "Yes, allow this time", "1 是，仅本次允许",
    "是，仅本次允许", "1 是，允许本次", "是，允许本次",
})


class ProbeUnavailable(Exception):
    def __init__(self, code, message):
        super().__init__(message)
        self.code = code


@dataclass(frozen=True)
class ProcessIdentity:
    pid: int
    ppid: int
    uid: int
    executable: str
    start_time: str


@dataclass(frozen=True)
class HostBinding:
    parent: ProcessIdentity
    main: ProcessIdentity


def read_process(pid):
    # 2026-10-14：PID 必须连同启动时间和真实路径核验，拒绝退出或复用后的进程。
    try:
        root = Path("/proc") / str(pid)
        raw = (root / "stat").read_text(encoding="utf-8")
        fields = raw[raw.rfind(")") + 2:].split()
        executable = os.readlink(root / "exe")
        if executable.endswith(" (deleted)"):
            raise ValueError("deleted executable")
        return ProcessIdentity(pid, int(fields[1]), root.stat().st_uid,
                               os.path.realpath(executable), fields[19])
    except (OSError, ValueError, IndexError):
        raise ProbeUnavailable("host-unavailable", "The Antigravity process identity could not be verified.") from None


def bind_host(parent_pid, expected_path, reader=read_process, uid=None):
    if not isinstance(parent_pid, int) or parent_pid <= 0 or not os.path.isabs(expected_path):
        raise ProbeUnavailable("missing-host-identity", "Pass the local extension-host PID and executable path.")
    expected = os.path.realpath(expected_path)
    if os.path.basename(expected) not in HOST_NAMES:
        raise ProbeUnavailable("unsupported-host", "The executable is not a recognized Antigravity IDE Linux host.")
    parent = reader(parent_pid)
    user = os.getuid() if uid is None else uid
    if parent.executable != expected or parent.uid != user:
        raise ProbeUnavailable("host-mismatch", "The extension host does not match this user's Antigravity executable.")
    main = parent
    visited = {parent.pid}
    for _ in range(64):
        if main.ppid <= 1:
            break
        if main.ppid in visited:
            raise ProbeUnavailable("invalid-ancestry", "The host process ancestry could not be verified.")
        ancestor = reader(main.ppid)
        if ancestor.executable != expected or ancestor.uid != user:
            break
        visited.add(ancestor.pid)
        main = ancestor
    else:
        raise ProbeUnavailable("invalid-ancestry", "The host process ancestry exceeded the safety limit.")
    return HostBinding(parent, main)


def verify_binding(binding, reader=read_process):
    return reader(binding.parent.pid) == binding.parent and reader(binding.main.pid) == binding.main


def classify_snapshot(nodes):
    """Recognize conservative fixture shapes for diagnostics, never for execution."""
    # 2026-10-14：同一总线对象、窗口、conversation 与卡片的完整身份均不可缺失。
    ids = [node.get("id") for node in nodes]
    if any(not isinstance(key, str) or not key for key in ids) or len(set(ids)) != len(ids):
        return []
    by_id = {node["id"]: node for node in nodes}
    result = []
    for card in nodes:
        if card.get("kind") != "card" or card.get("outcome") not in (None, "pending"):
            continue
        ancestor = by_id.get(card.get("parent"))
        if not ancestor or ancestor.get("accessibleId") != "conversation":
            continue
        frame = by_id.get(ancestor.get("parent"))
        if not frame or frame.get("role") != "frame":
            continue
        identity = (card.get("bus"), card.get("pid"))
        if not identity[0] or not isinstance(identity[1], int) or identity[1] <= 0:
            continue
        children = [node for node in nodes if node.get("parent") == card["id"]]
        if any((node.get("bus"), node.get("pid")) != identity for node in [ancestor, frame] + children):
            continue
        buttons = [node for node in children if node.get("role") == "push button"]
        labels = Counter(node.get("name") for node in buttons)
        targets = [node for node in children if node.get("kind") == "browser-target"]
        once = [node for node in buttons if node.get("name") == "Allow Once"]
        if len(targets) == 1 and targets[0].get("target") and all(labels[label] == 1 for label in
                ("Configure", "Deny", "Always Allow", "Allow Once")) and len(once) == 1:
            action = once[0]
            states = set(action.get("states", []))
            if {"enabled", "sensitive", "showing", "visible"} <= states and not states.intersection({"defunct", "busy"}):
                if action.get("actions") == ["click"]:
                    result.append({"kind": "browser-once-shape", "card": card["id"], "action": action["id"]})
    return result


def load_gi():
    try:
        import gi
    except ImportError:
        raise ProbeUnavailable("missing-pygobject", "Linux diagnostics require system Python 3 with PyGObject (gi); nothing was installed.") from None
    try:
        gi.require_version("Atspi", "2.0")
        from gi.repository import Atspi, Gio, GLib
        return Atspi, Gio, GLib
    except (ImportError, ValueError):
        raise ProbeUnavailable("missing-atspi", "Linux diagnostics require the AT-SPI 2 GObject typelib (for example gir1.2-atspi-2.0 on Debian/Ubuntu); nothing was installed.") from None


def check_existing_bus(Gio, GLib, environ):
    # 2026-10-14：预检查不激活服务，不改变辅助功能开关或写入桌面设置。
    if not environ.get("DBUS_SESSION_BUS_ADDRESS"):
        raise ProbeUnavailable("missing-session-bus", "No local desktop D-Bus session was inherited by the extension host.")
    try:
        bus = Gio.bus_get_sync(Gio.BusType.SESSION, None)
        flags = Gio.DBusCallFlags.NO_AUTO_START
        owner = bus.call_sync("org.freedesktop.DBus", "/org/freedesktop/DBus",
                              "org.freedesktop.DBus", "NameHasOwner",
                              GLib.Variant("(s)", ("org.a11y.Bus",)),
                              GLib.VariantType.new("(b)"), flags, 1000, None).unpack()[0]
        if not owner:
            raise ProbeUnavailable("accessibility-bus-inactive", "The desktop accessibility bus is not running; diagnostics did not enable it.")
        values = bus.call_sync("org.a11y.Bus", "/org/a11y/bus",
                               "org.freedesktop.DBus.Properties", "GetAll",
                               GLib.Variant("(s)", ("org.a11y.Status",)),
                               GLib.VariantType.new("(a{sv})"), flags, 1000, None).unpack()[0]
        if values.get("IsEnabled") is not True:
            raise ProbeUnavailable("accessibility-disabled", "Desktop accessibility is disabled; diagnostics did not change it.")
    except ProbeUnavailable:
        raise
    except Exception:
        raise ProbeUnavailable("accessibility-bus-unavailable", "The existing accessibility service could not be read.") from None


class AtspiReadOnlyAdapter:
    def __init__(self, Atspi, cancelled=lambda: False):
        self.api = Atspi
        self.cancelled = cancelled

    def inspect(self, binding, reader=read_process):
        # 2026-10-14：每次检查均有总时限和节点上限；只读目标应用，不记录消息、域名或命令。
        deadline = time.monotonic() + MAX_SECONDS
        self.api.set_timeout(400, 400)
        initialized = False
        try:
            if self.api.init() != 0:
                raise ProbeUnavailable("atspi-init-failed", "AT-SPI could not connect to the existing accessibility registry.")
            initialized = True
            desktop = self.api.get_desktop(0)
            if desktop is None:
                raise ProbeUnavailable("no-accessibility-desktop", "AT-SPI did not expose a desktop.")
            applications = []
            for index in range(min(desktop.get_child_count(), 256)):
                self._check(binding, reader, deadline)
                app = desktop.get_child_at_index(index)
                if app is not None and app.get_process_id() == binding.main.pid:
                    applications.append(app)
            if len(applications) != 1:
                raise ProbeUnavailable("host-tree-unavailable", "A unique accessibility application for this Antigravity process was not found.")
            app = applications[0]
            owner = app.app.bus_name
            if not isinstance(owner, str) or not owner.startswith(":"):
                raise ProbeUnavailable("unverified-bus-owner", "AT-SPI did not expose a unique application bus owner.")
            queue = [(app, 0)]
            visited = set()
            roles, labels, actions = Counter(), Counter(), Counter()
            conversation_count = 0
            while queue:
                self._check(binding, reader, deadline)
                node, depth = queue.pop()
                key = (node.app.bus_name, node.path)
                if key in visited:
                    continue
                if key[0] != owner or node.get_process_id() != binding.main.pid:
                    raise ProbeUnavailable("tree-identity-changed", "An accessibility object no longer belongs to the verified host.")
                if len(visited) >= MAX_NODES or depth > MAX_DEPTH:
                    raise ProbeUnavailable("tree-limit", "The accessibility tree exceeded the bounded diagnostic scan.")
                visited.add(key)
                role = node.get_role_name()
                roles[role if role in ROLE_CATEGORIES else "other"] += 1
                name = node.get_name()
                if name in FIXED_LABELS:
                    labels[name] += 1
                if node.get_accessible_id() == "conversation":
                    conversation_count += 1
                action = node.get_action_iface()
                if action is not None and name in FIXED_LABELS:
                    for index in range(min(action.get_n_actions(), 16)):
                        action_name = action.get_action_name(index)
                        if action_name in {"click", "press", "activate"}:
                            actions[action_name] += 1
                child_count = node.get_child_count()
                if child_count < 0 or child_count > MAX_NODES:
                    raise ProbeUnavailable("tree-limit", "The accessibility provider reported an unsupported tree size.")
                for index in range(child_count):
                    self._check(binding, reader, deadline)
                    child = node.get_child_at_index(index)
                    if child is not None:
                        queue.append((child, depth + 1))
                    if len(queue) + len(visited) > MAX_NODES:
                        raise ProbeUnavailable("tree-limit", "The accessibility tree exceeded the bounded diagnostic scan.")
            self._check(binding, reader, deadline)
            if len(visited) <= 2:
                raise ProbeUnavailable("incomplete-accessibility-tree", "Antigravity exposes only an accessibility shell; approval controls are unavailable.")
            return {"nodeCount": len(visited), "roles": dict(roles), "fixedLabels": dict(labels),
                    "actionNames": dict(actions), "conversationCount": conversation_count}
        finally:
            if initialized:
                self.api.exit()

    def _check(self, binding, reader, deadline):
        if self.cancelled():
            raise ProbeUnavailable("cancelled", "Linux diagnostics were cancelled.")
        if time.monotonic() > deadline:
            raise ProbeUnavailable("probe-timeout", "The bounded Linux accessibility diagnostic timed out.")
        if not verify_binding(binding, reader):
            raise ProbeUnavailable("host-identity-changed", "The Antigravity host exited or its process identity changed.")


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--probe", action="store_true", help="Read capability information only (the default).")
    parser.add_argument("--dry-run", action="store_true", help="Read capability information only; actions remain disabled.")
    parser.add_argument("--parent-pid", type=int, default=0)
    parser.add_argument("--host-executable", default="")
    args = parser.parse_args(argv)
    cancelled = [False]
    def stop(_signal, _frame):
        cancelled[0] = True
    signal.signal(signal.SIGTERM, stop)
    signal.signal(signal.SIGINT, stop)
    report = {"schemaVersion": 1, "backend": "linux-atspi", "actionsEnabled": ACTIONS_ENABLED}
    try:
        if sys.platform != "linux":
            raise ProbeUnavailable("unsupported-platform", "The AT-SPI diagnostic is Linux-only.")
        Atspi, Gio, GLib = load_gi()
        binding = bind_host(args.parent_pid, args.host_executable)
        check_existing_bus(Gio, GLib, os.environ)
        report.update(AtspiReadOnlyAdapter(Atspi, lambda: cancelled[0]).inspect(binding))
        report.update(status="diagnostic-only", code="actions-disabled", message="Accessibility tree inspected. Linux approval actions are not implemented or verified.")
        exit_code = 0
    except ProbeUnavailable as error:
        report.update(status="unavailable", code=error.code, message=str(error))
        exit_code = 2
    except Exception:
        # 2026-10-14：底层异常可能带有私有界面文案，输出固定诊断而不泄露原文。
        report.update(status="unavailable", code="probe-failed", message="Linux accessibility inspection failed; no actions were performed.")
        exit_code = 2
    print(json.dumps(report, ensure_ascii=True), flush=True)
    return exit_code


if __name__ == "__main__":
    sys.exit(main())
