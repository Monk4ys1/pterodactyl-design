/* =========================================================================
   Nebula · 60-stats.js
   Live-Verlaufsgraphen fuer CPU, Arbeitsspeicher, Netzwerk und Festplatte.
   Die Werte stammen direkt aus dem Wings-Datenstrom (siehe 00-boot.js),
   es wird also nichts zusaetzlich abgefragt.
   ========================================================================= */

(function () {
    'use strict';
    var PTD = window.PTD;
    if (!PTD) return;

    var el = PTD.el, qs = PTD.qs;
    var host = null, cards = {}, limits = null, limitsFor = null, queued = false;

    var DEFS = [
        { key: 'cpu',  title: 'CPU',              unit: '%'  },
        { key: 'mem',  title: 'Arbeitsspeicher',  unit: 'b'  },
        { key: 'net',  title: 'Netzwerk',         unit: 'bs' },
        { key: 'disk', title: 'Festplatte',       unit: 'b'  }
    ];

    /* =====================================================================
       Position im Seitenlayout bestimmen
       ===================================================================== */

    /* Naechster Vorfahre mit begrenzter Breite – so richten sich die Graphen
       am selben Raster aus wie der uebrige Seiteninhalt. */
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
        return PTD.get('modules.charts') &&
            PTD.route.page === 'server' &&
            !!qs('[data-ptd="console"]');
    }

    /* =====================================================================
       Aufbau
       ===================================================================== */

    function card(def) {
        var value = el('span', { class: 'ptd-chart-value', text: '–' });
        var sub = el('span', { class: 'ptd-chart-sub', text: '' });
        var svg = document.createElementNS('http://www.w3.org/2000/svg', 'svg');
        svg.setAttribute('viewBox', '0 0 100 30');
        svg.setAttribute('preserveAspectRatio', 'none');

        var area = document.createElementNS('http://www.w3.org/2000/svg', 'path');
        area.setAttribute('class', 'ptd-area');
        area.setAttribute('fill', 'var(--ptd-accent)');
        area.setAttribute('opacity', '0.16');

        var line = document.createElementNS('http://www.w3.org/2000/svg', 'path');
        line.setAttribute('class', 'ptd-line-path');
        line.setAttribute('vector-effect', 'non-scaling-stroke');

        svg.appendChild(area);
        svg.appendChild(line);

        var node = el('div', { class: 'ptd-chart', 'data-key': def.key }, [
            el('div', { class: 'ptd-chart-head' }, [
                el('span', { class: 'ptd-chart-title', text: def.title }),
                value
            ]),
            sub
        ]);
        node.appendChild(svg);

        return { node: node, value: value, sub: sub, line: line, area: area };
    }

    function mount() {
        if (!shouldMount()) { unmount(); return; }
        if (host && host.parentNode) return;

        host = el('div', { id: 'ptd-charts' });
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

    /* =====================================================================
       Serverlimits (fuer Prozentwerte)
       ===================================================================== */

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
                memory: (a.limits && a.limits.memory) || 0,   /* MiB, 0 = unbegrenzt */
                disk: (a.limits && a.limits.disk) || 0,
                cpu: (a.limits && a.limits.cpu) || 0          /* Prozent, 0 = unbegrenzt */
            };
            PTD.cache.set('limits:' + id, limits);
            draw();
        }).catch(function () { /* Limits sind optional */ });
    }

    /* =====================================================================
       Zeichnen
       ===================================================================== */

    function series(key) {
        var pts = PTD.store.stats.slice(-Math.max(10, PTD.get('historyPoints') || 90));
        if (key === 'cpu')  return pts.map(function (p) { return p.cpu; });
        if (key === 'mem')  return pts.map(function (p) { return p.mem; });
        if (key === 'disk') return pts.map(function (p) { return p.disk; });
        if (key === 'net') {
            var out = [];
            for (var i = 1; i < pts.length; i++) {
                var dt = Math.max((pts[i].t - pts[i - 1].t) / 1000, 0.001);
                var d = (pts[i].rx - pts[i - 1].rx) + (pts[i].tx - pts[i - 1].tx);
                out.push(d > 0 ? d / dt : 0);
            }
            return out;
        }
        return [];
    }

    function path(values) {
        if (values.length < 2) return { line: '', area: '' };
        var max = Math.max.apply(null, values);
        var min = Math.min.apply(null, values);
        if (max === min) { max = min + 1; }
        var span = max - min;
        var step = 100 / (values.length - 1);

        var d = '';
        for (var i = 0; i < values.length; i++) {
            var x = (i * step).toFixed(2);
            var y = (29 - ((values[i] - min) / span) * 27).toFixed(2);
            d += (i === 0 ? 'M' : 'L') + x + ' ' + y;
        }
        return { line: d, area: d + 'L100 30L0 30Z' };
    }

    function levelFor(key, latest) {
        var ratio = 0;
        if (key === 'cpu') {
            var cap = (limits && limits.cpu) ? limits.cpu : 100;
            ratio = latest / cap;
        } else if (key === 'mem') {
            var lim = PTD.store.lastStats && PTD.store.lastStats.memLimit;
            if (!lim && limits && limits.memory) lim = limits.memory * 1048576;
            ratio = lim ? latest / lim : 0;
        } else if (key === 'disk') {
            var dl = limits && limits.disk ? limits.disk * 1048576 : 0;
            ratio = dl ? latest / dl : 0;
        }
        if (ratio >= 0.9) return 'danger';
        if (ratio >= 0.75) return 'warn';
        return '';
    }

    function labelFor(key, latest) {
        if (key === 'cpu') {
            var cap = limits && limits.cpu ? limits.cpu : 0;
            return { value: PTD.fmt.pct(latest), sub: cap ? 'Limit ' + cap + ' %' : 'ohne Limit' };
        }
        if (key === 'mem') {
            var lim = PTD.store.lastStats && PTD.store.lastStats.memLimit;
            if (!lim && limits && limits.memory) lim = limits.memory * 1048576;
            return {
                value: PTD.fmt.bytes(latest),
                sub: lim ? 'von ' + PTD.fmt.bytes(lim) + ' · ' + PTD.fmt.pct((latest / lim) * 100) : 'ohne Limit'
            };
        }
        if (key === 'disk') {
            var dl = limits && limits.disk ? limits.disk * 1048576 : 0;
            return { value: PTD.fmt.bytes(latest), sub: dl ? 'von ' + PTD.fmt.bytes(dl) : 'ohne Limit' };
        }
        if (key === 'net') {
            var last = PTD.store.lastStats;
            return {
                value: PTD.fmt.bytes(latest) + '/s',
                sub: last ? '↓ ' + PTD.fmt.bytes(last.rx) + '  ↑ ' + PTD.fmt.bytes(last.tx) : ''
            };
        }
        return { value: '–', sub: '' };
    }

    function draw() {
        if (!host) return;
        DEFS.forEach(function (def) {
            var c = cards[def.key];
            if (!c) return;
            var vals = series(def.key);
            if (!vals.length) {
                c.value.textContent = '–';
                c.sub.textContent = PTD.store.state === 'running' ? 'warte auf Daten …' : 'Server offline';
                c.line.setAttribute('d', '');
                c.area.setAttribute('d', '');
                return;
            }
            var latest = vals[vals.length - 1];
            var p = path(vals);
            c.line.setAttribute('d', p.line);
            c.area.setAttribute('d', p.area);
            var lbl = labelFor(def.key, latest);
            c.value.textContent = lbl.value;
            c.sub.textContent = lbl.sub;
            var lvl = levelFor(def.key, latest);
            if (lvl) c.node.setAttribute('data-level', lvl); else c.node.removeAttribute('data-level');
        });
    }

    function queue() {
        if (queued) return;
        queued = true;
        requestAnimationFrame(function () { queued = false; draw(); });
    }

    /* =====================================================================
       Ereignisse
       ===================================================================== */

    PTD.bus.on('stats', queue);
    PTD.bus.on('state', queue);
    PTD.bus.on('scan', mount);
    PTD.bus.on('route', function () { unmount(); limitsFor = null; limits = null; setTimeout(mount, 150); });
    PTD.bus.on('remount', function () { unmount(); setTimeout(mount, 60); });

    PTD.ready(function () { setTimeout(mount, 300); });

    PTD.charts = { mount: mount, unmount: unmount, draw: draw };
})();
