/* =========================================================================
   Nebula · tests/browser.test.js
   Prueft das Theme in einem echten Chromium gegen den Nachbau der
   Panel-Oberflaeche samt Wings-WebSocket.
   ========================================================================= */

const { chromium } = require('playwright');
const fs = require('fs');
const path = require('path');

const PORT = fs.readFileSync(path.join(__dirname, '.port'), 'utf8').trim();
const BASE = 'http://127.0.0.1:' + PORT;
const SHOTS = path.join(__dirname, 'shots');
fs.mkdirSync(SHOTS, { recursive: true });

async function noHScroll(page) {
    return page.evaluate(() => {
        window.scrollTo(600, 0);
        const ok = window.scrollX === 0 &&
            document.documentElement.scrollWidth <= window.innerWidth + 1;
        window.scrollTo(0, 0);
        return ok ? true : document.documentElement.scrollWidth + ' > ' + window.innerWidth;
    });
}

const results = [];
function check(name, cond, extra) {
    results.push({ name, ok: !!cond, extra: extra === undefined ? '' : String(extra) });
    console.log((cond ? 'PASS  ' : 'FAIL  ') + name + (extra !== undefined ? '   [' + extra + ']' : ''));
}

(async () => {
    const browser = await chromium.launch({ executablePath: '/opt/pw-browsers/chromium', args: ['--no-sandbox'] });
    const ctx = await browser.newContext({ viewport: { width: 1500, height: 940 }, deviceScaleFactor: 1 });
    const page = await ctx.newPage();

    const errors = [];
    page.on('console', (m) => { if (m.type() === 'error') errors.push(m.text()); });
    page.on('pageerror', (e) => errors.push('pageerror: ' + e.message));

    /* ================= Anmeldung ================= */
    await page.goto(BASE + '/auth/login', { waitUntil: 'domcontentloaded' });
    await page.waitForTimeout(700);
    check('PTD verfuegbar', await page.evaluate(() => !!window.PTD));
    check('Anmeldeseite erkannt', (await page.getAttribute('html', 'data-ptd-page')) === 'auth');
    check('Login-Karte getaggt', await page.locator('[data-ptd="auth-card"]').count() > 0);
    check('Markenkopf eingefuegt', await page.locator('#ptd-auth-brand').count() > 0);
    check('Verlaufsebene sichtbar (Body transparent)',
        (await page.evaluate(() => getComputedStyle(document.body).backgroundColor)) === 'rgba(0, 0, 0, 0)');
    check('Schiene auf der Anmeldeseite ausgeblendet',
        await page.evaluate(() => {
            const r = document.querySelector('#ptd-rail');
            return !r || getComputedStyle(r).display === 'none';
        }));
    check('Anmeldeknopf als primary erkannt',
        (await page.getAttribute('form button[type="submit"]', 'data-ptd-btn')) === 'primary');
    await page.screenshot({ path: path.join(SHOTS, '01-login.png') });

    /* ================= Dashboard ================= */
    await page.goto(BASE + '/', { waitUntil: 'domcontentloaded' });
    await page.waitForTimeout(1400);

    check('Seitenschiene vorhanden', await page.locator('#ptd-rail').isVisible());
    check('Panel-Navigation ausgeblendet',
        await page.evaluate(() => getComputedStyle(document.querySelector('#navigation')).display === 'none'));
    check('Navigationseintraege gespiegelt',
        await page.locator('#ptd-rail .ptd-rail-item:not([data-ptd-server])').count() >= 2,
        await page.locator('#ptd-rail .ptd-rail-item:not([data-ptd-server])').count());
    check('Server in der Schiene',
        await page.locator('#ptd-rail .ptd-rail-item[data-ptd-server]').count() === 3,
        await page.locator('#ptd-rail .ptd-rail-item[data-ptd-server]').count());
    check('Kopfleiste vorhanden', await page.locator('#ptd-topbar').isVisible());
    check('Uebersichtskacheln gerendert',
        await page.locator('#ptd-overview .ptd-sv').count() === 3,
        await page.locator('#ptd-overview .ptd-sv').count());
    check('Originalliste ausgeblendet',
        await page.evaluate(() => {
            const row = document.querySelector('[data-ptd="server-card"]');
            return !row || getComputedStyle(row).display === 'none';
        }));
    check('Kennzahlen im Kopfbereich', await page.locator('#ptd-hero-stats .ptd-hero-stat').count() === 4);
    const hs1 = await noHScroll(page);
    check('Dashboard scrollt nicht seitlich', hs1 === true, hs1);

    const usage = await page.locator('#ptd-overview .ptd-sv .ptd-sv-u-value').first().innerText();
    check('Live-Auslastung auf der Kachel', /%|MiB|GiB/.test(usage), usage);
    const onlineStat = await page.locator('#ptd-hero-stats .ptd-hero-stat').nth(1).innerText();
    check('Online-Zaehler gefuellt', /\d+\/\d+/.test(onlineStat), onlineStat.replace(/\n/g, ' '));
    await page.screenshot({ path: path.join(SHOTS, '02-dashboard.png') });

    /* ================= Anheften ================= */
    await page.locator('#ptd-overview .ptd-sv').first().hover();
    await page.locator('#ptd-overview .ptd-sv').first().locator('button[aria-label="Anheften"]').click();
    await page.waitForTimeout(400);
    check('Server angeheftet',
        (await page.evaluate(() => (window.PTD.get('favorites') || []).length)) === 1);
    check('Abschnitt "Angeheftet" erscheint',
        (await page.locator('#ptd-rail .ptd-rail-title').first().innerText()).indexOf('ANGEHEFTET') > -1 ||
        (await page.locator('#ptd-rail .ptd-rail-title').allInnerTexts()).join(' ').toLowerCase().indexOf('angeheftet') > -1);

    /* ================= Schiene einklappen ================= */
    await page.keyboard.press('Control+b');
    await page.waitForTimeout(400);
    check('Schiene eingeklappt', (await page.getAttribute('html', 'data-ptd-rail')) === 'mini');
    const railW = await page.evaluate(() => document.querySelector('#ptd-rail').getBoundingClientRect().width);
    check('Schmale Schiene ist schmal', railW < 90, Math.round(railW) + 'px');
    await page.screenshot({ path: path.join(SHOTS, '03-rail-mini.png') });
    await page.keyboard.press('Control+b');
    await page.waitForTimeout(400);

    /* ================= Befehlspalette ================= */
    await page.keyboard.press('Control+k');
    await page.waitForTimeout(500);
    check('Palette offen', await page.locator('#ptd-palette').isVisible());
    await page.keyboard.type('lobby');
    await page.waitForTimeout(400);
    const first = await page.locator('#ptd-palette .ptd-p-item').first();
    check('Serversuche findet "Lobby Proxy"',
        /lobby/i.test(await first.locator('.ptd-p-title').innerText()),
        await first.locator('.ptd-p-title').innerText());
    check('Treffer hervorgehoben', await page.locator('#ptd-palette .ptd-p-title mark').count() > 0);
    check('Statuspunkt am Servereintrag', await first.locator('.ptd-p-state').count() > 0);
    await page.screenshot({ path: path.join(SHOTS, '04-palette.png') });
    await page.keyboard.press('Escape');
    await page.waitForTimeout(300);

    /* ================= Serverkonsole ================= */
    await page.goto(BASE + '/server/a1b2c3d4', { waitUntil: 'domcontentloaded' });
    await page.waitForTimeout(900);
    check('Statuswechsel-Meldung erschienen', await page.locator('#ptd-toasts .ptd-toast').count() > 0,
        await page.locator('#ptd-toasts .ptd-toast').count());
    await page.waitForTimeout(2400);

    check('Reiter getaggt', await page.locator('[data-ptd="subnav"]').count() > 0);
    check('Aktiver Reiter markiert', await page.locator('[data-ptd="subnav"] a[data-ptd-active="1"]').count() === 1);
    check('Pfadanzeige gefuellt',
        (await page.locator('#ptd-topbar .ptd-crumbs').innerText()).indexOf('Konsole') > -1,
        (await page.locator('#ptd-topbar .ptd-crumbs').innerText()).replace(/\n/g, ' '));
    check('Serverangaben in der Kopfleiste',
        /play\.example\.de:25565/.test(await page.locator('#ptd-topbar .ptd-tb-chips').innerText()),
        (await page.locator('#ptd-topbar .ptd-tb-chips').innerText()).replace(/\n/g, ' | '));
    check('Konsolen-Werkzeugleiste', await page.locator('#ptd-console-bar').isVisible());
    check('Kurzbefehl-Leiste', await page.locator('#ptd-snippets').isVisible());
    const hs2 = await noHScroll(page);
    check('Serverseite scrollt nicht seitlich', hs2 === true, hs2);

    const lines = await page.evaluate(() => window.PTD.store.lines.length);
    check('Konsolenzeilen ueber WebSocket', lines > 5, lines + ' Zeilen');
    check('Serverstatus erkannt', (await page.evaluate(() => window.PTD.store.state)) === 'running');
    check('ANSI-Codes entfernt',
        await page.evaluate(() => window.PTD.store.lines.every((l) => l.text.indexOf(String.fromCharCode(27)) === -1)));
    check('Log-Level erkannt',
        await page.evaluate(() => window.PTD.store.lines.some((l) => l.lvl === 'error') &&
                                  window.PTD.store.lines.some((l) => l.lvl === 'warn')));

    /* ================= Diagramme ================= */
    check('Vier Diagramme', await page.locator('#ptd-charts .ptd-chart').count() === 4);
    const d = await page.getAttribute('#ptd-charts .ptd-chart[data-key="cpu"] .ptd-line-path', 'd');
    check('CPU-Kurve hat Daten', !!d && d.length > 20, (d || '').slice(0, 22) + '…');
    check('Raster gezeichnet', await page.locator('#ptd-charts .ptd-chart[data-key="cpu"] .ptd-grid-line').count() === 3);
    const foot = await page.locator('#ptd-charts .ptd-chart[data-key="mem"] .ptd-chart-foot').innerText();
    check('Min/Mittel/Max ausgewiesen', /min[\s\S]*ø[\s\S]*max/i.test(foot), foot.replace(/\n/g, ' '));

    const plot = page.locator('#ptd-charts .ptd-chart[data-key="cpu"] .ptd-chart-plot');
    const pb = await plot.boundingBox();
    await page.mouse.move(pb.x + pb.width * 0.6, pb.y + pb.height / 2);
    await page.waitForTimeout(300);
    check('Fadenkreuz beim Ueberfahren',
        await page.locator('#ptd-charts .ptd-chart[data-key="cpu"] .ptd-chart-plot.is-hover').count() > 0);
    const tip = await page.locator('#ptd-charts .ptd-chart[data-key="cpu"] .ptd-chart-tip').innerText();
    check('Sprechblase zeigt Wert und Zeit', /%/.test(tip) && /\d{2}:\d{2}/.test(tip), tip.replace(/\n/g, ' '));
    await page.screenshot({ path: path.join(SHOTS, '05-console.png') });

    /* ================= Kurzbefehle senden ================= */
    await page.evaluate(() => {
        const m = window.PTD.get('snippets') || {};
        m['a1b2c3d4'] = ['say Wartung in 5 Minuten'];
        window.PTD.settings.snippets = m;
        window.PTD.save();
        window.PTD.bus.emit('settings', window.PTD.settings);
    });
    await page.waitForTimeout(400);
    check('Kurzbefehl-Chip erscheint', await page.locator('#ptd-snippets .ptd-snip').first().isVisible());
    await page.locator('#ptd-snippets .ptd-snip').first().click();
    await page.waitForTimeout(800);
    check('Befehl ging ueber die bestehende Verbindung',
        await page.evaluate(() => window.PTD.store.lines.some((l) => l.text.indexOf('ausgefuehrt: say Wartung') > -1)));

    /* ================= Konsolensuche ================= */
    await page.fill('#ptd-console-bar .ptd-csearch input', 'ERROR');
    await page.waitForTimeout(500);
    check('Puffer-Ansicht geoeffnet', await page.locator('#ptd-log-view.is-open').count() > 0);
    check('Treffer hervorgehoben', await page.locator('#ptd-log-view mark').count() > 0);
    await page.screenshot({ path: path.join(SHOTS, '06-console-search.png') });
    await page.fill('#ptd-console-bar .ptd-csearch input', '');
    await page.waitForTimeout(300);

    /* ================= Mini-Konsole ================= */
    await page.click('#ptd-tb-dock');
    await page.waitForTimeout(500);
    check('Mini-Konsole offen', await page.locator('#ptd-dock.is-open').isVisible());
    check('Mini-Konsole zeigt Zeilen', await page.locator('#ptd-dock .ptd-dock-body .ptd-line').count() > 3);

    const before = await page.evaluate(() => document.querySelector('#ptd-dock').getBoundingClientRect().left);
    const head = await page.locator('#ptd-dock .ptd-dock-head').boundingBox();
    await page.mouse.move(head.x + head.width / 2, head.y + head.height / 2);
    await page.mouse.down();
    await page.mouse.move(head.x + head.width / 2 - 200, head.y + head.height / 2 - 120, { steps: 12 });
    await page.mouse.up();
    await page.waitForTimeout(600);
    const after = await page.evaluate(() => document.querySelector('#ptd-dock').getBoundingClientRect().left);
    check('Mini-Konsole laesst sich ziehen', Math.abs(after - before) > 100, Math.round(before) + ' → ' + Math.round(after));

    await page.fill('#ptd-dock .ptd-dock-input input', 'list');
    await page.press('#ptd-dock .ptd-dock-input input', 'Enter');
    await page.waitForTimeout(700);
    check('Befehl aus der Mini-Konsole gesendet',
        await page.evaluate(() => window.PTD.store.lines.some((l) => l.text.indexOf('ausgefuehrt: list') > -1)));
    await page.screenshot({ path: path.join(SHOTS, '07-dock.png') });
    await page.click('#ptd-tb-dock');
    await page.waitForTimeout(300);

    /* ================= Waechter und Schwellwerte ================= */
    await page.evaluate(() => {
        const host = document.querySelector('#ptd-toasts');
        if (host) host.innerHTML = '';
        window.PTD.settings.watchers = ['players online'];
        window.PTD.save();
    });
    await page.waitForTimeout(1500);
    check('Schluesselwort-Waechter meldet Treffer',
        (await page.locator('#ptd-toasts .ptd-toast .ptd-t-title').allInnerTexts())
            .some((t) => /players online/i.test(t)),
        (await page.locator('#ptd-toasts .ptd-toast .ptd-t-title').allInnerTexts()).join(' | '));

    await page.evaluate(() => {
        document.querySelector('#ptd-toasts').innerHTML = '';
        window.PTD.settings.watchers = [];
        window.PTD.settings.alertCpu = 5;
        window.PTD.settings.alertHold = 5;
        window.PTD.save();
    });
    await page.waitForTimeout(7000);
    check('Auslastungswarnung ausgeloest',
        (await page.locator('#ptd-toasts .ptd-toast .ptd-t-title').allInnerTexts())
            .some((t) => /CPU ueber/i.test(t)),
        (await page.locator('#ptd-toasts .ptd-toast .ptd-t-title').allInnerTexts()).join(' | '));
    await page.evaluate(() => { window.PTD.settings.alertCpu = 90; window.PTD.save(); });

    /* ================= Einstellungen ================= */
    await page.click('#ptd-fab');
    await page.waitForTimeout(500);
    check('Einstellungen offen', await page.locator('#ptd-drawer.is-open').count() > 0);
    check('Reiter vorhanden', await page.locator('#ptd-drawer .ptd-d-tabs button').count() === 6);
    await page.screenshot({ path: path.join(SHOTS, '08-settings.png') });

    await page.click('#ptd-drawer .ptd-swatches .ptd-swatch:nth-child(4)');
    await page.waitForTimeout(400);
    check('Preset gewechselt (ember)', (await page.getAttribute('html', 'data-ptd-preset')) === 'ember');

    await page.click('#ptd-drawer .ptd-d-tabs button:nth-child(4)');
    await page.waitForTimeout(300);
    check('Reiter "Warnungen" zeigt Waechterliste',
        /schluesselwoerter/i.test(await page.locator('#ptd-drawer .ptd-d-body').innerText()));
    await page.screenshot({ path: path.join(SHOTS, '09-settings-alerts.png') });

    await page.click('#ptd-drawer .ptd-d-tabs button:nth-child(1)');
    await page.waitForTimeout(200);
    await page.click('#ptd-drawer .ptd-seg button:nth-child(2)');
    await page.waitForTimeout(400);
    check('Hellmodus aktiv', (await page.getAttribute('html', 'data-ptd-mode')) === 'light');
    await page.evaluate(() => { window.PTD.set('preset', 'ocean'); window.PTD.settingsPanel.close(); });
    await page.waitForTimeout(700);
    const termBg = await page.evaluate(() =>
        getComputedStyle(document.querySelector('[data-ptd="console"]')).backgroundImage.slice(0, 60));
    check('Terminal bleibt im Hellmodus dunkel', /rgb\(1[0-9], 1[0-9], 2[0-9]\)|6, 7, 12|10, 12, 19/.test(termBg), termBg);
    await page.screenshot({ path: path.join(SHOTS, '10-light.png') });

    await page.evaluate(() => { window.PTD.set('mode', 'dark'); window.PTD.set('preset', 'nebula'); });
    await page.waitForTimeout(400);

    /* ================= Fokusmodus ================= */
    await page.keyboard.press('Control+Shift+z');
    await page.waitForTimeout(500);
    check('Fokusmodus aktiv', (await page.getAttribute('html', 'data-ptd-focus')) === '1');
    await page.screenshot({ path: path.join(SHOTS, '11-focus.png') });
    await page.keyboard.press('Escape');
    await page.waitForTimeout(400);
    check('Fokusmodus per Esc beendet', (await page.getAttribute('html', 'data-ptd-focus')) === null);

    /* ================= Tastenkuerzel ================= */
    await page.keyboard.press('Control+/');
    await page.waitForTimeout(400);
    check('Tastenkuerzel-Uebersicht', await page.locator('#ptd-keys').isVisible());
    await page.screenshot({ path: path.join(SHOTS, '12-shortcuts.png') });
    await page.keyboard.press('Escape');
    await page.waitForTimeout(300);

    /* ================= Navigation innerhalb der Anwendung ================= */
    await page.click('[data-ptd="subnav"] a[href$="/files"]');
    await page.waitForTimeout(800);
    check('Route gewechselt', (await page.evaluate(() => window.PTD.route.sub)) === 'files');
    check('Werkzeugleiste auf anderer Seite entfernt', await page.locator('#ptd-console-bar').count() === 0);
    check('Pfadanzeige nachgezogen',
        (await page.locator('#ptd-topbar .ptd-crumbs').innerText()).indexOf('Dateien') > -1);
    check('Aktiver Reiter nachgezogen',
        (await page.getAttribute('[data-ptd="subnav"] a[data-ptd-active="1"]', 'href')) === '/server/a1b2c3d4/files');

    /* ================= Einstellungen ueberdauern ================= */
    await page.evaluate(() => { window.PTD.set('preset', 'forest'); window.PTD.set('compact', true); });
    await page.reload({ waitUntil: 'domcontentloaded' });
    await page.waitForTimeout(900);
    check('Einstellungen ueberleben Neuladen',
        (await page.getAttribute('html', 'data-ptd-preset')) === 'forest' &&
        (await page.getAttribute('html', 'data-ptd-compact')) === '1');
    check('Angeheftete Server bleiben erhalten',
        (await page.evaluate(() => (window.PTD.get('favorites') || []).length)) === 1);
    await page.evaluate(() => window.PTD.reset());

    /* ================= Mobiles Layout ================= */
    await page.setViewportSize({ width: 420, height: 820 });
    await page.goto(BASE + '/', { waitUntil: 'domcontentloaded' });
    await page.waitForTimeout(1000);
    check('Schiene mobil ausgefahren-versteckt',
        await page.evaluate(() => {
            const r = document.querySelector('#ptd-rail').getBoundingClientRect();
            return r.right <= 1;
        }));
    await page.click('#ptd-topbar .ptd-tb-menu');
    await page.waitForTimeout(500);
    check('Schiene mobil geoeffnet', (await page.getAttribute('html', 'data-ptd-railopen')) === '1');
    await page.screenshot({ path: path.join(SHOTS, '13-mobile.png') });
    await page.setViewportSize({ width: 1500, height: 940 });

    /* ================= Fehlerfreiheit ================= */
    const real = errors.filter((e) => !/favicon|Failed to load resource/i.test(e));
    check('Keine JavaScript-Fehler', real.length === 0, real.slice(0, 3).join(' | '));

    await browser.close();

    const failed = results.filter((r) => !r.ok);
    console.log('\n' + (results.length - failed.length) + '/' + results.length + ' Pruefungen bestanden');
    if (failed.length) {
        console.log('Fehlgeschlagen:');
        failed.forEach((f) => console.log('  - ' + f.name + (f.extra ? '  [' + f.extra + ']' : '')));
        process.exit(1);
    }
})().catch((e) => { console.error(e); process.exit(1); });
