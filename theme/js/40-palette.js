/* =========================================================================
   Nebula · 40-palette.js
   Command-Palette (Strg/Cmd + K): Server suchen, springen, Aktionen
   ausloesen und das Design umschalten.
   ========================================================================= */

(function () {
    'use strict';
    var PTD = window.PTD;
    if (!PTD) return;

    var el = PTD.el, qs = PTD.qs, icon = PTD.icon;
    var overlay = null, box = null, input = null, list = null;
    var items = [], cursor = 0, servers = [], loaded = false;

    /* =====================================================================
       SPA-taugliche Navigation
       ===================================================================== */

    function navigate(href) {
        if (!href) return;
        if (href.indexOf('/admin') === 0) { window.location.assign(href); return; }

        var existing = qs('a[href="' + href.replace(/"/g, '\\"') + '"]');
        if (existing) { existing.click(); return; }

        var before = PTD._lastScanAt || 0;
        try {
            window.history.pushState({}, '', href);
            window.dispatchEvent(new PopStateEvent('popstate', { state: {} }));
        } catch (e) {
            window.location.assign(href);
            return;
        }
        PTD.refreshRoute();
        setTimeout(function () {
            if ((PTD._lastScanAt || 0) === before && location.pathname === href) {
                window.location.assign(href);
            }
        }, 700);
    }

    /* =====================================================================
       Fuzzy-Suche
       ===================================================================== */

    function score(needle, hay) {
        if (!needle) return 1;
        needle = needle.toLowerCase();
        hay = hay.toLowerCase();
        var idx = hay.indexOf(needle);
        if (idx === 0) return 1000;
        if (idx > 0) return 700 - idx;
        var n = 0, s = 0, last = -1;
        for (var i = 0; i < hay.length && n < needle.length; i++) {
            if (hay[i] === needle[n]) {
                s += (last === i - 1) ? 6 : 2;
                last = i; n++;
            }
        }
        return n === needle.length ? s : -1;
    }

    /* =====================================================================
       Datenquellen
       ===================================================================== */

    function loadServers() {
        var cached = PTD.cache.get('servers', 60000);
        if (cached) { servers = cached; loaded = true; render(); }
        PTD.api('/api/client?per_page=100').then(function (res) {
            if (!res || !res.data) return;
            servers = res.data.map(function (row) {
                var a = row.attributes || {};
                return {
                    id: a.identifier,
                    name: a.name,
                    node: a.node,
                    ip: a.relationships && a.relationships.allocations && a.relationships.allocations.data[0]
                        ? (a.relationships.allocations.data[0].attributes.ip_alias ||
                           a.relationships.allocations.data[0].attributes.ip) + ':' +
                          a.relationships.allocations.data[0].attributes.port
                        : '',
                    suspended: !!a.is_suspended
                };
            });
            loaded = true;
            PTD.cache.set('servers', servers);
            render();
        }).catch(function () { loaded = true; render(); });
    }

    var SERVER_TABS = [
        { path: '', label: 'Konsole', ico: 'terminal' },
        { path: '/files', label: 'Dateien', ico: 'folder' },
        { path: '/databases', label: 'Datenbanken', ico: 'database' },
        { path: '/schedules', label: 'Zeitplaene', ico: 'clock' },
        { path: '/users', label: 'Benutzer', ico: 'users' },
        { path: '/backups', label: 'Backups', ico: 'archive' },
        { path: '/network', label: 'Netzwerk', ico: 'network' },
        { path: '/startup', label: 'Startparameter', ico: 'sliders' },
        { path: '/settings', label: 'Einstellungen', ico: 'settings' },
        { path: '/activity', label: 'Aktivitaet', ico: 'activity' }
    ];

    var GLOBAL_LINKS = [
        { href: '/', label: 'Dashboard', ico: 'home' },
        { href: '/account', label: 'Kontoeinstellungen', ico: 'user' },
        { href: '/account/api', label: 'API-Zugangsdaten', ico: 'key' },
        { href: '/account/ssh', label: 'SSH-Schluessel', ico: 'shield' },
        { href: '/account/activity', label: 'Kontoaktivitaet', ico: 'activity' }
    ];

    function power(signal) {
        var id = PTD.route.server;
        if (!id) return;
        PTD.api('/api/client/servers/' + id + '/power', { method: 'POST', body: { signal: signal } })
            .then(function () {
                PTD.toast({ type: 'ok', title: 'Befehl gesendet', msg: signal });
            })
            .catch(function (e) {
                PTD.toast({ type: 'danger', title: 'Fehlgeschlagen', msg: 'Signal "' + signal + '" (' + (e.status || 'Netzwerkfehler') + ')' });
            });
    }

    function buildItems(query) {
        var out = [];
        var onServer = PTD.route.page === 'server' && PTD.route.server;

        if (onServer) {
            SERVER_TABS.forEach(function (t) {
                out.push({
                    group: 'Aktueller Server', ico: t.ico, title: t.label,
                    sub: '/server/' + PTD.route.server + t.path,
                    run: function () { navigate('/server/' + PTD.route.server + t.path); }
                });
            });
            [['start', 'Server starten', 'play'],
             ['restart', 'Server neu starten', 'restart'],
             ['stop', 'Server stoppen', 'stop'],
             ['kill', 'Prozess beenden (Kill)', 'power']].forEach(function (p) {
                out.push({
                    group: 'Aktionen', ico: p[2], title: p[1], sub: 'Signal: ' + p[0],
                    run: function () {
                        if (p[0] === 'kill' && !window.confirm('Prozess wirklich hart beenden?')) return;
                        power(p[0]);
                    }
                });
            });
        }

        servers.forEach(function (s) {
            out.push({
                group: 'Server', ico: 'server', title: s.name,
                sub: (s.ip ? s.ip + '  ·  ' : '') + (s.node || '') + (s.suspended ? '  ·  gesperrt' : ''),
                run: function () { navigate('/server/' + s.id); }
            });
        });

        GLOBAL_LINKS.forEach(function (l) {
            out.push({ group: 'Navigation', ico: l.ico, title: l.label, sub: l.href, run: function () { navigate(l.href); } });
        });

        if (qs('a[href^="/admin"]')) {
            out.push({ group: 'Navigation', ico: 'shield', title: 'Administration', sub: '/admin', run: function () { navigate('/admin'); } });
        }

        ['nebula', 'ocean', 'forest', 'ember', 'rose', 'solar', 'midnight', 'mono'].forEach(function (p) {
            out.push({
                group: 'Design', ico: 'wand', title: 'Preset: ' + p.charAt(0).toUpperCase() + p.slice(1),
                sub: 'Farbschema wechseln',
                run: function () { PTD.settings.accent = ''; PTD.set('preset', p); PTD.toast({ type: 'ok', title: 'Preset aktiv', msg: p }); }
            });
        });

        out.push({
            group: 'Design', ico: PTD.get('mode') === 'light' ? 'moon' : 'sun',
            title: PTD.get('mode') === 'light' ? 'Dunkelmodus' : 'Hellmodus',
            sub: 'Farbschema umschalten',
            run: function () { PTD.set('mode', PTD.get('mode') === 'light' ? 'dark' : 'light'); }
        });
        out.push({
            group: 'Design', ico: 'settings', title: 'Nebula-Einstellungen', sub: 'Alle Optionen',
            run: function () { close(); if (PTD.settingsPanel) PTD.settingsPanel.open(); }
        });
        out.push({
            group: 'Design', ico: 'keyboard', title: 'Tastenkuerzel anzeigen', sub: 'Strg + /',
            run: function () { close(); if (PTD.shortcuts) PTD.shortcuts.show(); }
        });

        if (!query) return out;

        return out.map(function (it) {
            var s = Math.max(score(query, it.title), score(query, it.sub || '') - 200, score(query, it.group) - 400);
            return { it: it, s: s };
        }).filter(function (x) { return x.s > 0; })
          .sort(function (a, b) { return b.s - a.s; })
          .map(function (x) { return x.it; });
    }

    /* =====================================================================
       Darstellung
       ===================================================================== */

    function render() {
        if (!list) return;
        var q = (input.value || '').trim();
        items = buildItems(q).slice(0, 60);
        cursor = Math.min(cursor, Math.max(items.length - 1, 0));
        list.innerHTML = '';

        if (!items.length) {
            list.appendChild(el('div', { class: 'ptd-p-empty', text: loaded ? 'Keine Treffer.' : 'Lade Server …' }));
            return;
        }

        var lastGroup = null;
        items.forEach(function (it, i) {
            if (it.group !== lastGroup) {
                lastGroup = it.group;
                list.appendChild(el('div', { class: 'ptd-p-group', text: it.group }));
            }
            var node = el('div', {
                class: 'ptd-p-item', role: 'option',
                'aria-selected': i === cursor ? 'true' : 'false',
                'data-i': i
            }, [
                el('span', { class: 'ptd-p-ico', html: icon(it.ico, 14) }),
                el('span', { class: 'ptd-p-txt' }, [
                    el('div', { class: 'ptd-p-title', text: it.title }),
                    it.sub ? el('div', { class: 'ptd-p-sub', text: it.sub }) : null
                ])
            ]);
            node.addEventListener('mousemove', function () { select(i); });
            node.addEventListener('click', function () { run(i); });
            list.appendChild(node);
        });
        scrollToCursor();
    }

    function select(i) {
        if (i === cursor) return;
        cursor = i;
        PTD.qsa('.ptd-p-item', list).forEach(function (n) {
            n.setAttribute('aria-selected', Number(n.getAttribute('data-i')) === cursor ? 'true' : 'false');
        });
    }

    function scrollToCursor() {
        var node = qs('.ptd-p-item[aria-selected="true"]', list);
        if (node && node.scrollIntoView) node.scrollIntoView({ block: 'nearest' });
    }

    function move(delta) {
        if (!items.length) return;
        var next = (cursor + delta + items.length) % items.length;
        select(next);
        scrollToCursor();
    }

    function run(i) {
        var it = items[i === undefined ? cursor : i];
        if (!it) return;
        close();
        setTimeout(function () { it.run(); }, 10);
    }

    /* =====================================================================
       Auf- und Zuklappen
       ===================================================================== */

    function build() {
        input = el('input', {
            type: 'text', placeholder: 'Server, Seite oder Aktion suchen …',
            spellcheck: 'false', autocomplete: 'off', 'aria-label': 'Suche'
        });
        list = el('div', { class: 'ptd-p-list', role: 'listbox' });

        box = el('div', { id: 'ptd-palette' }, [
            el('div', { class: 'ptd-p-input' }, [
                el('span', { html: icon('search', 17) }),
                input
            ]),
            list,
            el('div', { class: 'ptd-p-foot' }, [
                el('span', { html: '<b class="ptd-kbd">&uarr;</b><b class="ptd-kbd">&darr;</b> Navigieren' }),
                el('span', { html: '<b class="ptd-kbd">&crarr;</b> Auswaehlen' }),
                el('span', { html: '<b class="ptd-kbd">Esc</b> Schliessen' })
            ])
        ]);

        overlay = el('div', { class: 'ptd-overlay', id: 'ptd-palette-overlay' }, [box]);
        overlay.addEventListener('click', function (e) { if (e.target === overlay) close(); });

        input.addEventListener('input', function () { cursor = 0; render(); });
        input.addEventListener('keydown', function (e) {
            if (e.key === 'ArrowDown') { e.preventDefault(); move(1); }
            else if (e.key === 'ArrowUp') { e.preventDefault(); move(-1); }
            else if (e.key === 'Enter') { e.preventDefault(); run(); }
            else if (e.key === 'Escape') { e.preventDefault(); close(); }
            else if (e.key === 'Tab') { e.preventDefault(); move(e.shiftKey ? -1 : 1); }
        });

        document.body.appendChild(overlay);
    }

    function open() {
        if (!PTD.get('modules.palette')) return;
        if (!overlay) build();
        overlay.classList.add('is-open');
        input.value = '';
        cursor = 0;
        render();
        if (!loaded) loadServers();
        setTimeout(function () { input.focus(); }, 20);
    }

    function close() {
        if (overlay) overlay.classList.remove('is-open');
    }

    function isOpen() { return !!overlay && overlay.classList.contains('is-open'); }

    PTD.palette = { open: open, close: close, toggle: function () { isOpen() ? close() : open(); }, isOpen: isOpen, navigate: navigate };
    PTD.navigate = navigate;
})();
