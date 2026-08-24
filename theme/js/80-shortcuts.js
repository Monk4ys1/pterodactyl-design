/* =========================================================================
   Nebula · 80-shortcuts.js
   Globale Tastenkuerzel und die Uebersicht dazu (Strg + /).
   ========================================================================= */

(function () {
    'use strict';
    var PTD = window.PTD;
    if (!PTD) return;

    var el = PTD.el, qs = PTD.qs;
    var overlay = null;
    var chord = null, chordTimer = null;

    var GROUPS = [
        {
            title: 'Allgemein',
            keys: [
                { k: ['Strg', 'K'], d: 'Befehlspalette' },
                { k: ['Strg', '/'], d: 'Diese Uebersicht' },
                { k: ['Strg', 'B'], d: 'Schiene ein-/ausklappen' },
                { k: ['Strg', 'Umschalt', 'E'], d: 'Nebula-Einstellungen' },
                { k: ['Strg', 'Umschalt', 'L'], d: 'Hell / Dunkel' },
                { k: ['Esc'], d: 'Overlay schliessen' }
            ]
        },
        {
            title: 'Springen  (g, dann …)',
            keys: [
                { k: ['g', 'd'], d: 'Dashboard' },
                { k: ['g', 'c'], d: 'Konsole' },
                { k: ['g', 'f'], d: 'Dateien' },
                { k: ['g', 'b'], d: 'Backups' },
                { k: ['g', 'n'], d: 'Netzwerk' },
                { k: ['g', 'u'], d: 'Benutzer' },
                { k: ['g', 't'], d: 'Zeitplaene' },
                { k: ['g', 's'], d: 'Servereinstellungen' },
                { k: ['g', 'a'], d: 'Konto' }
            ]
        },
        {
            title: 'Server steuern',
            keys: [
                { k: ['Alt', 'S'], d: 'Starten' },
                { k: ['Alt', 'R'], d: 'Neu starten' },
                { k: ['Alt', 'X'], d: 'Stoppen' },
                { k: ['Alt', 'K'], d: 'Prozess beenden (Kill)' }
            ]
        },
        {
            title: 'Konsole',
            keys: [
                { k: ['Strg', 'Umschalt', 'F'], d: 'Vollbild' },
                { k: ['Strg', 'Umschalt', 'D'], d: 'Mini-Konsole' },
                { k: ['Strg', 'Umschalt', 'Z'], d: 'Fokusmodus' },
                { k: ['Alt', '1'], d: 'Erster Reiter' },
                { k: ['Alt', '2 – 9'], d: 'Weitere Reiter' }
            ]
        }
    ];

    /* =====================================================================
       Uebersicht
       ===================================================================== */

    function build() {
        var grid = el('div', { class: 'ptd-k-grid' });
        GROUPS.forEach(function (g) {
            var col = el('div', {}, [el('h3', { text: g.title })]);
            g.keys.forEach(function (row) {
                col.appendChild(el('div', { class: 'ptd-k-row' }, [
                    el('span', { text: row.d }),
                    el('span', { class: 'ptd-k-keys', html: row.k.map(function (k) { return '<b class="ptd-kbd">' + k + '</b>'; }).join('') })
                ]));
            });
            grid.appendChild(col);
        });

        var boxNode = el('div', { id: 'ptd-keys', role: 'dialog', 'aria-label': 'Tastenkuerzel' }, [
            el('h2', { text: 'Tastenkuerzel' }),
            grid
        ]);

        overlay = el('div', { class: 'ptd-overlay', id: 'ptd-keys-overlay' }, [boxNode]);
        overlay.addEventListener('click', function (e) { if (e.target === overlay) hide(); });
        document.body.appendChild(overlay);
    }

    function show() {
        if (!overlay) build();
        overlay.classList.add('is-open');
    }
    function hide() { if (overlay) overlay.classList.remove('is-open'); }
    function visible() { return !!overlay && overlay.classList.contains('is-open'); }

    /* =====================================================================
       Aktionen
       ===================================================================== */

    function goServer(sub) {
        if (!PTD.route.server) { PTD.toast({ type: 'warn', title: 'Kein Server geoeffnet' }); return; }
        PTD.navigate('/server/' + PTD.route.server + sub);
    }

    function power(signal, confirmText) {
        if (!PTD.route.server) return;
        if (confirmText && !window.confirm(confirmText)) return;
        PTD.api('/api/client/servers/' + PTD.route.server + '/power', { method: 'POST', body: { signal: signal } })
            .then(function () { PTD.toast({ type: 'ok', title: 'Befehl gesendet', msg: signal }); })
            .catch(function (e) { PTD.toast({ type: 'danger', title: 'Fehlgeschlagen', msg: String(e.status || 'Netzwerkfehler') }); });
    }

    function subTab(n) {
        var inner = qs('[data-ptd="subnav"] [data-ptd-sub="inner"]') || qs('[data-ptd="subnav"] > div');
        if (!inner) return;
        var links = PTD.qsa('a', inner);
        if (links[n - 1]) links[n - 1].click();
    }

    function closeTopOverlay() {
        if (PTD.palette && PTD.palette.isOpen()) { PTD.palette.close(); return true; }
        if (visible()) { hide(); return true; }
        if (PTD.settingsPanel && PTD.settingsPanel.isOpen()) { PTD.settingsPanel.close(); return true; }
        if (PTD.tags) PTD.tags.close();
        if (document.documentElement.getAttribute('data-ptd-railopen') === '1') {
            PTD.rail.closeMobile(); return true;
        }
        if (document.documentElement.getAttribute('data-ptd-focus') === '1') {
            PTD.rail.toggleFocus(); return true;
        }
        if (document.documentElement.getAttribute('data-ptd-console') === 'full') {
            document.documentElement.removeAttribute('data-ptd-console');
            setTimeout(function () { window.dispatchEvent(new Event('resize')); }, 60);
            return true;
        }
        return false;
    }

    /* =====================================================================
       Tastaturauswertung
       ===================================================================== */

    function isTyping(e) {
        var t = e.target;
        if (!t) return false;
        var tag = (t.tagName || '').toLowerCase();
        if (tag === 'input' || tag === 'textarea' || tag === 'select') return true;
        if (t.isContentEditable) return true;
        if (t.closest && t.closest('.xterm')) return true;
        return false;
    }

    document.addEventListener('keydown', function (e) {
        var mod = e.ctrlKey || e.metaKey;

        if (e.key === 'Escape') {
            if (closeTopOverlay()) e.preventDefault();
            return;
        }

        /* Command-Palette funktioniert auch im Eingabefeld */
        if (mod && !e.altKey && (e.key === 'k' || e.key === 'K')) {
            e.preventDefault();
            if (PTD.palette) PTD.palette.toggle();
            return;
        }

        if (!PTD.get('modules.shortcuts')) return;

        if (mod && e.key === '/') { e.preventDefault(); visible() ? hide() : show(); return; }

        if (mod && e.shiftKey && (e.key === 'E' || e.key === 'e')) {
            e.preventDefault();
            if (PTD.settingsPanel) PTD.settingsPanel.toggle();
            return;
        }
        if (mod && e.shiftKey && (e.key === 'L' || e.key === 'l')) {
            e.preventDefault();
            PTD.set('mode', PTD.get('mode') === 'light' ? 'dark' : 'light');
            return;
        }
        if (mod && !e.shiftKey && !e.altKey && (e.key === 'b' || e.key === 'B')) {
            e.preventDefault();
            PTD.set('rail', PTD.get('rail') === 'mini' ? 'full' : 'mini');
            return;
        }
        if (mod && e.shiftKey && (e.key === 'D' || e.key === 'd')) {
            if (PTD.route.page !== 'server') return;
            e.preventDefault();
            if (PTD.dock) PTD.dock.toggle();
            return;
        }
        if (mod && e.shiftKey && (e.key === 'Z' || e.key === 'z')) {
            e.preventDefault();
            if (PTD.rail) PTD.rail.toggleFocus();
            return;
        }
        if (mod && e.shiftKey && (e.key === 'F' || e.key === 'f')) {
            if (PTD.route.page !== 'server') return;
            e.preventDefault();
            var h = document.documentElement;
            if (h.getAttribute('data-ptd-console') === 'full') h.removeAttribute('data-ptd-console');
            else h.setAttribute('data-ptd-console', 'full');
            setTimeout(function () { window.dispatchEvent(new Event('resize')); }, 60);
            return;
        }

        if (isTyping(e)) return;

        if (e.altKey && !mod && /^[1-9]$/.test(e.key)) { e.preventDefault(); subTab(Number(e.key)); return; }

        if (e.altKey && !mod) {
            var k = e.key.toLowerCase();
            if (k === 's') { e.preventDefault(); power('start'); return; }
            if (k === 'r') { e.preventDefault(); power('restart'); return; }
            if (k === 'x') { e.preventDefault(); power('stop'); return; }
            if (k === 'k') { e.preventDefault(); power('kill', 'Prozess wirklich hart beenden?'); return; }
        }

        if (mod || e.altKey) return;

        if (e.key === '?') { e.preventDefault(); visible() ? hide() : show(); return; }

        /* Sequenz  g + Taste */
        if (chord === 'g') {
            clearTimeout(chordTimer);
            chord = null;
            var key = e.key.toLowerCase();
            var map = {
                d: function () { PTD.navigate('/'); },
                a: function () { PTD.navigate('/account'); },
                c: function () { goServer(''); },
                f: function () { goServer('/files'); },
                b: function () { goServer('/backups'); },
                n: function () { goServer('/network'); },
                u: function () { goServer('/users'); },
                t: function () { goServer('/schedules'); },
                s: function () { goServer('/settings'); }
            };
            if (map[key]) { e.preventDefault(); map[key](); }
            return;
        }

        if (e.key === 'g') {
            chord = 'g';
            clearTimeout(chordTimer);
            chordTimer = setTimeout(function () { chord = null; }, 1200);
        }
    }, true);

    PTD.shortcuts = { show: show, hide: hide, toggle: function () { visible() ? hide() : show(); } };
})();
