"""2026-10-14：合成测试只调用只读适配器，不连接真实桌面或执行审批。"""

import copy
import importlib.util
import json
from pathlib import Path
import sys
import unittest

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("atspi_probe", ROOT / "src/linux/atspi_probe.py")
probe = importlib.util.module_from_spec(spec)
sys.modules[spec.name] = probe
spec.loader.exec_module(probe)


class HostTests(unittest.TestCase):
    def setUp(self):
        self.parent = probe.ProcessIdentity(300, 200, 1000, "/opt/antigravity-ide", "30")
        self.main = probe.ProcessIdentity(200, 100, 1000, "/opt/antigravity-ide", "20")
        self.shell = probe.ProcessIdentity(100, 1, 1000, "/bin/sh", "10")
        self.processes = {p.pid: p for p in (self.parent, self.main, self.shell)}

    def test_exact_ancestry(self):
        binding = probe.bind_host(300, "/opt/antigravity-ide", self.processes.__getitem__, 1000)
        self.assertEqual(binding.main, self.main)
        self.assertTrue(probe.verify_binding(binding, self.processes.__getitem__))

    def test_pid_reuse(self):
        binding = probe.HostBinding(self.parent, self.main)
        self.processes[200] = probe.ProcessIdentity(200, 100, 1000, "/opt/antigravity-ide", "99")
        self.assertFalse(probe.verify_binding(binding, self.processes.__getitem__))

    def test_wrong_executable_and_user(self):
        for expected, uid in [("/other/antigravity-ide", 1000), ("/opt/antigravity-ide", 1001), ("/opt/code", 1000)]:
            with self.subTest(expected=expected, uid=uid), self.assertRaises(probe.ProbeUnavailable):
                probe.bind_host(300, expected, self.processes.__getitem__, uid)

    def test_ancestry_cycle(self):
        self.processes[200] = probe.ProcessIdentity(200, 300, 1000, "/opt/antigravity-ide", "20")
        with self.assertRaises(probe.ProbeUnavailable):
            probe.bind_host(300, "/opt/antigravity-ide", self.processes.__getitem__, 1000)


class ShapeTests(unittest.TestCase):
    def setUp(self):
        self.nodes = json.loads((ROOT / "tests/fixtures/linux-browser-once.json").read_text())

    def test_exact_browser_once_fixture(self):
        self.assertEqual(len(probe.classify_snapshot(self.nodes)), 1)
        self.assertFalse(probe.ACTIONS_ENABLED)

    def test_wrong_host_duplicate_hidden_disabled_or_unknown_action(self):
        cases = [
            ("bus", ":1.666"), ("pid", 666), ("name", "Always Allow"),
            ("name", "Allow Once for all future requests"), ("states", ["enabled"]),
            ("states", ["enabled", "sensitive", "showing", "visible", "defunct"]),
            ("actions", ["click", "activate"]), ("actions", []), ("parent", "unrelated-card"),
        ]
        for key, value in cases:
            with self.subTest(key=key, value=value):
                nodes = copy.deepcopy(self.nodes)
                nodes[-1][key] = value
                self.assertEqual(probe.classify_snapshot(nodes), [])
        self.assertEqual(probe.classify_snapshot(self.nodes + [copy.deepcopy(self.nodes[-1])]), [])

    def test_denied_cancelled_or_unknown_cards(self):
        for outcome in ("denied", "cancelled", "completed", "unknown"):
            nodes = copy.deepcopy(self.nodes)
            nodes[2]["outcome"] = outcome
            self.assertEqual(probe.classify_snapshot(nodes), [])

    def test_missing_scope_or_target(self):
        for index, key, value in [(1, "accessibleId", "editor"), (0, "role", "document"), (3, "target", "")]:
            nodes = copy.deepcopy(self.nodes)
            nodes[index][key] = value
            self.assertEqual(probe.classify_snapshot(nodes), [])

    def test_narrow_menu_and_generic_buttons_are_unsupported(self):
        for name in ("More actions", "Run", "Accept", "Allow", "Submit", "Deny", "Cancel"):
            nodes = copy.deepcopy(self.nodes)
            nodes[-1]["name"] = name
            self.assertEqual(probe.classify_snapshot(nodes), [])


class FakeAction:
    def get_n_actions(self):
        return 1

    def get_action_name(self, index):
        return "click"

    def do_action(self, index):
        raise AssertionError("The read-only adapter must never invoke an action")


