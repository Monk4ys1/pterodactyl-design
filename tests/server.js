const http = require('http');
const fs = require('fs');
const path = require('path');
const { WebSocketServer } = require('ws');

const ROOT = __dirname;
const MOCK = path.join(ROOT, 'mock');
const DIST = path.join(ROOT, '..', 'dist');
const SID = 'a1b2c3d4';
const ESC = String.fromCharCode(27);

function serverPayload(id, name) {
    return {
        object: 'server',
        attributes: {
            identifier: id,
            uuid: '11111111-2222-3333-4444-555555555555',
            name: name, node: 'Node Alpha', description: 'Testserver',
            is_suspended: false,
            limits: { memory: 2048, disk: 10240, cpu: 200, swap: 0, io: 500 },
            relationships: {
                allocations: {
                    data: [{ object: 'allocation', attributes: { id: 1, ip: '10.0.0.5', ip_alias: 'play.example.de', port: 25565, is_default: true } }]
                }
            }
        }
    };
}

const srv = http.createServer((req, res) => {
    const url = new URL(req.url, 'http://localhost');
    const p = url.pathname;

    if (p.startsWith('/api/')) {
        res.setHeader('content-type', 'application/json');
        if (p === '/api/client') {
            return res.end(JSON.stringify({
                object: 'list',
                data: [serverPayload(SID, 'Testserver 1'), serverPayload('srv2', 'Lobby Proxy'), serverPayload('srv3', 'Survival Welt')],
                meta: { pagination: { total: 3 } }
            }));
        }
        let m = p.match(/^\/api\/client\/servers\/([^/]+)$/);
        if (m) return res.end(JSON.stringify(serverPayload(m[1], 'Testserver 1')));
        m = p.match(/^\/api\/client\/servers\/([^/]+)\/resources$/);
        if (m) {
            return res.end(JSON.stringify({
                object: 'stats',
                attributes: {
                    current_state: 'running', is_suspended: false,
                    resources: { memory_bytes: 536870912, cpu_absolute: 24.5, disk_bytes: 1048576000, uptime: 90000 }
                }
            }));
        }
        if (/\/power$/.test(p)) { res.statusCode = 204; return res.end(); }
        res.statusCode = 404;
        return res.end('{}');
    }

    let file;
    if (p.startsWith('/assets/')) file = path.join(DIST, p.slice('/assets/'.length));
    else if (p === '/mock-app.js' || p === '/pterodactyl.css' || p === '/adminlte.css') file = path.join(MOCK, p.slice(1));
    else if (p.startsWith('/admin')) file = path.join(MOCK, 'admin.html');
    else file = path.join(MOCK, 'index.html');

    fs.readFile(file, (err, buf) => {
        if (err) { res.statusCode = 404; return res.end('not found'); }
        const ext = path.extname(file);
        res.setHeader('content-type',
            ext === '.css' ? 'text/css' : ext === '.js' ? 'text/javascript' : 'text/html; charset=utf-8');
        res.end(buf);
    });
});

const wss = new WebSocketServer({ server: srv, path: '/api/servers/11111111-2222-3333-4444-555555555555/ws' });

wss.on('connection', (ws) => {
    const send = (event, args) => { try { ws.send(JSON.stringify({ event, args })); } catch (e) {} };
    send('auth success', []);
    send('status', ['offline']);

    let rx = 1000, tx = 2000, t = 0, live = false;
    setTimeout(() => send('status', ['starting']), 150);
    setTimeout(() => {
        send('console output', [ESC + '[32m[INFO] Starting minecraft server version 1.20.4' + ESC + '[0m']);
        send('console output', ['[WARN] Deprecated option detected in server.properties']);
        send('console output', ['[ERROR] Failed to bind to port 25565 already in use']);
        send('console output', ['[INFO] Done (4.281s)! For help, type "help"']);
    }, 300);
    setTimeout(() => { live = true; send('status', ['running']); }, 450);

    const iv = setInterval(() => {
        if (!live) return;
        t++;
        rx += 4096 * t; tx += 2048 * t;
        send('stats', [JSON.stringify({
            memory_bytes: (400 + Math.round(Math.sin(t / 3) * 80 + t * 3)) * 1048576,
            memory_limit_bytes: 2147483648,
            cpu_absolute: 20 + Math.round(Math.sin(t / 2) * 15 + t),
            disk_bytes: 1048576000 + t * 1000,
            network: { rx_bytes: rx, tx_bytes: tx },
            state: 'running',
            uptime: 90000 + t * 1000
        })]);
        send('console output', ['[INFO] tick ' + t + ' players online']);
    }, 110);

    ws.on('close', () => clearInterval(iv));
});

srv.listen(8899, '127.0.0.1', () => console.log('mock panel on http://127.0.0.1:8899'));
