import * as http from 'http';
import WebSocket = require('ws');

// 2026-03-29 v5.0.0 CDP架构重写 //***

export interface CdpTarget {
    id: string;
    type: string;
    url: string;
    webSocketDebuggerUrl: string;
    title: string;
}

export interface ClickResult {
    clicked: boolean;
    text?: string;
    x?: number;
    y?: number;
}

export class CdpClient {
    private port: number;
    private log: (msg: string) => void;

    constructor(port: number, log: (msg: string) => void) {
        this.port = port;
        this.log = log;
    }

    // 检测CDP端口是否开放
    async isPortOpen(): Promise<boolean> {
        return new Promise((resolve) => {
            const req = http.get(
                { host: '127.0.0.1', port: this.port, path: '/json', timeout: 1500 },
                (res) => {
                    resolve(res.statusCode === 200);
                    res.resume();
                }
            );
            req.on('error', () => resolve(false));
            req.on('timeout', () => { req.destroy(); resolve(false); });
        });
    }

    // 获取所有CDP调试目标
    private async getTargets(): Promise<CdpTarget[]> {
        return new Promise((resolve) => {
            const req = http.get(
                { host: '127.0.0.1', port: this.port, path: '/json', timeout: 2000 },
                (res) => {
                    let data = '';
                    res.on('data', (chunk) => (data += chunk));
                    res.on('end', () => {
                        try { resolve(JSON.parse(data) as CdpTarget[]); }
                        catch { resolve([]); }
                    });
                }
            );
            req.on('error', () => resolve([]));
            req.on('timeout', () => { req.destroy(); resolve([]); });
        });
    }

    // 在所有agent相关的webview目标上执行检测脚本
    async evaluateOnAgentTargets(script: string): Promise<ClickResult[]> {
        const targets = await this.getTargets();
        const results: ClickResult[] = [];

        for (const target of targets) {
            // Antigravity的agent面板类型可能是webview、page或iframe
            const isRelevant = target.type === 'webview' || target.type === 'page' || target.type === 'iframe';
            if (!target.webSocketDebuggerUrl || !isRelevant) { continue; }

            try {
                const result = await this.evaluateOnTarget(target.webSocketDebuggerUrl, script);
                if (result && result.clicked && typeof result.x === 'number' && result.x > 0) {
                    // 找到按钮了，发送CDP物理点击
                    await this.sendClick(target.webSocketDebuggerUrl, result.x, result.y!);
                }
                if (result) { results.push(result); }
            } catch (e) {
                this.log(`[CDP] target ${target.id} error: ${e}`);
            }
        }
        return results;
    }

    // 通过CDP Input.dispatchMouseEvent模拟鼠标点击
    private sendClick(wsUrl: string, x: number, y: number): Promise<void> {
        return new Promise((resolve) => {
            const ws = new WebSocket(wsUrl);
            let step = 0;
            const next = () => {
                step++;
                if (step === 1) {
                    ws.send(JSON.stringify({
                        id: 10, method: 'Input.dispatchMouseEvent',
                        params: { type: 'mousePressed', x, y, button: 'left', clickCount: 1 }
                    }));
                } else if (step === 2) {
                    ws.send(JSON.stringify({
                        id: 11, method: 'Input.dispatchMouseEvent',
                        params: { type: 'mouseReleased', x, y, button: 'left', clickCount: 1 }
                    }));
                } else {
                    try { ws.close(); } catch { }
                    resolve();
                }
            };
            ws.on('open', () => next());
            ws.on('message', () => next());
            ws.on('error', () => { try { ws.close(); } catch { } resolve(); });
            setTimeout(() => { try { ws.close(); } catch { } resolve(); }, 2000);
        });
    }

    // 在单个target上执行JS脚本
    private evaluateOnTarget(wsUrl: string, script: string): Promise<ClickResult | null> {
        return new Promise((resolve) => {
            const ws = new WebSocket(wsUrl);
            let resolved = false;
            const done = (val: ClickResult | null) => {
                if (!resolved) {
                    resolved = true;
                    try { ws.close(); } catch { }
                    resolve(val);
                }
            };

            const timeout = setTimeout(() => done(null), 3000);

            ws.on('open', () => {
                ws.send(JSON.stringify({
                    id: 1,
                    method: 'Runtime.evaluate',
                    params: { expression: script, returnByValue: true, awaitPromise: false }
                }));
            });

            ws.on('message', (data: Buffer | string) => {
                clearTimeout(timeout);
                try {
                    const msg = JSON.parse(data.toString());
                    if (msg.id === 1) {
                        done(msg.result?.result?.value ?? null);
                    }
                } catch { done(null); }
            });

            ws.on('error', () => { clearTimeout(timeout); done(null); });
        });
    }
}
