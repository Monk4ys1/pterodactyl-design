/* =========================================================================
   Nebula · 50-console.js
   Werkzeugleiste ueber der Konsole, frei belegbare Kurzbefehle und eine
   schwebende Mini-Konsole, die beim Wechsel in andere Reiter des Servers
   sichtbar bleibt.

   Gesendet wird ausschliesslich ueber die Verbindung, die das Panel selbst
   schon aufgebaut hat – es wird keine zweite Verbindung geoeffnet.
   ========================================================================= */

(function () {
    'use strict';
    var PTD = window.PTD;
    if (!PTD) return;

    var el = PTD.el, qs = PTD.qs, icon = PTD.icon;

    var bar = null, view = null, snips = null, box = null;
    var query = '', filter = 'all', autoscroll = true, viewOpen = false;
    var hitsEl = null, countEl = null, stateEl = null, searchInput = null;
    var painting = false;

    /* =====================================================================
       Hilfen
       ===================================================================== */

    function shouldMount() {
        return PTD.get('modules.console') && PTD.route.page === 'server' && !!qs('[data-ptd="console"]');
    }

    function label(state) {
        return ({ running: 'Online', starting: 'Startet', stopping: 'Stoppt', offline: 'Offline', missing: 'Fehlt' })[state]
            || String(state || 'offline');
    }

    function cbtn(opts) {
        var b = el('button', {
            class: 'ptd-cbtn', type: 'button',
            title: opts.title || opts.label,
            'aria-label': opts.title || opts.label,
            'aria-pressed': opts.pressed === undefined ? null : (opts.pressed ? 'true' : 'false')
        }, []);
        if (opts.icon) b.insertAdjacentHTML('beforeend', icon(opts.icon, 12));
        if (opts.label) b.appendChild(el('span', { text: opts.label }));
        b.addEventListener('click', function () { opts.onClick(b); });
        return b;
    }

    /* =====================================================================
       Werkzeugleiste
       ===================================================================== */

    function build() {
        searchInput = el('input', {
            type: 'search', placeholder: 'Konsole durchsuchen …',
            spellcheck: 'false', 'aria-label': 'Konsole durchsuchen'
        });
        searchInput.addEventListener('input', PTD.debounce(function () {
            query = searchInput.value.trim();
            viewOpen = !!query || filter !== 'all';
            paint();
        }, 120));
        searchInput.addEventListener('keydown', function (e) {
            if (e.key === 'Escape') { searchInput.value = ''; query = ''; viewOpen = filter !== 'all'; paint(); }
        });

        hitsEl = el('span', { class: 'ptd-chits' });
        countEl = el('span', { class: 'ptd-chits' });
        stateEl = el('span', { class: 'ptd-cstate', 'data-state': PTD.store.state }, [
            el('i', { class: 'ptd-dot' }),
            el('span', { text: label(PTD.store.state) })
        ]);

        var filterBtn = cbtn({
            label: 'Alle', icon: 'filter', title: 'Nach Log-Level filtern', pressed: false,
            onClick: function (b) {
                filter = filter === 'all' ? 'error' : filter === 'error' ? 'warn' : 'all';
                b.lastChild.textContent = filter === 'all' ? 'Alle' : filter === 'error' ? 'Fehler' : 'Warnungen';
                b.setAttribute('aria-pressed', filter === 'all' ? 'false' : 'true');
                viewOpen = !!query || filter !== 'all';
                paint();
            }
        });

        var bufferBtn = cbtn({
            label: 'Puffer', icon: 'table', title: 'Mitgelesenen Puffer ein-/ausblenden', pressed: false,
            onClick: function (b) { viewOpen = !viewOpen; b.setAttribute('aria-pressed', viewOpen ? 'true' : 'false'); paint(); }
        });

        var tsBtn = cbtn({
            icon: 'clock', title: 'Zeitstempel anzeigen', pressed: PTD.get('consoleTimestamps'),
            onClick: function (b) {
                var v = !PTD.get('consoleTimestamps');
                PTD.set('consoleTimestamps', v);
                b.setAttribute('aria-pressed', v ? 'true' : 'false');
                paint();
            }
        });

        var scrollBtn = cbtn({
            icon: 'arrowUp', title: 'Automatisch nach unten scrollen', pressed: true,
            onClick: function (b) {
                autoscroll = !autoscroll;
                b.setAttribute('aria-pressed', autoscroll ? 'true' : 'false');
                if (autoscroll) scrollBottom();
            }
        });

        var copyBtn = cbtn({
            icon: 'copy', title: 'Puffer in die Zwischenablage kopieren',
            onClick: function () {
                var text = plain();
                if (!text) { PTD.toast({ type: 'warn', title: 'Puffer ist leer' }); return; }
                if (navigator.clipboard && navigator.clipboard.writeText) {
                    navigator.clipboard.writeText(text).then(function () {
                        PTD.toast({ type: 'ok', title: 'Kopiert', msg: PTD.store.lines.length + ' Zeilen' });
                    });
                } else {
                    PTD.toast({ type: 'warn', title: 'Zwischenablage nicht verfuegbar' });
                }
            }
        });

        var dlBtn = cbtn({
            icon: 'download', title: 'Puffer als .log speichern',
            onClick: function () {
                var text = plain();
                if (!text) { PTD.toast({ type: 'warn', title: 'Puffer ist leer' }); return; }
                var name = (PTD.route.server || 'server') + '-console.log';
                if (PTD.download(name, text)) PTD.toast({ type: 'ok', title: 'Gespeichert', msg: name });
            }
        });

        var clearBtn = cbtn({
            icon: 'trash', title: 'Mitgelesenen Puffer leeren',
            onClick: function () {
                PTD.store.lines = [];
                paint();
                PTD.toast({ type: 'ok', title: 'Puffer geleert', msg: 'Die Konsole selbst bleibt unveraendert.' });
            }
        });

        var dockBtn = cbtn({
            icon: 'pip', title: 'Mini-Konsole', pressed: false,
            onClick: function () { dock.toggle(); }
        });

        var fullBtn = cbtn({
            icon: 'expand', title: 'Vollbild (Strg + Umschalt + F)', pressed: false,
            onClick: function (b) {
                var h = document.documentElement;
                var full = h.getAttribute('data-ptd-console') === 'full';
                if (full) h.removeAttribute('data-ptd-console'); else h.setAttribute('data-ptd-console', 'full');
                b.setAttribute('aria-pressed', full ? 'false' : 'true');
                b.innerHTML = '';
                b.insertAdjacentHTML('beforeend', icon(full ? 'expand' : 'collapse', 12));
                setTimeout(function () { window.dispatchEvent(new Event('resize')); }, 60);
            }
        });

        bar = el('div', { id: 'ptd-console-bar', 'data-ptd-own': '' }, [
            el('div', { class: 'ptd-csearch' }, [
                el('span', { html: icon('search', 12), style: { color: 'var(--ptd-faint)', display: 'inline-flex' } }),
                searchInput, hitsEl
            ]),
            filterBtn, bufferBtn, tsBtn, scrollBtn,
            el('span', { class: 'ptd-cspacer' }),
            countEl, copyBtn, dlBtn, clearBtn, dockBtn, fullBtn, stateEl
        ]);

        view = el('div', { id: 'ptd-log-view' });
        view.addEventListener('scroll', function () {
            var atBottom = view.scrollTop + view.clientHeight >= view.scrollHeight - 24;
            if (!atBottom) autoscroll = false;
        });

        snips = el('div', { id: 'ptd-snippets', 'data-ptd-own': '' });
    }

    /* =====================================================================
       Kurzbefehle
       ===================================================================== */

    function snippetsFor(id) {
        var all = PTD.get('snippets') || {};
        return all[id] || [];
    }

    function saveSnippets(id, list) {
        var all = PTD.get('snippets') || {};
        if (list.length) all[id] = list; else delete all[id];
        PTD.settings.snippets = all;
        PTD.save();
        paintSnippets();
    }

    function run(cmd) {
        if (PTD.command(cmd)) {
            PTD.toast({ type: 'ok', title: 'Gesendet', msg: cmd, timeout: 2600 });
        } else {
            PTD.toast({ type: 'danger', title: 'Nicht verbunden', msg: 'Die Konsole muss geoeffnet und verbunden sein.' });
        }
    }

    function paintSnippets() {
        if (!snips) return;
        var id = PTD.route.server;
        if (!id || !PTD.get('modules.snippets')) { snips.style.display = 'none'; return; }
        snips.style.display = '';

        var list = snippetsFor(id);
        snips.innerHTML = '';
        snips.appendChild(el('span', { class: 'ptd-sn-title', text: 'Kurzbefehle' }));

        list.forEach(function (cmd, i) {
            var chip = el('button', { class: 'ptd-snip', type: 'button', title: 'Senden: ' + cmd }, [
                el('span', { text: cmd }),
                el('span', { class: 'ptd-snip-x', html: '&times;' })
            ]);
            chip.addEventListener('click', function () {
                if (snips.classList.contains('is-editing')) {
                    var copy = list.slice();
                    copy.splice(i, 1);
                    saveSnippets(id, copy);
                    return;
                }
                run(cmd);
            });
            snips.appendChild(chip);
        });

        var add = el('button', { class: 'ptd-snip ptd-snip--add', type: 'button', title: 'Kurzbefehl hinzufuegen' }, []);
        add.insertAdjacentHTML('beforeend', icon('plus', 11));
        add.appendChild(el('span', { text: list.length ? 'Neu' : 'Kurzbefehl anlegen' }));
        add.addEventListener('click', function () {
            var cmd = window.prompt('Befehl, der an den Server gesendet wird:');
            if (!cmd) return;
            saveSnippets(id, snippetsFor(id).concat([cmd.trim()]));
        });
        snips.appendChild(add);

        if (list.length) {
            var edit = el('button', { class: 'ptd-snip ptd-snip--add', type: 'button', title: 'Bearbeiten' }, []);
            edit.insertAdjacentHTML('beforeend', icon('sliders', 11));
            edit.addEventListener('click', function () { snips.classList.toggle('is-editing'); });
            snips.appendChild(edit);
        }
    }

    /* =====================================================================
       Protokollansicht
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

    function scrollBottom() { if (view) view.scrollTop = view.scrollHeight; }

    function paint() {
        if (!bar || !view) return;

        countEl.textContent = PTD.store.lines.length + ' Zeilen';
        view.classList.toggle('is-open', viewOpen);
        view.style.fontSize = PTD.get('consoleFontSize') + 'px';

        if (!viewOpen) { hitsEl.textContent = ''; return; }

        var ts = PTD.get('consoleTimestamps');
        var hits = PTD.store.lines.filter(matches);
        hitsEl.textContent = (query || filter !== 'all') ? String(hits.length) : '';

        if (!hits.length) {
            view.innerHTML = '<div class="ptd-empty">Keine passenden Zeilen im mitgelesenen Puffer.</div>';
            return;
        }

        view.innerHTML = hits.slice(-1500).map(function (l) {
            return '<div class="ptd-line"' + (l.lvl ? ' data-lvl="' + l.lvl + '"' : '') + '>' +
                (ts ? '<span class="ptd-ts">' + PTD.fmt.clockTime(l.t) + '</span>' : '') +
                '<span>' + highlight(l.text) + '</span></div>';
        }).join('');
        if (autoscroll) scrollBottom();
    }

    function queuePaint() {
        if (painting) return;
        painting = true;
        requestAnimationFrame(function () { painting = false; paint(); });
    }

    /* =====================================================================
       Ein- und Aushaengen
       ===================================================================== */

    function mount() {
        if (!shouldMount()) { unmount(); return; }
        var target = qs('[data-ptd="console"]');
        if (!target) return;
        if (!bar) build();

        if (box !== target || !bar.parentNode) {
            box = target;
            [bar, snips, view].forEach(function (n) { if (n.parentNode) n.parentNode.removeChild(n); });
            box.parentNode.insertBefore(bar, box);
            box.parentNode.insertBefore(snips, box);
            box.appendChild(view);
            paintSnippets();
            paint();
        }
    }

    function unmount() {
        [bar, snips, view].forEach(function (n) { if (n && n.parentNode) n.parentNode.removeChild(n); });
        document.documentElement.removeAttribute('data-ptd-console');
        box = null;
    }

    /* =====================================================================
       Schwebende Mini-Konsole
       ===================================================================== */

    var dock = (function () {
        var node = null, body = null, input = null, title = null, open = false;
        var pos = null, drag = null;

        function load() {
            try { return JSON.parse(sessionStorage.getItem('ptd:dock') || 'null'); } catch (e) { return null; }
        }
        function store() {
            try { sessionStorage.setItem('ptd:dock', JSON.stringify(pos)); } catch (e) { /* egal */ }
        }

        function build() {
            body = el('div', { class: 'ptd-dock-body' });
            input = el('input', {
                type: 'text', placeholder: 'Befehl senden …', spellcheck: 'false',
                'aria-label': 'Befehl senden'
            });
            input.addEventListener('keydown', function (e) {
                if (e.key !== 'Enter') return;
                var v = input.value.trim();
                if (!v) return;
                run(v);
                input.value = '';
            });
            title = el('span', { class: 'ptd-dock-title', text: 'Konsole' });

            var head = el('div', { class: 'ptd-dock-head' }, [
                el('span', { html: icon('terminal', 13), style: { color: 'var(--ptd-accent)', display: 'inline-flex' } }),
                title,
                el('button', {
                    class: 'ptd-dock-btn', type: 'button', 'aria-label': 'Zur Konsole',
                    html: icon('expand', 13),
                    onclick: function () { PTD.navigate('/server/' + PTD.route.server); }
                }),
                el('button', {
                    class: 'ptd-dock-btn', type: 'button', 'aria-label': 'Schliessen',
                    html: icon('close', 13),
                    onclick: hide
                })
            ]);

            var resize = el('div', { class: 'ptd-dock-resize', 'aria-hidden': 'true' });

            node = el('section', { id: 'ptd-dock', 'data-ptd-own': '', 'aria-label': 'Mini-Konsole' }, [
                head, body,
                el('div', { class: 'ptd-dock-input' }, [el('span', { text: '›' }), input]),
                resize
            ]);

            wireDrag(head, node);
            wireResize(resize, node);
            document.body.appendChild(node);

            pos = load() || { x: window.innerWidth - 440, y: window.innerHeight - 300, w: 420, h: 260 };
            apply();
        }

        function apply() {
            node.style.left = Math.round(pos.x) + 'px';
            node.style.top = Math.round(pos.y) + 'px';
            node.style.right = 'auto';
            node.style.bottom = 'auto';
            node.style.width = Math.round(pos.w) + 'px';
            node.style.height = Math.round(pos.h) + 'px';
        }

        /* Ziehen: 1:1 am Zeiger, mit Gummiband an den Raendern und einem
           kurzen Nachlauf aus der Loesegeschwindigkeit. */
        function wireDrag(handle, target) {
            handle.addEventListener('pointerdown', function (e) {
                if (e.button !== 0) return;
                if (e.target.closest('button')) return;
                handle.setPointerCapture(e.pointerId);
                drag = {
                    id: e.pointerId,
                    dx: e.clientX - pos.x,
                    dy: e.clientY - pos.y,
                    hist: [{ x: e.clientX, y: e.clientY, t: performance.now() }]
                };
                target.classList.add('is-dragging');
            });

            handle.addEventListener('pointermove', function (e) {
                if (!drag || e.pointerId !== drag.id) return;
                var x = e.clientX - drag.dx;
                var y = e.clientY - drag.dy;
                pos.x = rubber(x, 0, window.innerWidth - pos.w);
                pos.y = rubber(y, 0, window.innerHeight - pos.h);
                apply();
                drag.hist.push({ x: e.clientX, y: e.clientY, t: performance.now() });
                if (drag.hist.length > 6) drag.hist.shift();
            });

            function end(e) {
                if (!drag || e.pointerId !== drag.id) return;
                target.classList.remove('is-dragging');
                var h = drag.hist;
                var v = { x: 0, y: 0 };
                if (h.length > 1) {
                    var a = h[0], b = h[h.length - 1];
                    var dt = Math.max(b.t - a.t, 1) / 1000;
                    v.x = (b.x - a.x) / dt;
                    v.y = (b.y - a.y) / dt;
                }
                drag = null;
                settle(v);
            }
            handle.addEventListener('pointerup', end);
            handle.addEventListener('pointercancel', end);
        }

        /* Weiche Begrenzung: je weiter ueber den Rand, desto weniger folgt das
           Fenster – statt hart zu stoppen. */
        function rubber(value, min, max) {
            if (value >= min && value <= max) return value;
            var over = value < min ? value - min : value - max;
            var limit = value < min ? min : max;
            var d = 220;
            return limit + (over * d * 0.55) / (d + 0.55 * Math.abs(over));
        }

        function project(v) { return (v / 1000) * 0.995 / (1 - 0.995); }

        function settle(v) {
            var tx = clamp(pos.x + project(v.x) * 0.25, 8, window.innerWidth - pos.w - 8);
            var ty = clamp(pos.y + project(v.y) * 0.25, 8, window.innerHeight - pos.h - 8);
            animateTo(tx, ty);
        }

        function clamp(v, a, b) { return Math.max(a, Math.min(b, v)); }

        function animateTo(tx, ty) {
            var sx = pos.x, sy = pos.y, t0 = performance.now(), dur = 320;
            if (!PTD.get('motion')) { pos.x = tx; pos.y = ty; apply(); store(); return; }
            function step(now) {
                var p = Math.min(1, (now - t0) / dur);
                /* Kritisch gedaempftes Einschwingen, kein Ueberschwingen */
                var e = 1 - Math.pow(1 - p, 3);
                pos.x = sx + (tx - sx) * e;
                pos.y = sy + (ty - sy) * e;
                apply();
                if (p < 1) requestAnimationFrame(step); else store();
            }
            requestAnimationFrame(step);
        }

        function wireResize(handle, target) {
            var r = null;
            handle.addEventListener('pointerdown', function (e) {
                handle.setPointerCapture(e.pointerId);
                r = { id: e.pointerId, x: e.clientX, y: e.clientY, w: pos.w, h: pos.h, px: pos.x, py: pos.y };
                target.classList.add('is-dragging');
            });
            handle.addEventListener('pointermove', function (e) {
                if (!r || e.pointerId !== r.id) return;
                var dw = r.x - e.clientX;
                var dh = r.y - e.clientY;
                pos.w = clamp(r.w + dw, 280, Math.min(760, window.innerWidth - 24));
                pos.h = clamp(r.h + dh, 160, Math.min(620, window.innerHeight - 24));
                pos.x = r.px + (r.w - pos.w);
                pos.y = r.py + (r.h - pos.h);
                apply();
            });
            function end() { if (!r) return; r = null; target.classList.remove('is-dragging'); store(); }
            handle.addEventListener('pointerup', end);
            handle.addEventListener('pointercancel', end);
        }

        function paintBody() {
            if (!open || !body) return;
            var lines = PTD.store.lines.slice(-160);
            body.innerHTML = lines.map(function (l) {
                return '<div class="ptd-line"' + (l.lvl ? ' data-lvl="' + l.lvl + '"' : '') + '>' +
                    PTD.escapeHtml(l.text) + '</div>';
            }).join('');
            body.scrollTop = body.scrollHeight;
        }

        function show() {
            if (!PTD.get('modules.dock')) return;
            if (!node) build();
            open = true;
            node.classList.add('is-open');
            if (title) {
                var s = ((PTD.rail && PTD.rail.servers()) || []).filter(function (x) { return x.id === PTD.route.server; })[0];
                title.textContent = s ? s.name : 'Konsole';
            }
            paintBody();
            syncButton();
        }

        function hide() {
            open = false;
            if (node) node.classList.remove('is-open');
            syncButton();
        }

        function syncButton() {
            var b = qs('#ptd-tb-dock');
            if (b) b.setAttribute('aria-pressed', open ? 'true' : 'false');
        }

        return {
            toggle: function () { open ? hide() : show(); },
            show: show, hide: hide,
            isOpen: function () { return open; },
            paint: paintBody
        };
    })();

    /* =====================================================================
       Ereignisse
       ===================================================================== */

    PTD.bus.on('console:line', function () {
        if (bar) queuePaint();
        if (dock.isOpen()) dock.paint();
    });

    PTD.bus.on('state', function (e) {
        if (!stateEl) return;
        stateEl.setAttribute('data-state', e.to);
        stateEl.lastChild.textContent = label(e.to);
        var dot = stateEl.querySelector('.ptd-dot');
        if (dot) dot.classList.toggle('ptd-dot--pulse', e.to === 'starting' || e.to === 'stopping');
    });

    PTD.bus.on('scan', mount);
    PTD.bus.on('route', function () {
        unmount();
        setTimeout(function () { mount(); paintSnippets(); }, 120);
        if (PTD.route.page !== 'server') dock.hide();
    });
    PTD.bus.on('settings', function () {
        if (!PTD.get('modules.console')) unmount(); else mount();
        if (bar) { paint(); paintSnippets(); }
        if (!PTD.get('modules.dock')) dock.hide();
    });

    PTD.ready(function () { setTimeout(mount, 250); });

    PTD.console = { mount: mount, unmount: unmount, paint: paint, run: run };
    PTD.dock = dock;
})();
