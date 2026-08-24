/* =========================================================================
   Nebula · 40-palette.js
   Befehlspalette (Strg/Cmd + K): Server finden, Seiten wechseln, Aktionen
   ausloesen, Kurzbefehle senden und das Design umschalten.
   ========================================================================= */

(function () {
    'use strict';
    var PTD = window.PTD;
    if (!PTD) return;

    var el = PTD.el, qs = PTD.qs, icon = PTD.icon;
    var overlay = null, box = null, input = null, list = null, scope = null;
    var items = [], cursor = 0;

    /* =====================================================================
       Navigation innerhalb der Anwendung
       ===================================================================== */

    function navigate(href) {
        if (!href) return;
        if (href.indexOf('/admin') === 0) { window.location.assign(href); return; }

        var existing = qs('a[href="' + href.replace(/"/g, '\\"') + '"]:not(.ptd-rail-item)');
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
       Bewertung und Hervorhebung
       ===================================================================== */

    function score(needle, hay) {
        if (!needle) return 1;
        var n = needle.toLowerCase(), h = String(hay).toLowerCase();
        var idx = h.indexOf(n);
        if (idx === 0) return 1000;
        if (idx > 0) return 700 - idx;
        var k = 0, s = 0, last = -1;
        for (var i = 0; i < h.length && k < n.length; i++) {
            if (h[i] === n[k]) { s += (last === i - 1) ? 6 : 2; last = i; k++; }
        }
        return k === n.length ? s : -1;
    }

    function highlight(text, needle) {
        var safe = PTD.escapeHtml(text);
        if (!needle) return safe;
        var i = text.toLowerCase().indexOf(needle.toLowerCase());
        if (i < 0) return safe;
        return PTD.escapeHtml(text.slice(0, i)) +
            '<mark>' + PTD.escapeHtml(text.slice(i, i + needle.length)) + '</mark>' +
            PTD.escapeHtml(text.slice(i + needle.length));
    }

    /* =====================================================================
       Eintraege
       ===================================================================== */

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

    function power(signal, confirmText) {
        var id = PTD.route.server;
        if (!id) return;
        if (confirmText && !window.confirm(confirmText)) return;
        PTD.api('/api/client/servers/' + id + '/power', { method: 'POST', body: { signal: signal } })
            .then(function () { PTD.toast({ type: 'ok', title: 'Befehl gesendet', msg: signal }); })
            .catch(function (e) {
                PTD.toast({ type: 'danger', title: 'Fehlgeschlagen', msg: 'HTTP ' + (e.status || '?') });
            });
    }

    function servers() { return (PTD.rail && PTD.rail.servers()) || PTD.cache.get('servers', 120000) || []; }

    function liveState(id) {
        var l = PTD.overview && PTD.overview.live()[id];
        if (l) return l.state;
        var s = servers().filter(function (x) { return x.id === id; })[0];
        return s ? s.state : 'offline';
    }

    function build(query) {
        var out = [];
        var onServer = PTD.route.page === 'server' && PTD.route.server;
        var list = servers();

        if (onServer) {
            SERVER_TABS.forEach(function (t) {
                out.push({
                    group: 'Dieser Server', ico: t.ico, title: t.label,
                    sub: '/server/' + PTD.route.server + t.path,
                    run: function () { navigate('/server/' + PTD.route.server + t.path); }
                });
            });
            [['start', 'Server starten', 'play', null],
             ['restart', 'Server neu starten', 'restart', null],
             ['stop', 'Server stoppen', 'stop', null],
             ['kill', 'Prozess beenden (Kill)', 'power', 'Prozess wirklich hart beenden?']
            ].forEach(function (p) {
                out.push({
                    group: 'Aktionen', ico: p[2], title: p[1], sub: 'Signal: ' + p[0],
                    run: function () { power(p[0], p[3]); }
                });
            });

            var snips = (PTD.get('snippets') || {})[PTD.route.server] || [];
            snips.forEach(function (cmd) {
                out.push({
                    group: 'Kurzbefehle', ico: 'zap', title: cmd, sub: 'An die Konsole senden',
                    run: function () { if (PTD.console) PTD.console.run(cmd); }
                });
            });
        }

        var favs = PTD.get('favorites') || [];
        var recents = PTD.get('recents') || [];

        if (!query && recents.length) {
            recents.slice(0, 4).forEach(function (id) {
                var s = list.filter(function (x) { return x.id === id; })[0];
                if (!s || s.id === PTD.route.server) return;
                out.push(serverItem(s, 'Zuletzt besucht'));
            });
        }

        list.forEach(function (s) {
            out.push(serverItem(s, favs.indexOf(s.id) > -1 ? 'Angeheftet' : 'Server'));
        });

        GLOBAL_LINKS.forEach(function (l) {
            out.push({ group: 'Navigation', ico: l.ico, title: l.label, sub: l.href, run: function () { navigate(l.href); } });
        });
        if (qs('#navigation a[href^="/admin"]')) {
            out.push({ group: 'Navigation', ico: 'shield', title: 'Administration', sub: '/admin', run: function () { navigate('/admin'); } });
        }

        PTD.presets.forEach(function (p) {
            out.push({
                group: 'Design', ico: 'wand', title: 'Preset: ' + p.charAt(0).toUpperCase() + p.slice(1),
                sub: 'Farbschema wechseln',
                run: function () { PTD.settings.accent = ''; PTD.set('preset', p); PTD.toast({ type: 'ok', title: 'Preset aktiv', msg: p }); }
            });
        });
        out.push({
            group: 'Design', ico: PTD.get('mode') === 'light' ? 'moon' : 'sun',
            title: PTD.get('mode') === 'light' ? 'Dunkelmodus' : 'Hellmodus', sub: 'Farbschema umschalten',
            run: function () { PTD.set('mode', PTD.get('mode') === 'light' ? 'dark' : 'light'); }
        });
        out.push({
            group: 'Design', ico: 'panelLeft',
            title: PTD.get('rail') === 'mini' ? 'Schiene ausklappen' : 'Schiene einklappen',
            sub: 'Seitennavigation', run: function () { PTD.set('rail', PTD.get('rail') === 'mini' ? 'full' : 'mini'); }
        });
        out.push({ group: 'Design', ico: 'settings', title: 'Nebula-Einstellungen', sub: 'Alle Optionen', run: function () { close(); PTD.settingsPanel.open(); } });
        out.push({ group: 'Design', ico: 'keyboard', title: 'Tastenkuerzel', sub: 'Strg + /', run: function () { close(); if (PTD.shortcuts) PTD.shortcuts.show(); } });

        if (!query) return out;

        return out.map(function (it) {
            var s = Math.max(score(query, it.title), score(query, it.sub || '') - 200, score(query, it.group) - 400);
            return { it: it, s: s };
        }).filter(function (x) { return x.s > 0; })
          .sort(function (a, b) { return b.s - a.s; })
          .map(function (x) { return x.it; });
    }

    function serverItem(s, group) {
        var tag = PTD.tagOf ? PTD.tagOf(s.id, s.name) : { color: PTD.autoColor(s.id), label: PTD.fmt.initials(s.name) };
        return {
            group: group, initials: tag.label, color: tag.color, state: liveState(s.id),
            title: s.name,
            sub: (s.address ? s.address + '  ·  ' : '') + (s.node || '') + (s.suspended ? '  ·  gesperrt' : ''),
            run: function () { navigate('/server/' + s.id); }
        };
    }

    /* =====================================================================
       Darstellung
       ===================================================================== */

    function render() {
        if (!list) return;
        var q = (input.value || '').trim();
        items = build(q).slice(0, 70);
        cursor = Math.min(cursor, Math.max(items.length - 1, 0));
        list.innerHTML = '';

        var onServer = PTD.route.page === 'server' && PTD.route.server;
        scope.style.display = onServer ? '' : 'none';
        if (onServer) {
            var s = servers().filter(function (x) { return x.id === PTD.route.server; })[0];
            scope.textContent = s ? s.name : PTD.route.server;
        }

        if (!items.length) {
            list.appendChild(el('div', { class: 'ptd-p-empty', text: 'Keine Treffer.' }));
            return;
        }

        var lastGroup = null;
        items.forEach(function (it, i) {
            if (it.group !== lastGroup) {
                lastGroup = it.group;
                list.appendChild(el('div', { class: 'ptd-p-group', text: it.group }));
            }
            var ico = el('span', { class: 'ptd-p-ico', style: it.color ? { background: 'color-mix(in srgb,' + it.color + ' 22%, transparent)', color: it.color } : null });
            if (it.initials) ico.textContent = it.initials;
            else ico.innerHTML = icon(it.ico, 14);

            var node = el('div', {
                class: 'ptd-p-item', role: 'option', 'data-i': i,
                'data-state': it.state || null,
                'aria-selected': i === cursor ? 'true' : 'false'
            }, [ico]);

            var txt = el('span', { class: 'ptd-p-txt' });
            txt.appendChild(el('div', { class: 'ptd-p-title', html: highlight(it.title, q) }));
            if (it.sub) txt.appendChild(el('div', { class: 'ptd-p-sub', text: it.sub }));
            node.appendChild(txt);

            if (it.state) node.appendChild(el('span', { class: 'ptd-p-state' }));
            node.appendChild(el('span', { class: 'ptd-p-hint', html: '<b class="ptd-kbd">&crarr;</b>' }));

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
        select((cursor + delta + items.length) % items.length);
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

    function buildUi() {
        input = el('input', {
            type: 'text', placeholder: 'Server, Seite oder Aktion …',
            spellcheck: 'false', autocomplete: 'off', 'aria-label': 'Suche'
        });
        scope = el('span', { class: 'ptd-p-scope' });
        list = el('div', { class: 'ptd-p-list', role: 'listbox' });

        box = el('div', { id: 'ptd-palette' }, [
            el('div', { class: 'ptd-p-input' }, [
                el('span', { html: icon('search', 16) }),
                input, scope
            ]),
            list,
            el('div', { class: 'ptd-p-foot' }, [
                el('span', { html: '<b class="ptd-kbd">&uarr;</b><b class="ptd-kbd">&darr;</b> Navigieren' }),
                el('span', { html: '<b class="ptd-kbd">&crarr;</b> Ausfuehren' }),
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
        if (!overlay) buildUi();
        overlay.classList.add('is-open');
        input.value = '';
        cursor = 0;
        render();
        if (!servers().length && PTD.rail) PTD.rail.reload();
        setTimeout(function () { input.focus(); }, 20);
    }

    function close() { if (overlay) overlay.classList.remove('is-open'); }
    function isOpen() { return !!overlay && overlay.classList.contains('is-open'); }

    PTD.bus.on('servers', function () { if (isOpen()) render(); });

    PTD.palette = { open: open, close: close, toggle: function () { isOpen() ? close() : open(); }, isOpen: isOpen, navigate: navigate };
    PTD.navigate = navigate;
})();
