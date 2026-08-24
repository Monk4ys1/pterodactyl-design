/* =========================================================================
   Nebula · 65-overview.js
   Serveruebersicht auf dem Dashboard.

   Die Auslastungswerte stammen aus den Ressourcen-Abfragen, die das Panel
   fuer seine eigenen Zeilen ohnehin ausfuehrt – wir hoeren nur mit. Nur wenn
   davon nichts ankommt (etwa weil die Originalzeilen gar nicht gerendert
   werden), fragt dieses Modul selbst nach, und dann bewusst sparsam.
   ========================================================================= */

(function () {
    'use strict';
    var PTD = window.PTD;
    if (!PTD) return;

    var el = PTD.el, qs = PTD.qs, icon = PTD.icon;

    var hero = null, grid = null, cards = {}, live = {};
    var pollTimer = null, heardAt = 0, ownPolling = false;

    /* =====================================================================
       Sichtbarkeit
       ===================================================================== */

    function active() {
        return PTD.get('modules.overview') && PTD.route.page === 'dashboard';
    }

    /* =====================================================================
       Aufbau
       ===================================================================== */

    function greeting() {
        var h = new Date().getHours();
        if (h < 5) return 'Gute Nacht';
        if (h < 11) return 'Guten Morgen';
        if (h < 18) return 'Guten Tag';
        return 'Guten Abend';
    }

    function userName() {
        try { return (window.PterodactylUser || {}).username || null; } catch (e) { return null; }
    }

    function usageBlock(label, id) {
        var value = el('span', { class: 'ptd-sv-u-value', text: '–' });
        var meter = el('div', { class: 'ptd-meter' }, [el('i')]);
        return {
            node: el('div', { class: 'ptd-sv-u' }, [
                el('div', { class: 'ptd-sv-u-top' }, [
                    el('span', { class: 'ptd-sv-u-label', text: label }),
                    value
                ]),
                meter
            ]),
            value: value,
            meter: meter,
            bar: meter.firstChild,
            id: id
        };
    }

    function powerBtn(act, label, ico, id) {
        var b = el('button', {
            class: 'ptd-sv-btn', type: 'button', 'data-act': act,
            'aria-label': label + ' – ' + id
        }, []);
        b.insertAdjacentHTML('beforeend', icon(ico, 11));
        b.appendChild(el('span', { text: label }));
        b.addEventListener('click', function (e) {
            e.preventDefault();
            e.stopPropagation();
            power(id, act, b);
        });
        return b;
    }

    function power(id, signal, btn) {
        if (btn) { btn.disabled = true; setTimeout(function () { btn.disabled = false; }, 2500); }
        PTD.api('/api/client/servers/' + id + '/power', { method: 'POST', body: { signal: signal } })
            .then(function () { PTD.toast({ type: 'ok', title: 'Befehl gesendet', msg: signal }); })
            .catch(function (e) {
                PTD.toast({ type: 'danger', title: 'Fehlgeschlagen', msg: 'HTTP ' + (e.status || '?') });
            });
    }

    function card(s) {
        var tag = PTD.tagOf ? PTD.tagOf(s.id, s.name) : { color: PTD.autoColor(s.id), label: PTD.fmt.initials(s.name) };

        var mark = el('span', { class: 'ptd-sv-mark', text: tag.label, 'aria-hidden': 'true' });
        mark.addEventListener('click', function (e) {
            e.preventDefault();
            e.stopPropagation();
            if (PTD.tags) PTD.tags.open(mark, s.id, s.name);
        });

        var state = el('span', { class: 'ptd-sv-state' }, [
            el('i', { class: 'ptd-dot' }),
            el('span', { text: 'Offline' })
        ]);

        var cpu = usageBlock('CPU', 'cpu');
        var mem = usageBlock('RAM', 'mem');

        var pin = el('button', { class: 'ptd-sv-btn', type: 'button', 'aria-label': 'Anheften' }, []);
        pin.insertAdjacentHTML('beforeend', icon('pin', 11));
        pin.addEventListener('click', function (e) {
            e.preventDefault();
            e.stopPropagation();
            if (PTD.rail) PTD.rail.toggleFavorite(s.id);
            paintPin(pin, s.id);
        });
        paintPin(pin, s.id);

        var node = el('a', {
            class: 'ptd-sv',
            href: '/server/' + s.id,
            'data-sid': s.id,
            'data-state': s.suspended ? 'suspended' : 'offline',
            style: { '--tag': tag.color }
        }, [
            el('div', { class: 'ptd-sv-top' }, [
                mark,
                el('span', { class: 'ptd-sv-id' }, [
                    el('span', { class: 'ptd-sv-name', text: s.name }),
                    el('span', { class: 'ptd-sv-meta', text: s.address || s.node || '' })
                ]),
                state
            ]),
            el('div', { class: 'ptd-sv-usage' }, [cpu.node, mem.node]),
            el('div', { class: 'ptd-sv-actions' }, [
                powerBtn('start', 'Start', 'play', s.id),
                powerBtn('restart', 'Neustart', 'restart', s.id),
                powerBtn('stop', 'Stopp', 'stop', s.id),
                el('span', { class: 'ptd-sv-spacer' }),
                pin
            ])
        ]);

        node.addEventListener('click', function (e) {
            if (e.metaKey || e.ctrlKey || e.shiftKey || e.button !== 0) return;
            e.preventDefault();
            PTD.navigate('/server/' + s.id);
        });

        return { node: node, state: state, cpu: cpu, mem: mem, pin: pin, data: s };
    }

    function paintPin(btn, id) {
        var on = (PTD.get('favorites') || []).indexOf(id) > -1;
        btn.setAttribute('aria-pressed', on ? 'true' : 'false');
        btn.firstChild.classList.toggle('ptd-sv-pin-on', on);
        btn.style.color = on ? 'var(--ptd-accent)' : '';
    }

    var STATE_LABEL = {
        running: 'Online', starting: 'Startet', stopping: 'Stoppt',
        offline: 'Offline', suspended: 'Gesperrt', missing: 'Fehlt'
    };

    function paintCard(c) {
        var d = live[c.data.id];
        var st = c.data.suspended ? 'suspended' : ((d && d.state) || 'offline');
        c.node.setAttribute('data-state', st);
        c.state.lastChild.textContent = STATE_LABEL[st] || st;
        c.state.querySelector('.ptd-dot').classList.toggle('ptd-dot--pulse', st === 'starting' || st === 'stopping');

        var limits = c.data.limits || {};
        var cpuCap = limits.cpu || 100;
        var memCap = (limits.memory || 0) * 1048576;

        if (d && d.resources) {
            var cpu = Number(d.resources.cpu_absolute || 0);
            var mem = Number(d.resources.memory_bytes || 0);
            c.cpu.value.textContent = PTD.fmt.pct(cpu);
            c.mem.value.textContent = PTD.fmt.bytes(mem);
            setBar(c.cpu, cpuCap ? cpu / cpuCap : 0);
            setBar(c.mem, memCap ? mem / memCap : 0);
        } else {
            c.cpu.value.textContent = '–';
            c.mem.value.textContent = '–';
            setBar(c.cpu, 0);
            setBar(c.mem, 0);
        }
    }

    function setBar(block, ratio) {
        var r = Math.max(0, Math.min(1, ratio || 0));
        block.bar.style.width = (r * 100).toFixed(1) + '%';
        block.meter.setAttribute('data-level', r >= 0.9 ? 'danger' : r >= 0.75 ? 'warn' : 'ok');
    }

    /* =====================================================================
       Kopfbereich
       ===================================================================== */

    function buildHero() {
        var name = userName();
        hero = el('section', { id: 'ptd-hero', 'data-ptd-own': '' }, [
            el('div', {}, [
                el('h1', { text: greeting() + (name ? ', ' + name : '') }),
                el('p', { id: 'ptd-hero-sub', text: 'Alle Server im Blick.' })
            ]),
            el('div', { class: 'ptd-hero-stats', id: 'ptd-hero-stats' })
        ]);
        return hero;
    }

    function paintHero(list) {
        var host = qs('#ptd-hero-stats');
        if (!host) return;
        var online = 0, mem = 0, cpu = 0;
        list.forEach(function (s) {
            var d = live[s.id];
            if (d && d.state === 'running') online++;
            if (d && d.resources) {
                mem += Number(d.resources.memory_bytes || 0);
                cpu += Number(d.resources.cpu_absolute || 0);
            }
        });

        host.innerHTML = '';
        function stat(value, label, tone) {
            host.appendChild(el('div', { class: 'ptd-hero-stat', 'data-tone': tone || null }, [
                el('b', { text: value }),
                el('span', { text: label })
            ]));
        }
        stat(String(list.length), 'Server');
        stat(online + '/' + list.length, 'Online', online ? 'ok' : null);
        stat(PTD.fmt.bytes(mem), 'RAM gesamt');
        stat(PTD.fmt.pct(cpu), 'CPU gesamt');

        var sub = qs('#ptd-hero-sub');
        if (sub) {
            sub.textContent = list.length
                ? (online ? online + ' von ' + list.length + ' Servern laufen gerade.' : 'Aktuell laeuft kein Server.')
                : 'Noch keine Server vorhanden.';
        }
    }

    /* =====================================================================
       Ein- und Aushaengen
       ===================================================================== */

    function servers() {
        return (PTD.rail && PTD.rail.servers()) || PTD.cache.get('servers', 120000) || [];
    }

    function mount() {
        if (!active()) { unmount(); return; }
        var list = servers();
        if (!list.length) {
            if (PTD.rail) PTD.rail.reload();
            return;
        }

        var root = PTD.contentRoot();
        if (!root) return;

        if (!hero) buildHero();
        if (!grid) grid = el('div', { id: 'ptd-overview', 'data-ptd-own': '' });

        if (hero.parentNode !== root) root.insertBefore(hero, root.firstChild);

        /* Das Raster kommt dorthin, wo das Panel seine eigene Liste rendert –
           so bleibt dessen Ueberschrift oben stehen und wirkt nicht verwaist. */
        if (!grid.parentNode) {
            var anchor = qs('[data-ptd="server-card"]');
            var host = anchor && anchor.parentNode && !PTD.isOurs(anchor.parentNode) ? anchor.parentNode : null;
            if (host) host.insertBefore(grid, anchor);
            else root.insertBefore(grid, hero.nextSibling);
        }

        document.documentElement.setAttribute('data-ptd-overview', '1');

        var seen = {};
        list.forEach(function (s) {
            seen[s.id] = 1;
            if (!cards[s.id]) {
                cards[s.id] = card(s);
                grid.appendChild(cards[s.id].node);
            } else {
                cards[s.id].data = s;
            }
            paintCard(cards[s.id]);
        });
        Object.keys(cards).forEach(function (id) {
            if (seen[id]) return;
            if (cards[id].node.parentNode) cards[id].node.parentNode.removeChild(cards[id].node);
            delete cards[id];
        });

        paintHero(list);
        ensurePolling(list);
    }

    function unmount() {
        if (hero && hero.parentNode) hero.parentNode.removeChild(hero);
        if (grid && grid.parentNode) grid.parentNode.removeChild(grid);
        document.documentElement.removeAttribute('data-ptd-overview');
        stopPolling();
    }

    /* =====================================================================
       Ersatzabfrage, falls das Panel selbst keine Werte liefert
       ===================================================================== */

    function sweep(list) {
        ownPolling = true;
        list.slice(0, 24).forEach(function (s, i) {
            if (s.suspended) return;
            setTimeout(function () {
                if (!active()) return;
                PTD.api('/api/client/servers/' + s.id + '/resources').then(function (res) {
                    var a = res && res.attributes;
                    if (!a) return;
                    record(s.id, a.current_state, a.resources, false);
                }).catch(function () { /* einzelne Fehler ignorieren */ });
            }, i * 80);
        });
    }

    function ensurePolling(list) {
        if (pollTimer) return;

        /* Kurz warten: liefert das Panel selbst Werte, sparen wir uns die
           Abfragen. Kommt nichts, holen wir sie einmal aktiv und dann im
           Takt nach. */
        setTimeout(function () {
            if (!active() || heardAt) return;
            sweep(list);
        }, 900);

        pollTimer = setInterval(function () {
            if (!active()) { stopPolling(); return; }
            if (Date.now() - heardAt < 12000) { ownPolling = false; return; }
            sweep(list);
        }, 10000);
    }

    function stopPolling() {
        if (pollTimer) { clearInterval(pollTimer); pollTimer = null; }
        ownPolling = false;
    }

    function record(id, state, resources, fromPanel) {
        live[id] = { state: state || 'offline', resources: resources || null };
        if (fromPanel) heardAt = Date.now();
        if (cards[id]) paintCard(cards[id]);
        paintHero(servers());
    }

    /* =====================================================================
       Ereignisse
       ===================================================================== */

    PTD.bus.on('resources', function (r) {
        if (!r || !r.id) return;
        record(r.id, r.suspended ? 'suspended' : r.state, r.resources, true);
    });
    PTD.bus.on('servers', function () { mount(); });
    PTD.bus.on('tags', function () { cards = {}; if (grid) grid.innerHTML = ''; mount(); });
    PTD.bus.on('favorites', function () {
        Object.keys(cards).forEach(function (id) { paintPin(cards[id].pin, id); });
    });
    PTD.bus.on('scan', mount);
    PTD.bus.on('settings', function () { if (active()) mount(); else unmount(); });
    PTD.bus.on('route', function () {
        if (!active()) unmount();
        else setTimeout(mount, 80);
    });

    PTD.ready(function () { setTimeout(mount, 180); });

    PTD.overview = { mount: mount, unmount: unmount, live: function () { return live; } };
})();
