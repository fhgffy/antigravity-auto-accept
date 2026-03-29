// 2026-03-29 v5.0.0 按钮检测器 — 注入到webview中执行的JS脚本 //***

// 目标按钮文本（优先级从高到低）
const BUTTON_TEXTS = [
    'run',
    'run command',
    'accept',
    'accept all',
    'accept changes',
    'accept all changes',
    'always allow',
    'allow this conversation',
    'allow',
    'apply',
    'apply changes',
    'apply edits',
    'apply all',
    'continue',
    'proceed',
    'retry',
    'yes',
    'ok',
    'approve',
    'confirm',
    'save',
    'execute',
    'execute command',
    'overwrite',
    'yes, overwrite',
];

// 排除列表（防止误点）
const EXCLUDED_TEXTS = [
    'always run',   // 这是下拉菜单，不是动作按钮
    'run and debug',
];

export function buildDetectorScript(): string {
    const textsJson = JSON.stringify(BUTTON_TEXTS);
    const excludedJson = JSON.stringify(EXCLUDED_TEXTS);

    return `
(function() {
    var BUTTON_TEXTS = ${textsJson};
    var EXCLUDE_TEXTS = ${excludedJson};

    function checkButton(node) {
        if (!node || !node.tagName) return null;

        var tag = node.tagName.toUpperCase();
        var role = (node.getAttribute && node.getAttribute('role')) || '';
        var cls = (node.className || '').toString().toLowerCase();

        // 只匹配可交互元素
        var isInteractive = (
            tag === 'BUTTON' || tag === 'A' || tag === 'VSCODE-BUTTON' ||
            role === 'button' ||
            ((tag === 'SPAN' || tag === 'DIV') &&
             (cls.indexOf('cursor-pointer') !== -1 || cls.indexOf('monaco-button') !== -1))
        );
        if (!isInteractive) return null;

        var text = (node.textContent || '').trim().toLowerCase();
        if (!text || text.length > 50) return null;

        // 排除菜单项
        if (role === 'menuitem' || role === 'menubar') return null;
        if (cls.indexOf('menubar') !== -1 || cls.indexOf('menu-title') !== -1) return null;

        // 排除列表检查
        for (var e = 0; e < EXCLUDE_TEXTS.length; e++) {
            if (text === EXCLUDE_TEXTS[e]) return null;
        }

        // 关键字匹配
        var matched = false;
        for (var i = 0; i < BUTTON_TEXTS.length; i++) {
            var bt = BUTTON_TEXTS[i];
            if (text === bt) { matched = true; break; }
            // startsWith匹配，处理 "RunAlt+Enter" 这种带快捷键的情况
            if (text.startsWith(bt)) {
                var suffix = text.substring(bt.length);
                // 短词(<=3字符)需要词边界检查
                if (bt.length <= 3) {
                    if (suffix === '' || /^[\\s(\\[+]/.test(suffix)) { matched = true; break; }
                    if (text.indexOf('alt') !== -1 || text.indexOf('ctrl') !== -1 || text.indexOf('+') !== -1) {
                        matched = true; break;
                    }
                } else {
                    if (text.length < bt.length + 20) { matched = true; break; }
                }
            }
        }
        if (!matched) return null;

        // 如果子节点中有更精确的按钮，跳过父节点
        if (node.querySelectorAll) {
            var children = node.querySelectorAll('button, a, vscode-button, [role="button"]');
            for (var c = 0; c < children.length; c++) {
                if ((children[c].textContent || '').trim().toLowerCase() === text) {
                    return null;
                }
            }
        }

        // 可见性检查
        var rect = node.getBoundingClientRect ? node.getBoundingClientRect() : {width:0, height:0};
        if (rect.width === 0 && rect.height === 0) return null;

        return node;
    }

    function searchButtons(root) {
        // 第一轮：直接搜索可交互元素
        var selectors = 'button, a, [role="button"], vscode-button, .cursor-pointer, .monaco-button, [class*="cursor-pointer"]';
        var all = root.querySelectorAll(selectors);
        for (var i = 0; i < all.length; i++) {
            if (all[i].shadowRoot) {
                var res = searchButtons(all[i].shadowRoot);
                if (res) return res;
            }
            var match = checkButton(all[i]);
            if (match) return match;
        }
        // 第二轮：遍历shadow DOM
        var allEls = root.querySelectorAll('*');
        for (var j = 0; j < allEls.length; j++) {
            if (allEls[j].shadowRoot) {
                var res2 = searchButtons(allEls[j].shadowRoot);
                if (res2) return res2;
            }
        }
        return null;
    }

    var found = searchButtons(document);
    if (found) {
        if (found.scrollIntoView) {
            found.scrollIntoView({ behavior: 'auto', block: 'center', inline: 'center' });
        }
        var rect = found.getBoundingClientRect();
        var cx = Math.round(rect.x + rect.width / 2);
        var cy = Math.round(rect.y + rect.height / 2);
        return { clicked: true, text: (found.textContent || '').trim().toLowerCase(), x: cx, y: cy };
    }
    return { clicked: false };
})();
`;
}