class FakeNode:
    def __init__(self, name="", role="panel", pid=200, path="/node", children=()):
        self.name, self.role, self.pid, self.path, self.children = name, role, pid, path, list(children)
        self.app = type("Application", (), {"bus_name": ":1.42"})()

    def get_child_count(self):
        return len(self.children)

    def get_child_at_index(self, index):
        return self.children[index]

    def get_process_id(self):
        return self.pid

    def get_role_name(self):
        return self.role

    def get_name(self):
        return self.name

    def get_accessible_id(self):
        return ""

    def get_action_iface(self):
        return FakeAction() if self.role == "push button" else None


class FakeApi:
    def __init__(self, desktop):
        self.desktop, self.exited = desktop, False

    def set_timeout(self, normal, startup):
        pass

    def init(self):
        return 0

    def get_desktop(self, index):
        return self.desktop

    def exit(self):
        self.exited = True


class AdapterTests(unittest.TestCase):
    def setUp(self):
        self.process = probe.ProcessIdentity(200, 1, 1000, "/opt/antigravity-ide", "20")
        self.binding = probe.HostBinding(self.process, self.process)
        button = FakeNode("Allow Once", "push button", path="/button")
        secret = FakeNode("private.example secret command", path="/secret")
        self.app = FakeNode("Private project title", "application", path="/app", children=[button, secret])
        self.api = FakeApi(FakeNode(children=[self.app]))

    def test_read_only_and_redacted_inventory(self):
        result = probe.AtspiReadOnlyAdapter(self.api).inspect(self.binding, lambda pid: self.process)
        self.assertEqual(result["fixedLabels"], {"Allow Once": 1})
        self.assertEqual(result["actionNames"], {"click": 1})
        self.assertNotIn("private.example", json.dumps(result))
        self.assertNotIn("Private project title", json.dumps(result))
        self.assertTrue(self.api.exited)

    def test_provider_controlled_role_text_is_redacted(self):
        self.app.children[1].role = "private.example secret command"
        result = probe.AtspiReadOnlyAdapter(self.api).inspect(self.binding, lambda pid: self.process)
        self.assertEqual(result["roles"]["other"], 1)
        self.assertNotIn("private.example", json.dumps(result))
        self.assertNotIn("secret command", json.dumps(result))

    def test_cancel_before_read(self):
        with self.assertRaises(probe.ProbeUnavailable) as caught:
            probe.AtspiReadOnlyAdapter(self.api, lambda: True).inspect(self.binding, lambda pid: self.process)
        self.assertEqual(caught.exception.code, "cancelled")
        self.assertTrue(self.api.exited)

    def test_changed_host(self):
        changed = probe.ProcessIdentity(200, 1, 1000, "/opt/antigravity-ide", "99")
        with self.assertRaises(probe.ProbeUnavailable) as caught:
            probe.AtspiReadOnlyAdapter(self.api).inspect(self.binding, lambda pid: changed)
        self.assertEqual(caught.exception.code, "host-identity-changed")

    def test_duplicate_application(self):
        self.api.desktop.children.append(self.app)
        with self.assertRaises(probe.ProbeUnavailable) as caught:
            probe.AtspiReadOnlyAdapter(self.api).inspect(self.binding, lambda pid: self.process)
        self.assertEqual(caught.exception.code, "host-tree-unavailable")

    def test_foreign_descendant(self):
        self.app.children[0].pid = 999
        with self.assertRaises(probe.ProbeUnavailable) as caught:
            probe.AtspiReadOnlyAdapter(self.api).inspect(self.binding, lambda pid: self.process)
        self.assertEqual(caught.exception.code, "tree-identity-changed")

    def test_incomplete_tree(self):
        self.app.children = []
        with self.assertRaises(probe.ProbeUnavailable) as caught:
            probe.AtspiReadOnlyAdapter(self.api).inspect(self.binding, lambda pid: self.process)
        self.assertEqual(caught.exception.code, "incomplete-accessibility-tree")

    def test_missing_session_bus_does_not_connect(self):
        with self.assertRaises(probe.ProbeUnavailable) as caught:
            probe.check_existing_bus(None, None, {})
        self.assertEqual(caught.exception.code, "missing-session-bus")


if __name__ == "__main__":
    unittest.main()
