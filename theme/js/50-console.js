/* =========================================================================
   Nebula · 50-console.js
   Werkzeugleiste ueber der Serverkonsole: Volltextsuche, Log-Level-Filter,
   Zeitstempel, Kopieren, Download, Vollbild und Statusanzeige.
   Datengrundlage ist der in 00-boot.js mitgelesene Wings-Datenstrom.
   ========================================================================= */

(function () {
    'use strict';
    var PTD = window.PTD;
    if (!PTD) return;

    var el = PTD.el, qs = PTD.qs, icon = PTD.icon;

    var bar = null, view = null, box = null;
    var query = '', filter = 'all', autoscroll = true, viewOpen = false;
    var hitsEl = null, countEl = null, stateEl = null;
    var renderQueued = false;

    /* =====================================================================
       Sichtbarkeit
       ===================================================================== */

    function shouldMount() {
        if (!PTD.get('modules.console')) return false;
        if (PTD.route.page !== 'server') return false;
        return !!(qs('[data-ptd="console"]'));
    }

    /* =====================================================================
       Aufbau der Leiste
       ===================================================================== */

    function cbtn(label, ico, title, handler, pressed) {
        var b = el('button', {
            class: 'ptd-cbtn', type: 'button', title: title || label,
            'aria-pressed': pressed === undefined ? null : (pressed ? 'true' : 'false')
        }, []);
        if (ico) b.insertAdjacentHTML('beforeend', icon(ico, 13));
        if (label) b.appendChild(el('span', { text: label }));
        b.addEventListener('click', function () { handler(b); });
        return b;
    }

    function build() {
        var search = el('input', {
            type: 'search', placeholder: 'Konsole durchsuchen …',
            spellcheck: 'false', 'aria-label': 'Konsole durchsuchen'
        });
        search.addEventListener('input', PTD.debounce(function () {
            query = search.value.trim();
            viewOpen = !!query || filter !== 'all';
            paint();
        }, 130));
        search.addEventListener('keydown', function (e) {
            if (e.key === 'Escape') { search.value = ''; query = ''; viewOpen = filter !== 'all'; paint(); }
        });

        hitsEl = el('span', { class: 'ptd-chits', text: '' });

        var filterBtn = cbtn('Alle', 'filter', 'Log-Level filtern', function (b) {
            filter = filter === 'all' ? 'error' : filter === 'error' ? 'warn' : 'all';
            b.lastChild.textContent = filter === 'all' ? 'Alle' : filter === 'error' ? 'Fehler' : 'Warnungen';
            b.setAttribute('aria-pressed', filter === 'all' ? 'false' : 'true');
            viewOpen = !!query || filter !== 'all';
            paint();
        }, false);

        var bufferBtn = cbtn('Puffer', 'terminal', 'Mitgelesenen Puffer ein-/ausblenden', function (b) {
            viewOpen = !viewOpen;
            b.setAttribute('aria-pressed', viewOpen ? 'true' : 'false');
            paint();
        }, false);

        var tsBtn = cbtn('Zeit', 'clock', 'Zeitstempel anzeigen', function (b) {
            var v = !PTD.get('consoleTimestamps');
            PTD.set('consoleTimestamps', v);
            b.setAttribute('aria-pressed', v ? 'true' : 'false');
            paint();
        }, PTD.get('consoleTimestamps'));

        var scrollBtn = cbtn('Auto', 'arrowUp', 'Automatisch nach unten scrollen', function (b) {
            autoscroll = !autoscroll;
            b.setAttribute('aria-pressed', autoscroll ? 'true' : 'false');
            if (autoscroll) scrollBottom();
        }, true);

        var copyBtn = cbtn('', 'copy', 'Puffer in die Zwischenablage kopieren', function () {
            var text = plain();
            if (!text) { PTD.toast({ type: 'warn', title: 'Puffer ist leer' }); return; }
            if (navigator.clipboard && navigator.clipboard.writeText) {
                navigator.clipboard.writeText(text).then(function () {
                    PTD.toast({ type: 'ok', title: 'Kopiert', msg: PTD.store.lines.length + ' Zeilen' });
                });
            } else {
                PTD.toast({ type: 'warn', title: 'Zwischenablage nicht verfuegbar' });
            }
        });

        var dlBtn = cbtn('', 'download', 'Puffer als .log herunterladen', function () {
            var text = plain();
            if (!text) { PTD.toast({ type: 'warn', title: 'Puffer ist leer' }); return; }
            var blob = new Blob([text], { type: 'text/plain;charset=utf-8' });
            var url = URL.createObjectURL(blob);
            var a = el('a', { href: url, download: (PTD.route.server || 'server') + '-console.log' });
            document.body.appendChild(a);
            a.click();
            document.body.removeChild(a);
            setTimeout(function () { URL.revokeObjectURL(url); }, 2000);
        });

        var clearBtn = cbtn('', 'trash', 'Mitgelesenen Puffer leeren', function () {
            PTD.store.lines = [];
            paint();
            PTD.toast({ type: 'ok', title: 'Puffer geleert', msg: 'Die Konsole selbst bleibt unveraendert.' });
        });

        var fullBtn = cbtn('', 'expand', 'Konsole im Vollbild', function (b) {
            var h = document.documentElement;
            var full = h.getAttribute('data-ptd-console') === 'full';
            if (full) h.removeAttribute('data-ptd-console'); else h.setAttribute('data-ptd-console', 'full');
            b.setAttribute('aria-pressed', full ? 'false' : 'true');
            b.innerHTML = '';
            b.insertAdjacentHTML('beforeend', icon(full ? 'expand' : 'collapse', 13));
            setTimeout(function () { window.dispatchEvent(new Event('resize')); }, 60);
        }, false);

        countEl = el('span', { class: 'ptd-chits', text: '0 Zeilen' });
        stateEl = el('span', { class: 'ptd-cstate', 'data-state': PTD.store.state }, [
            el('i', { class: 'ptd-dot' }),
            el('span', { text: label(PTD.store.state) })
        ]);

        bar = el('div', { id: 'ptd-console-bar' }, [
            el('div', { class: 'ptd-csearch' }, [
                el('span', { html: icon('search', 13), style: { color: 'var(--ptd-faint)', display: 'inline-flex' } }),
                search, hitsEl
            ]),
            filterBtn, bufferBtn, tsBtn, scrollBtn,
            el('span', { class: 'ptd-cspacer' }),
            countEl, copyBtn, dlBtn, clearBtn, fullBtn, stateEl
        ]);

        view = el('div', { id: 'ptd-log-view' });
        view.addEventListener('scroll', function () {
            var atBottom = view.scrollTop + view.clientHeight >= view.scrollHeight - 24;
            if (!atBottom) autoscroll = false;
        });
    }

    function label(state) {
        return ({
            running: 'Online', starting: 'Startet', stopping: 'Stoppt',
            offline: 'Offline', missing: 'Fehlt'
        })[state] || String(state || 'offline');
    }

    /* =====================================================================
       Ein- und Aushaengen
       ===================================================================== */

    function mount() {
        if (!shouldMount()) { unmount(); return; }
        var target = qs('[data-ptd="console"]');
        if (!target) return;
        if (!bar) build();

        if (box !== target) {
            box = target;
            if (bar.parentNode) bar.parentNode.removeChild(bar);
            if (view.parentNode) view.parentNode.removeChild(view);
            box.parentNode.insertBefore(bar, box);
            box.appendChild(view);
            paint();
        }
    }

    function unmount() {
        if (bar && bar.parentNode) bar.parentNode.removeChild(bar);
        if (view && view.parentNode) view.parentNode.removeChild(view);
        document.documentElement.removeAttribute('data-ptd-console');
        box = null;
    }

    /* =====================================================================
       Darstellung des Puffers
       ===================================================================== */

    function matches(line) {
        if (filter === 'error' && line.lvl !== 'error') return false;
        if (filter === 'warn' && line.lvl !== 'warn' && line.lvl !== 'error') return false;
        if (query && line.text.toLowerCase().indexOf(query.toLowerCase()) === -1) return false;
        return true;
    }

    function plain() {
        var ts = PTD.get('consoleTimestamps');
        return PTD.store.lines.map(function (l) {
            return (ts ? '[' + new Date(l.t).toISOString() + '] ' : '') + l.text;
        }).join('\n');
    }

    function highlight(text) {
        var safe = PTD.escapeHtml(text);
        if (!query) return safe;
        var q = PTD.escapeHtml(query).replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
        return safe.replace(new RegExp(q, 'gi'), function (m) { return '<mark>' + m + '</mark>'; });
    }

    function scrollBottom() {
        if (view) view.scrollTop = view.scrollHeight;
    }

    function paint() {
        if (!bar || !view) return;

        countEl.textContent = PTD.store.lines.length + ' Zeilen';
        view.classList.toggle('is-open', viewOpen);
        view.style.fontSize = PTD.get('consoleFontSize') + 'px';

        if (!viewOpen) { hitsEl.textContent = ''; return; }

        var ts = PTD.get('consoleTimestamps');
        var hits = PTD.store.lines.filter(matches);
        hitsEl.textContent = (query || filter !== 'all') ? hits.length + '' : '';

        if (!hits.length) {
            view.innerHTML = '<div class="ptd-empty">Keine passenden Zeilen im mitgelesenen Puffer.</div>';
            return;
        }

        var slice = hits.slice(-1200);
        var html = slice.map(function (l) {
            return '<div class="ptd-line"' + (l.lvl ? ' data-lvl="' + l.lvl + '"' : '') + '>' +
                (ts ? '<span class="ptd-ts">' + PTD.fmt.clockTime(l.t) + '</span>' : '') +
                highlight(l.text) + '</div>';
        }).join('');
        view.innerHTML = html;
        if (autoscroll) scrollBottom();
    }

    function queuePaint() {
        if (renderQueued) return;
        renderQueued = true;
        requestAnimationFrame(function () {
            renderQueued = false;
            paint();
        });
    }

    /* =====================================================================
       Ereignisse
       ===================================================================== */

    PTD.bus.on('console:line', function () { if (bar) queuePaint(); });

    PTD.bus.on('state', function (e) {
        if (!stateEl) return;
        stateEl.setAttribute('data-state', e.to);
        stateEl.lastChild.textContent = label(e.to);
        var dot = stateEl.querySelector('.ptd-dot');
        if (dot) dot.classList.toggle('ptd-dot--pulse', e.to === 'starting' || e.to === 'stopping');
    });

    PTD.bus.on('scan', mount);
    PTD.bus.on('route', function () { unmount(); setTimeout(mount, 120); });
    PTD.bus.on('remount', function () { unmount(); setTimeout(mount, 60); });
    PTD.bus.on('settings', function () { if (bar) paint(); });

    PTD.ready(function () { setTimeout(mount, 250); });

    PTD.console = { mount: mount, unmount: unmount, paint: paint };
})();
