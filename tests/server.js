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
        /* Realistische, begrenzte Lastkurve – kein unbegrenzter Anstieg. */
        send('stats', [JSON.stringify({
            memory_bytes: Math.round((760 + Math.sin(t / 9) * 190 + Math.sin(t / 2.3) * 45) * 1048576),
            memory_limit_bytes: 2147483648,
            cpu_absolute: Math.max(2, Math.round(58 + Math.sin(t / 7) * 34 + Math.sin(t / 1.7) * 12)),
            disk_bytes: 1048576000 + t * 1000,
            network: { rx_bytes: rx, tx_bytes: tx },
            state: 'running',
            uptime: 90000 + t * 1000
        })]);
        send('console output', ['[INFO] tick ' + t + ' players online']);
    }, 110);

    /* Kommandos, die das Theme ueber die bestehende Verbindung schickt,
       werden zurueckgespiegelt – so laesst sich pruefen, dass sie wirklich
       auf der Leitung landen. */
    ws.on('message', (raw) => {
        let msg;
        try { msg = JSON.parse(raw.toString()); } catch (e) { return; }
        if (msg && msg.event === 'send command') {
            send('console output', ['[Nebula] ausgefuehrt: ' + (msg.args || [])[0]]);
        }
    });

    ws.on('close', () => clearInterval(iv));
});

/* Port 0 = freier Port vom Betriebssystem. Die Nummer landet in tests/.port,
   damit parallele oder haengengebliebene Laeufe sich nie in die Quere kommen. */
srv.listen(Number(process.env.PORT || 0), '127.0.0.1', () => {
    const port = srv.address().port;
    fs.writeFileSync(path.join(ROOT, '.port'), String(port));
    console.log('mock panel on http://127.0.0.1:' + port);
});

function shutdown() {
    try { fs.unlinkSync(path.join(ROOT, '.port')); } catch (e) { /* egal */ }
    process.exit(0);
}
process.on('SIGTERM', shutdown);
process.on('SIGINT', shutdown);
