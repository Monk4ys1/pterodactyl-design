/* =========================================================================
   Nebula · 60-stats.js
   Verlaufsdiagramme fuer CPU, Arbeitsspeicher, Netzwerk und Festplatte.

   Die Werte stammen aus dem mitgelesenen Wings-Datenstrom (00-boot.js) –
   es wird nichts zusaetzlich abgefragt.

   Gestaltungsregeln: je Diagramm genau eine Serie und eine Achse, duenne
   Marken, zuruecktretendes Raster, Extremwerte statt Beschriftung jedes
   Punktes, Fadenkreuz mit Sprechblase beim Ueberfahren. Die Serienfarben
   sind fest und wurden auf Farbfehlsichtigkeit geprueft.
   ========================================================================= */

(function () {
    'use strict';
    var PTD = window.PTD;
    if (!PTD) return;

    var el = PTD.el, qs = PTD.qs, icon = PTD.icon;
    var NS = 'http://www.w3.org/2000/svg';

    var host = null, cards = {}, limits = null, limitsFor = null, queued = false;

    var DEFS = [
        { key: 'cpu',  title: 'CPU',             color: 'var(--ptd-c1)', unit: 'pct' },
        { key: 'mem',  title: 'Arbeitsspeicher', color: 'var(--ptd-c2)', unit: 'bytes' },
        { key: 'net',  title: 'Netzwerk',        color: 'var(--ptd-c3)', unit: 'rate' },
        { key: 'disk', title: 'Festplatte',      color: 'var(--ptd-c4)', unit: 'bytes' }
    ];

    var W = 100, H = 40;   /* Nutzerkoordinaten des Diagramms */

    /* =====================================================================
       Platzierung
       ===================================================================== */

    function chartHost(box) {
        var n = box.parentElement, guard = 0;
        while (n && guard < 10) {
            var mw = getComputedStyle(n).maxWidth;
            if (mw && mw !== 'none' && parseFloat(mw) > 400) return n;
            if (n.parentElement && (n.parentElement.id === 'app' || n.parentElement === document.body)) break;
            n = n.parentElement;
            guard++;
        }
        return PTD.contentRoot() || box.parentElement;
    }

    function shouldMount() {
        return PTD.get('modules.charts') && PTD.route.page === 'server' && !!qs('[data-ptd="console"]');
    }

    /* =====================================================================
       Aufbau einer Karte
       ===================================================================== */

    function svgEl(name, attrs) {
        var n = document.createElementNS(NS, name);
        Object.keys(attrs || {}).forEach(function (k) { n.setAttribute(k, attrs[k]); });
        return n;
    }

    function card(def) {
        var value = el('span', { class: 'ptd-chart-value', text: '–' });
        var sub = el('span', { class: 'ptd-chart-sub', text: '' });

        var svg = svgEl('svg', { viewBox: '0 0 ' + W + ' ' + H, preserveAspectRatio: 'none', 'aria-hidden': 'true' });
        var grid = svgEl('g', { class: 'ptd-grid' });
        [0.25, 0.5, 0.75].forEach(function (f) {
            grid.appendChild(svgEl('line', {
                class: 'ptd-grid-line', x1: 0, x2: W, y1: (H * f).toFixed(1), y2: (H * f).toFixed(1)
            }));
        });
        var area = svgEl('path', { class: 'ptd-area' });
        var line = svgEl('path', { class: 'ptd-line-path' });
        var cross = svgEl('line', { class: 'ptd-cross', y1: 0, y2: H, x1: 0, x2: 0 });
        var dot = svgEl('circle', { class: 'ptd-focus-dot', cx: 0, cy: 0, r: 3 });
        svg.appendChild(grid);
        svg.appendChild(area);
        svg.appendChild(line);
        svg.appendChild(cross);
        svg.appendChild(dot);

        var tip = el('div', { class: 'ptd-chart-tip' });
        var plot = el('div', { class: 'ptd-chart-plot' }, [tip]);
        plot.appendChild(svg);

        var foot = el('div', { class: 'ptd-chart-foot' }, [
            el('dl', {}, [
                el('div', {}, [el('dt', { text: 'min' }), el('dd', { text: '–' })]),
                el('div', {}, [el('dt', { text: 'ø' }), el('dd', { text: '–' })]),
                el('div', {}, [el('dt', { text: 'max' }), el('dd', { text: '–' })])
            ])
        ]);

        var csv = el('button', {
            type: 'button', 'aria-label': def.title + ' als CSV speichern',
            'data-ptd-tip': 'CSV speichern',
            html: icon('download', 12)
        });
        csv.addEventListener('click', function () { exportCsv(def); });

        var node = el('div', {
            class: 'ptd-chart is-empty',
            'data-key': def.key,
            style: { '--series': def.color }
        }, [
            el('div', { class: 'ptd-chart-head' }, [
                el('span', { class: 'ptd-chart-title' }, [el('i'), el('span', { text: def.title })]),
                el('span', { class: 'ptd-chart-actions' }, [csv])
            ]),
            value, sub, plot, foot
        ]);

        wireHover(plot, tip, cross, dot, def);

        return {
            node: node, value: value, sub: sub, line: line, area: area,
            plot: plot, tip: tip, cross: cross, dot: dot,
            stats: foot.querySelectorAll('dd'),
            def: def, points: [], times: []
        };
    }

    /* =====================================================================
       Fadenkreuz
       ===================================================================== */

    function wireHover(plot, tip, cross, dot, def) {
        function move(e) {
            var c = cards[def.key];
            if (!c || c.points.length < 2) return;
            var r = plot.getBoundingClientRect();
            var ratio = Math.max(0, Math.min(1, (e.clientX - r.left) / r.width));
            var i = Math.round(ratio * (c.points.length - 1));
            var v = c.points[i];
            var x = (i / (c.points.length - 1)) * W;
            var y = yOf(c, v);

            cross.setAttribute('x1', x.toFixed(2));
            cross.setAttribute('x2', x.toFixed(2));
            dot.setAttribute('cx', x.toFixed(2));
            dot.setAttribute('cy', y.toFixed(2));

            tip.innerHTML = '<b>' + PTD.escapeHtml(format(def, v)) + '</b><span>' +
                PTD.escapeHtml(PTD.fmt.clockTime(c.times[i] || Date.now())) + '</span>';
            tip.style.left = (ratio * 100) + '%';
            tip.style.top = Math.max(4, (y / H) * r.height - 8) + 'px';
            plot.classList.add('is-hover');
        }
        plot.addEventListener('pointermove', move);
        plot.addEventListener('pointerdown', move);
        plot.addEventListener('pointerleave', function () { plot.classList.remove('is-hover'); });
    }

    function yOf(c, v) {
        var lo = c.lo, hi = c.hi;
        if (hi === lo) return H / 2;
        return H - 2 - ((v - lo) / (hi - lo)) * (H - 4);
    }

    /* =====================================================================
       Werte
       ===================================================================== */

    function series(key) {
        var pts = PTD.store.stats.slice(-Math.max(12, PTD.get('historyPoints') || 120));
        var out = { v: [], t: [] };
        if (key === 'net') {
            for (var i = 1; i < pts.length; i++) {
                var dt = Math.max((pts[i].t - pts[i - 1].t) / 1000, 0.001);
                var d = (pts[i].rx - pts[i - 1].rx) + (pts[i].tx - pts[i - 1].tx);
                out.v.push(d > 0 ? d / dt : 0);
                out.t.push(pts[i].t);
            }
            return out;
        }
        var field = key === 'cpu' ? 'cpu' : key === 'mem' ? 'mem' : 'disk';
        pts.forEach(function (p) { out.v.push(p[field]); out.t.push(p.t); });
        return out;
    }

    function format(def, v) {
        if (def.unit === 'pct') return PTD.fmt.pct(v);
        if (def.unit === 'rate') return PTD.fmt.bytes(v) + '/s';
        return PTD.fmt.bytes(v);
    }

    function capOf(key) {
        if (key === 'cpu') return (limits && limits.cpu) ? limits.cpu : 0;
        if (key === 'mem') {
            var l = PTD.store.lastStats && PTD.store.lastStats.memLimit;
            if (!l && limits && limits.memory) l = limits.memory * 1048576;
            return l || 0;
        }
        if (key === 'disk') return limits && limits.disk ? limits.disk * 1048576 : 0;
        return 0;
    }

    function fetchLimits() {
        var id = PTD.route.server;
        if (!id || limitsFor === id) return;
        limitsFor = id;
        limits = PTD.cache.get('limits:' + id, 300000);
        if (limits) return;
        PTD.api('/api/client/servers/' + id).then(function (res) {
            var a = res && res.attributes;
            if (!a) return;
            limits = {
                memory: (a.limits && a.limits.memory) || 0,
                disk: (a.limits && a.limits.disk) || 0,
                cpu: (a.limits && a.limits.cpu) || 0
            };
            PTD.cache.set('limits:' + id, limits);
            draw();
        }).catch(function () { /* Limits sind optional */ });
    }

    /* =====================================================================
       Zeichnen
       ===================================================================== */

    function draw() {
        if (!host) return;

        DEFS.forEach(function (def) {
            var c = cards[def.key];
            if (!c) return;

            var s = series(def.key);
            c.points = s.v;
            c.times = s.t;

            if (s.v.length < 2) {
                c.node.classList.add('is-empty');
                c.value.textContent = '–';
                c.sub.textContent = PTD.store.state === 'running' ? 'warte auf Daten …' : 'Server offline';
                c.line.setAttribute('d', '');
                c.area.setAttribute('d', '');
                c.plot.removeAttribute('title');
                Array.prototype.forEach.call(c.stats, function (n) { n.textContent = '–'; });
                return;
            }
            c.node.classList.remove('is-empty');

            var lo = Math.min.apply(null, s.v);
            var hi = Math.max.apply(null, s.v);
            if (hi === lo) hi = lo + (lo === 0 ? 1 : lo * 0.1);
            /* Etwas Luft nach oben, damit die Kurve nicht am Rand klebt */
            hi = hi + (hi - lo) * 0.12;
            c.lo = lo; c.hi = hi;

            var step = W / (s.v.length - 1);
            var d = '';
            for (var i = 0; i < s.v.length; i++) {
                d += (i === 0 ? 'M' : 'L') + (i * step).toFixed(2) + ' ' + yOf(c, s.v[i]).toFixed(2);
            }
            c.line.setAttribute('d', d);
            c.area.setAttribute('d', d + 'L' + W + ' ' + H + 'L0 ' + H + 'Z');

            var latest = s.v[s.v.length - 1];
            var sum = 0;
            for (var j = 0; j < s.v.length; j++) sum += s.v[j];

            c.value.textContent = format(def, latest);
            c.stats[0].textContent = format(def, Math.min.apply(null, s.v));
            c.stats[1].textContent = format(def, sum / s.v.length);
            c.stats[2].textContent = format(def, Math.max.apply(null, s.v));

            /* Das Zeitfenster steht als Titel am Diagramm statt in der Fusszeile –
               dort wuerde es bei schmalen Karten mit Min/Max kollidieren. */
            var secs = Math.round((s.t[s.t.length - 1] - s.t[0]) / 1000);
            c.plot.setAttribute('title', def.title + ' · letzte ' + PTD.fmt.duration(secs * 1000) +
                ' · ' + s.v.length + ' Messpunkte');

            var cap = capOf(def.key);
            var ratio = cap ? latest / cap : 0;
            c.sub.textContent = cap
                ? (def.unit === 'pct'
                    ? 'Limit ' + cap + ' %  ·  ' + PTD.fmt.pct(ratio * 100) + ' ausgelastet'
                    : 'von ' + PTD.fmt.bytes(cap) + '  ·  ' + PTD.fmt.pct(ratio * 100))
                : 'ohne Limit';

            var level = ratio >= 0.9 ? 'danger' : ratio >= 0.75 ? 'warn' : '';
            if (level) c.node.setAttribute('data-level', level); else c.node.removeAttribute('data-level');
        });
    }

    function exportCsv(def) {
        var s = series(def.key);
        if (!s.v.length) { PTD.toast({ type: 'warn', title: 'Noch keine Daten' }); return; }
        var rows = [['zeit', 'wert']];
        for (var i = 0; i < s.v.length; i++) {
            rows.push([new Date(s.t[i]).toISOString(), String(s.v[i])]);
        }
        var name = (PTD.route.server || 'server') + '-' + def.key + '.csv';
        if (PTD.download(name, PTD.toCsv(rows), 'text/csv')) {
            PTD.toast({ type: 'ok', title: 'Gespeichert', msg: name });
        }
    }

    /* =====================================================================
       Ein- und Aushaengen
       ===================================================================== */

    function mount() {
        if (!shouldMount()) { unmount(); return; }
        if (host && host.parentNode) return;

        host = el('div', { id: 'ptd-charts', 'data-ptd-own': '' });
        cards = {};
        DEFS.forEach(function (d) {
            var c = card(d);
            cards[d.key] = c;
            host.appendChild(c.node);
        });

        var box = qs('[data-ptd="console"]');
        if (!box) return;
        chartHost(box).appendChild(host);

        fetchLimits();
        draw();
    }

    function unmount() {
        if (host && host.parentNode) host.parentNode.removeChild(host);
        host = null;
        cards = {};
    }

    function queue() {
        if (queued) return;
        queued = true;
        requestAnimationFrame(function () { queued = false; draw(); });
    }

    PTD.bus.on('stats', queue);
    PTD.bus.on('state', queue);
    PTD.bus.on('scan', mount);
    PTD.bus.on('route', function () { unmount(); limitsFor = null; limits = null; setTimeout(mount, 150); });
    PTD.bus.on('settings', function () { if (PTD.get('modules.charts')) { mount(); queue(); } else unmount(); });

    PTD.ready(function () { setTimeout(mount, 300); });

    PTD.charts = { mount: mount, unmount: unmount, draw: draw, export: exportCsv };
})();
