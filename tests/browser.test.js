const { chromium } = require('playwright');
const fs = require('fs');
const path = require('path');

const BASE = 'http://127.0.0.1:8899';
const SHOTS = path.join(__dirname, 'shots');
fs.mkdirSync(SHOTS, { recursive: true });

const results = [];
function check(name, cond, extra) {
    results.push({ name, ok: !!cond, extra: extra === undefined ? '' : String(extra) });
    console.log((cond ? 'PASS  ' : 'FAIL  ') + name + (extra !== undefined ? '   [' + extra + ']' : ''));
}

(async () => {
    const browser = await chromium.launch({ executablePath: '/opt/pw-browsers/chromium', args: ['--no-sandbox'] });
    const ctx = await browser.newContext({ viewport: { width: 1440, height: 900 }, deviceScaleFactor: 1 });
    const page = await ctx.newPage();

    const errors = [];
    page.on('console', (m) => { if (m.type() === 'error') errors.push(m.text()); });
    page.on('pageerror', (e) => errors.push('pageerror: ' + e.message));

    /* ---------- Login ---------- */
    await page.goto(BASE + '/auth/login', { waitUntil: 'networkidle' });
    await page.waitForTimeout(600);
    check('PTD global vorhanden', await page.evaluate(() => !!window.PTD));
    check('html[data-ptd-preset]', (await page.getAttribute('html', 'data-ptd-preset')) === 'nebula');
    check('Auth-Seite erkannt', (await page.getAttribute('html', 'data-ptd-page')) === 'auth');
    check('Login-Karte getaggt', await page.locator('[data-ptd="auth-card"]').count() > 0);
    check('Markenkopf eingefuegt', await page.locator('#ptd-auth-brand').count() > 0);
    check('Verlaufsebene nicht vom Body verdeckt',
        (await page.evaluate(() => getComputedStyle(document.body).backgroundColor)) === 'rgba(0, 0, 0, 0)',
        await page.evaluate(() => getComputedStyle(document.body).backgroundColor));
    check('Login-Button als primary erkannt',
        (await page.getAttribute('form button[type="submit"]', 'data-ptd-btn')) === 'primary');
    await page.screenshot({ path: path.join(SHOTS, '01-login.png') });

    /* ---------- Dashboard ---------- */
    await page.goto(BASE + '/', { waitUntil: 'networkidle' });
    await page.waitForTimeout(700);
    check('Navigation getaggt', await page.locator('[data-ptd="nav"]').count() > 0);
    check('Nav-Aktionen getaggt', await page.locator('[data-ptd="nav-actions"]').count() > 0);
    check('Serverkacheln getaggt', await page.locator('[data-ptd="server-card"]').count(), await page.locator('[data-ptd="server-card"]').count());
    check('Begruessung sichtbar', await page.locator('#ptd-greeting').count() > 0);
    check('Fusszeile sichtbar', await page.locator('[data-ptd="footer"]').count() > 0);
    check('Einstellungsknopf sichtbar', await page.locator('#ptd-fab').isVisible());
    check('Schnellwechsler sichtbar', await page.locator('#ptd-switcher').count() > 0);
    await page.screenshot({ path: path.join(SHOTS, '02-dashboard.png') });

    /* ---------- Command-Palette ---------- */
    await page.keyboard.press('Control+k');
    await page.waitForTimeout(500);
    check('Palette offen', await page.locator('#ptd-palette').isVisible());
    await page.keyboard.type('lobby');
    await page.waitForTimeout(400);
    const firstItem = await page.locator('#ptd-palette .ptd-p-item .ptd-p-title').first().innerText().catch(() => '');
    check('Serversuche findet "Lobby Proxy"', /lobby/i.test(firstItem), firstItem);
    await page.screenshot({ path: path.join(SHOTS, '03-palette.png') });
    await page.keyboard.press('Escape');
    await page.waitForTimeout(300);
    check('Palette per Esc geschlossen', !(await page.locator('#ptd-palette').isVisible().catch(() => false)));

    /* ---------- Serverkonsole ---------- */
    await page.goto(BASE + '/server/a1b2c3d4', { waitUntil: 'domcontentloaded' });
    await page.waitForTimeout(900);
    check('Statuswechsel-Toast erschienen', await page.locator('#ptd-toasts .ptd-toast').count() > 0,
        await page.locator('#ptd-toasts .ptd-toast').count());
    await page.waitForTimeout(2000);
    check('Sub-Navigation getaggt', await page.locator('[data-ptd="subnav"]').count() > 0);
    check('Aktiver Reiter markiert', await page.locator('[data-ptd="subnav"] a[data-ptd-active="1"]').count() === 1);
    check('Konsole getaggt', await page.locator('[data-ptd="console"]').count() > 0);
    check('Konsolen-Toolbar eingehaengt', await page.locator('#ptd-console-bar').isVisible());
    check('Serverleiste eingehaengt', await page.locator('#ptd-serverbar').isVisible());

    const lines = await page.evaluate(() => window.PTD.store.lines.length);
    check('Konsolenzeilen ueber WebSocket empfangen', lines > 5, lines + ' Zeilen');
    const statsCount = await page.evaluate(() => window.PTD.store.stats.length);
    check('Statistikpunkte empfangen', statsCount > 3, statsCount + ' Punkte');
    check('Serverstatus erkannt', (await page.evaluate(() => window.PTD.store.state)) === 'running');
    check('ANSI-Codes entfernt', await page.evaluate(() =>
        window.PTD.store.lines.every((l) => l.text.indexOf(String.fromCharCode(27)) === -1)));
    check('Log-Level erkannt', await page.evaluate(() =>
        window.PTD.store.lines.some((l) => l.lvl === 'error') && window.PTD.store.lines.some((l) => l.lvl === 'warn')));

    check('Graphen gerendert', await page.locator('#ptd-charts .ptd-chart').count() === 4);
    const cpuPath = await page.getAttribute('#ptd-charts .ptd-chart[data-key="cpu"] .ptd-line-path', 'd');
    check('CPU-Kurve hat Daten', !!cpuPath && cpuPath.length > 20, (cpuPath || '').slice(0, 24) + '…');
    const memLabel = await page.locator('#ptd-charts .ptd-chart[data-key="mem"] .ptd-chart-value').innerText();
    check('RAM-Wert formatiert', /MiB|GiB/.test(memLabel), memLabel);
    const addr = await page.locator('#ptd-serverbar').innerText();
    check('Serveradresse angezeigt', /play\.example\.de:25565/.test(addr), addr.replace(/\n/g, ' | ').slice(0, 90));
    check('Titel zeigt Statussymbol', /^[●○◐◑⚠]/.test(await page.title()), await page.title());
    await page.screenshot({ path: path.join(SHOTS, '04-console.png') });

    /* ---------- Konsolensuche ---------- */
    await page.fill('#ptd-console-bar .ptd-csearch input', 'ERROR');
    await page.waitForTimeout(500);
    check('Log-Ansicht geoeffnet', await page.locator('#ptd-log-view.is-open').count() > 0);
    check('Treffer hervorgehoben', await page.locator('#ptd-log-view mark').count() > 0);
    await page.screenshot({ path: path.join(SHOTS, '05-console-search.png') });
    await page.fill('#ptd-console-bar .ptd-csearch input', '');
    await page.waitForTimeout(300);

    /* ---------- Einstellungen ---------- */
    await page.click('#ptd-fab');
    await page.waitForTimeout(500);
    check('Einstellungs-Drawer offen', await page.locator('#ptd-drawer.is-open').count() > 0);
    await page.screenshot({ path: path.join(SHOTS, '06-settings.png') });

    await page.click('#ptd-drawer .ptd-swatches .ptd-swatch:nth-child(4)');
    await page.waitForTimeout(400);
    check('Preset gewechselt (ember)', (await page.getAttribute('html', 'data-ptd-preset')) === 'ember');
    await page.screenshot({ path: path.join(SHOTS, '07-preset-ember.png') });

    await page.click('#ptd-drawer .ptd-seg button:nth-child(2)');
    await page.waitForTimeout(400);
    check('Hellmodus aktiv', (await page.getAttribute('html', 'data-ptd-mode')) === 'light');
    await page.screenshot({ path: path.join(SHOTS, '08-light-drawer.png') });
    await page.evaluate(() => { window.PTD.set('preset', 'ocean'); window.PTD.settingsPanel.close(); });
    await page.waitForTimeout(700);
    await page.screenshot({ path: path.join(SHOTS, '08-light.png') });
    const termBg = await page.evaluate(() => getComputedStyle(document.querySelector('[data-ptd=\"console\"]')).backgroundColor
        + '|' + getComputedStyle(document.querySelector('[data-ptd=\"console\"]')).backgroundImage.slice(0, 60));
    check('Terminal bleibt im Hellmodus dunkel', /rgb\(1[0-9], 1[0-9], 2[0-9]\)|10, 13, 21|14, 18, 28/.test(termBg), termBg);

    /* zuruecksetzen fuer den letzten Screenshot */
    await page.evaluate(() => { window.PTD.set('mode', 'dark'); window.PTD.set('preset', 'nebula'); });
    await page.waitForTimeout(300);
    await page.keyboard.press('Escape');
    await page.waitForTimeout(200);

    /* ---------- Persistenz ---------- */
    await page.evaluate(() => { window.PTD.set('preset', 'forest'); window.PTD.set('compact', true); });
    await page.reload({ waitUntil: 'networkidle' });
    await page.waitForTimeout(600);
    check('Einstellungen ueberleben Neuladen',
        (await page.getAttribute('html', 'data-ptd-preset')) === 'forest' &&
        (await page.getAttribute('html', 'data-ptd-compact')) === '1');
    await page.evaluate(() => { window.PTD.reset(); });

    /* ---------- Tastenkuerzel ---------- */
    await page.keyboard.press('Control+/');
    await page.waitForTimeout(400);
    check('Tastenkuerzel-Uebersicht offen', await page.locator('#ptd-keys').isVisible());
    await page.screenshot({ path: path.join(SHOTS, '09-shortcuts.png') });
    await page.keyboard.press('Escape');

    /* ---------- SPA-Navigation ---------- */
    await page.waitForTimeout(300);
    await page.click('[data-ptd="subnav"] a[href$="/files"]');
    await page.waitForTimeout(700);
    check('Route gewechselt', (await page.evaluate(() => window.PTD.route.sub)) === 'files');
    check('Toolbar auf anderer Seite entfernt', await page.locator('#ptd-console-bar').count() === 0);
    check('Aktiver Reiter nachgezogen',
        (await page.getAttribute('[data-ptd="subnav"] a[data-ptd-active="1"]', 'href')) === '/server/a1b2c3d4/files');

    /* ---------- Fehlerfreiheit ---------- */
    const nebulaErrors = errors.filter((e) => !/favicon|Failed to load resource/i.test(e));
    check('Keine JavaScript-Fehler', nebulaErrors.length === 0, nebulaErrors.slice(0, 3).join(' | '));

    await browser.close();

    const failed = results.filter((r) => !r.ok);
    console.log('\n' + (results.length - failed.length) + '/' + results.length + ' Pruefungen bestanden');
    if (failed.length) {
        console.log('Fehlgeschlagen:');
        failed.forEach((f) => console.log('  - ' + f.name + (f.extra ? '  [' + f.extra + ']' : '')));
        process.exit(1);
    }
})().catch((e) => { console.error(e); process.exit(1); });
