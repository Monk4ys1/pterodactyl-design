/* =========================================================================
   Nebula · 90-enhance.js
   Zusaetzliche Oberflaechenelemente: Serverleiste mit Kopierfeldern,
   Begruessung, Fusszeile, Nach-oben-Knopf, Schnellwechsler in der
   Navigation und Statusfarben fuer die Serverkacheln.
   ========================================================================= */

(function () {
    'use strict';
    var PTD = window.PTD;
    if (!PTD) return;

    var el = PTD.el, qs = PTD.qs, icon = PTD.icon;
    var serverInfo = null, infoFor = null;
    var bar = null, uptimeEl = null, stateEl = null, switcher = null;

    /* =====================================================================
       Hilfen
       ===================================================================== */

    function copy(text, label) {
        if (!text) return;
        if (navigator.clipboard && navigator.clipboard.writeText) {
            navigator.clipboard.writeText(text).then(function () {
                PTD.toast({ type: 'ok', title: 'Kopiert', msg: label || text });
            }, function () { window.prompt('Kopieren:', text); });
        } else {
            window.prompt('Kopieren:', text);
        }
    }

    function chip(ico, text, title, onClick) {
        var node = el('span', { class: 'ptd-sb-item', title: title || text }, []);
        node.insertAdjacentHTML('beforeend', icon(ico, 12));
        node.appendChild(el('span', { text: text }));
        if (onClick) node.addEventListener('click', onClick);
        return node;
    }

    /* =====================================================================
       Serverleiste
       ===================================================================== */

    function loadServerInfo() {
        var id = PTD.route.server;
        if (!id) return;
        if (infoFor === id && serverInfo) { paintBar(); return; }
        infoFor = id;
        serverInfo = PTD.cache.get('info:' + id, 300000);
        if (serverInfo) paintBar();
        PTD.api('/api/client/servers/' + id).then(function (res) {
            var a = res && res.attributes;
            if (!a) return;
            var alloc = null;
            try {
                var list = a.relationships.allocations.data;
                for (var i = 0; i < list.length; i++) {
                    if (list[i].attributes.is_default) { alloc = list[i].attributes; break; }
                }
                if (!alloc && list.length) alloc = list[0].attributes;
            } catch (e) { /* keine Allocation sichtbar */ }

            serverInfo = {
                name: a.name,
                uuid: a.uuid,
                identifier: a.identifier,
                node: a.node,
                description: a.description,
                address: alloc ? ((alloc.ip_alias || alloc.ip) + ':' + alloc.port) : '',
                suspended: !!a.is_suspended
            };
            PTD.cache.set('info:' + id, serverInfo);
            paintBar();
            paintSwitcher();
        }).catch(function () { /* Leiste bleibt reduziert */ });
    }

    function buildBar() {
        uptimeEl = el('span', { class: 'ptd-sb-item', title: 'Laufzeit' }, []);
        uptimeEl.insertAdjacentHTML('beforeend', icon('clock', 12));
        uptimeEl.appendChild(el('span', { text: '–' }));

        stateEl = el('span', { class: 'ptd-badge', 'data-ptd-state': 'offline' }, [
            el('i', { class: 'ptd-dot' }),
            el('span', { text: 'Offline' })
        ]);

        bar = el('div', { id: 'ptd-serverbar' }, []);
        return bar;
    }

    var STATE_LABEL = { running: 'Online', starting: 'Startet', stopping: 'Stoppt', offline: 'Offline', missing: 'Fehlt' };
    var STATE_CLASS = { running: 'ptd-badge--ok', starting: 'ptd-badge--warn', stopping: 'ptd-badge--warn', offline: '', missing: 'ptd-badge--danger' };

    function paintBar() {
        if (!bar) return;
        bar.innerHTML = '';
        var info = serverInfo || {};

        bar.appendChild(el('span', { class: 'ptd-sb-name', text: info.name || 'Server' }));
        bar.appendChild(stateEl);

        if (info.address) {
            bar.appendChild(chip('globe', info.address, 'Adresse kopieren', function () { copy(info.address, 'Serveradresse'); }));
        }
        if (info.node) {
            bar.appendChild(chip('server', info.node, 'Node'));
        }
        bar.appendChild(uptimeEl);
        bar.appendChild(el('span', { class: 'ptd-sb-spacer' }));
        if (info.uuid) {
            bar.appendChild(chip('copy', info.uuid.split('-')[0], 'Vollstaendige UUID kopieren', function () { copy(info.uuid, 'UUID'); }));
        }
        if (info.suspended) {
            bar.appendChild(el('span', { class: 'ptd-badge ptd-badge--danger', text: 'Gesperrt' }));
        }
        paintState(PTD.store.state);
        paintUptime();
    }

    function paintState(state) {
        if (!stateEl) return;
        stateEl.className = 'ptd-badge ' + (STATE_CLASS[state] || '');
        stateEl.setAttribute('data-ptd-state', state);
        stateEl.lastChild.textContent = STATE_LABEL[state] || state;
        var dot = stateEl.querySelector('.ptd-dot');
        if (dot) dot.classList.toggle('ptd-dot--pulse', state === 'starting' || state === 'stopping');
    }

    function paintUptime() {
        if (!uptimeEl) return;
        var s = PTD.store.lastStats;
        uptimeEl.lastChild.textContent = (s && s.uptime) ? PTD.fmt.duration(s.uptime) : '–';
    }

    function mountBar() {
        if (!PTD.get('modules.enhance') || PTD.route.page !== 'server') { unmountBar(); return; }
        var sub = qs('[data-ptd="subnav"]');
        if (!sub) return;
        if (!bar) buildBar();
        if (bar.parentNode !== sub.parentNode || bar.previousElementSibling !== sub) {
            sub.parentNode.insertBefore(bar, sub.nextSibling);
            loadServerInfo();
            paintBar();
        }
    }

    function unmountBar() {
        if (bar && bar.parentNode) bar.parentNode.removeChild(bar);
    }

    /* =====================================================================
       Schnellwechsler in der Navigation
       ===================================================================== */

    function mountSwitcher() {
        if (!PTD.get('modules.enhance') || !PTD.get('modules.palette')) { unmountSwitcher(); return; }
        var actions = qs('[data-ptd="nav-actions"]');
        if (!actions) return;
        if (!switcher) {
            switcher = el('button', { id: 'ptd-switcher', type: 'button', title: 'Server wechseln (Strg + K)' }, []);
            switcher.insertAdjacentHTML('beforeend', icon('server', 13));
            switcher.appendChild(el('span', { class: 'ptd-sw-name', text: 'Server' }));
            switcher.insertAdjacentHTML('beforeend', icon('chevron', 12));
            switcher.addEventListener('click', function () { if (PTD.palette) PTD.palette.open(); });
        }
        if (switcher.parentNode !== actions.parentNode) {
            actions.parentNode.insertBefore(switcher, actions);
        }
        paintSwitcher();
    }

    function unmountSwitcher() {
        if (switcher && switcher.parentNode) switcher.parentNode.removeChild(switcher);
    }

    function paintSwitcher() {
        if (!switcher) return;
        var label = (PTD.route.page === 'server' && serverInfo && serverInfo.name) ? serverInfo.name : 'Server wechseln';
        var span = switcher.querySelector('.ptd-sw-name');
        if (span) span.textContent = label;
    }

    /* =====================================================================
       Begruessung auf dem Dashboard
       ===================================================================== */

    function greetingText() {
        var h = new Date().getHours();
        if (h < 5) return 'Gute Nacht';
        if (h < 11) return 'Guten Morgen';
        if (h < 18) return 'Guten Tag';
        return 'Guten Abend';
    }

    function userName() {
        try {
            var u = window.PterodactylUser;
            if (u && u.username) return u.username;
        } catch (e) { /* nicht vorhanden */ }
        return null;
    }

    function mountGreeting() {
        var existing = qs('#ptd-greeting');
        if (!PTD.get('modules.enhance') || !PTD.get('greeting') || PTD.route.page !== 'dashboard') {
            if (existing) existing.remove();
            return;
        }
        if (existing) return;
        var root = PTD.contentRoot();
        if (!root) return;
        var name = userName();
        var node = el('div', {
            id: 'ptd-greeting',
            style: {
                maxWidth: 'var(--ptd-max-w)', margin: '1.4rem auto .2rem',
                padding: '0 1.25rem', display: 'flex', alignItems: 'baseline',
                gap: '.6rem', flexWrap: 'wrap'
            }
        }, [
            el('span', {
                text: greetingText() + (name ? ', ' + name : '') + '.',
                style: { fontSize: '1.4rem', fontWeight: '700', letterSpacing: '-.025em', color: 'var(--ptd-text)' }
            }),
            el('span', {
                text: 'Deine Server im Ueberblick.',
                style: { fontSize: '.85rem', color: 'var(--ptd-muted)' }
            })
        ]);
        root.insertBefore(node, root.firstChild);
    }

    /* =====================================================================
       Fusszeile
       ===================================================================== */

    function mountFooter() {
        var existing = qs('[data-ptd="footer"]');
        if (!PTD.get('modules.enhance') || !PTD.get('footer') || PTD.route.page === 'auth') {
            if (existing) existing.remove();
            return;
        }
        if (existing) return;
        var app = qs('#app');
        if (!app) return;
        var node = el('div', { 'data-ptd': 'footer' }, [
            el('span', {}, [
                el('span', { text: 'Nebula ' }),
                el('b', { text: 'v' + PTD.version, style: { color: 'var(--ptd-muted)' } }),
                el('span', { class: 'ptd-foot-dot', text: '·' }),
                el('span', { text: 'Design fuer Pterodactyl' })
            ]),
            el('span', {}, [
                el('a', { href: '#', text: 'Einstellungen', onclick: function (e) { e.preventDefault(); if (PTD.settingsPanel) PTD.settingsPanel.open(); } }),
                el('span', { class: 'ptd-foot-dot', text: '·' }),
                el('a', { href: '#', text: 'Tastenkuerzel', onclick: function (e) { e.preventDefault(); if (PTD.shortcuts) PTD.shortcuts.show(); } })
            ])
        ]);
        app.appendChild(node);
    }

    /* =====================================================================
       Markenkopf und Fusszeile der Login-Karte
       ===================================================================== */

    var MARK = '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" ' +
        'stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round">' +
        '<path d="M3 7.5 12 2l9 5.5v9L12 22l-9-5.5Z"/><path d="M12 22V12"/><path d="m3 7.5 9 4.5 9-4.5"/></svg>';

    function panelName() {
        var t = (document.title || '').split(/[|\-–]/)[0].trim();
        return t || 'Pterodactyl';
    }

    function mountAuthBrand() {
        if (PTD.route.page !== 'auth') return;
        var card = qs('[data-ptd="auth-card"]');
        if (!card) return;

        if (!qs('#ptd-auth-brand')) {
            var brand = el('div', { id: 'ptd-auth-brand' }, []);
            brand.appendChild(el('span', { class: 'ptd-mark', html: MARK }));
            brand.appendChild(el('h1', { text: panelName() }));
            brand.appendChild(el('p', { text: 'Melde dich an, um deine Server zu verwalten.' }));
            card.insertBefore(brand, card.firstChild);
        }

        if (!qs('#ptd-auth-foot')) {
            var modeBtn = el('button', { type: 'button' }, []);
            function paintMode() {
                var light = document.documentElement.getAttribute('data-ptd-mode') === 'light';
                modeBtn.innerHTML = '';
                modeBtn.insertAdjacentHTML('beforeend', icon(light ? 'moon' : 'sun', 13));
                modeBtn.appendChild(el('span', { text: light ? 'Dunkel' : 'Hell' }));
            }
            modeBtn.addEventListener('click', function () {
                PTD.set('mode', document.documentElement.getAttribute('data-ptd-mode') === 'light' ? 'dark' : 'light');
                paintMode();
            });
            paintMode();

            var themeBtn = el('button', { type: 'button' }, []);
            themeBtn.insertAdjacentHTML('beforeend', icon('wand', 13));
            themeBtn.appendChild(el('span', { text: 'Design' }));
            themeBtn.addEventListener('click', function () { if (PTD.settingsPanel) PTD.settingsPanel.open(); });

            card.appendChild(el('div', { id: 'ptd-auth-foot' }, [modeBtn, themeBtn]));
        }
    }

    /* =====================================================================
       Nach-oben-Knopf
       ===================================================================== */

    function mountTop() {
        if (qs('#ptd-totop')) return;
        var btn = el('button', {
            id: 'ptd-totop', type: 'button', 'aria-label': 'Nach oben',
            html: icon('arrowUp', 17),
            onclick: function () { window.scrollTo({ top: 0, behavior: PTD.get('motion') ? 'smooth' : 'auto' }); }
        });
        document.body.appendChild(btn);
        var update = PTD.debounce(function () {
            btn.classList.toggle('is-visible', window.scrollY > 420);
        }, 80);
        window.addEventListener('scroll', update, { passive: true });
    }

    /* =====================================================================
       Statusfarben der Serverkacheln
       ===================================================================== */

    PTD.bus.on('resources', function (r) {
        if (!r || !r.id) return;
        var card = qs('[data-ptd="server-card"][data-ptd-sid="' + r.id + '"]');
        if (!card) return;
        card.setAttribute('data-ptd-state', r.suspended ? 'suspended' : (r.state || 'offline'));
    });

    /* =====================================================================
       Laufzeit-Ticker
       ===================================================================== */

    setInterval(function () {
        if (!bar || !bar.parentNode) return;
        var s = PTD.store.lastStats;
        if (s && s.uptime && PTD.store.state === 'running') {
            s.uptime += 1000;
            paintUptime();
        }
    }, 1000);

    /* =====================================================================
       Ereignisse
       ===================================================================== */

    function refresh() {
        mountBar();
        mountSwitcher();
        mountGreeting();
        mountFooter();
        mountAuthBrand();
    }

    PTD.bus.on('scan', refresh);
    PTD.bus.on('state', function (e) { paintState(e.to); });
    PTD.bus.on('stats', paintUptime);
    PTD.bus.on('settings', refresh);
    PTD.bus.on('route', function () {
        if (PTD.route.page !== 'server') { unmountBar(); serverInfo = null; infoFor = null; }
        setTimeout(refresh, 120);
    });

    PTD.ready(function () {
        mountTop();
        setTimeout(refresh, 200);
    });

    PTD.enhance = { refresh: refresh, copy: copy };
})();
