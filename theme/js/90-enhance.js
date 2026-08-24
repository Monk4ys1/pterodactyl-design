/* =========================================================================
   Nebula · 90-enhance.js
   Ergaenzungen am Rand: Serverangaben in der Kopfleiste, Fusszeile,
   Nach-oben-Knopf und der Markenkopf auf der Anmeldeseite.
   ========================================================================= */

(function () {
    'use strict';
    var PTD = window.PTD;
    if (!PTD) return;

    var el = PTD.el, qs = PTD.qs, icon = PTD.icon;

    var chips = null, uptimeChip = null, stateChip = null, addrChip = null;
    var info = null, infoFor = null;

    /* =====================================================================
       Zwischenablage
       ===================================================================== */

    function copy(text, label) {
        if (!text) return;
        if (navigator.clipboard && navigator.clipboard.writeText) {
            navigator.clipboard.writeText(text).then(
                function () { PTD.toast({ type: 'ok', title: 'Kopiert', msg: label || text }); },
                function () { window.prompt('Kopieren:', text); }
            );
        } else {
            window.prompt('Kopieren:', text);
        }
    }

    function chip(ico, text, title, onClick) {
        var node = el('span', {
            class: 'ptd-chip',
            role: onClick ? 'button' : null,
            tabindex: onClick ? '0' : null,
            title: title || text
        }, []);
        if (ico) node.insertAdjacentHTML('beforeend', icon(ico, 12));
        node.appendChild(el('span', { text: text }));
        if (onClick) {
            node.addEventListener('click', onClick);
            node.addEventListener('keydown', function (e) { if (e.key === 'Enter' || e.key === ' ') { e.preventDefault(); onClick(); } });
        }
        return node;
    }

    /* =====================================================================
       Serverangaben in der Kopfleiste
       ===================================================================== */

    var STATE_LABEL = { running: 'Online', starting: 'Startet', stopping: 'Stoppt', offline: 'Offline', missing: 'Fehlt' };
    var STATE_CLASS = { running: 'ptd-badge--ok', starting: 'ptd-badge--warn', stopping: 'ptd-badge--warn', missing: 'ptd-badge--danger' };

    function loadInfo() {
        var id = PTD.route.server;
        if (!id) return;
        if (infoFor === id && info) { paintChips(); return; }
        infoFor = id;
        info = PTD.cache.get('info:' + id, 300000);
        if (info) paintChips();

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

            info = {
                name: a.name, uuid: a.uuid, node: a.node,
                address: alloc ? ((alloc.ip_alias || alloc.ip) + ':' + alloc.port) : '',
                suspended: !!a.is_suspended
            };
            PTD.cache.set('info:' + id, info);
            paintChips();
        }).catch(function () { /* Angaben sind optional */ });
    }

    function mountChips() {
        var bar = qs('#ptd-topbar');
        if (!bar || !PTD.get('modules.enhance')) { removeChips(); return; }
        if (PTD.route.page !== 'server') { removeChips(); return; }

        if (!chips) {
            chips = el('div', { class: 'ptd-tb-chips' });
        }
        if (chips.parentNode !== bar) {
            var spacer = bar.querySelector('.ptd-tb-spacer');
            bar.insertBefore(chips, spacer);
            loadInfo();
        }
        paintChips();
    }

    function removeChips() { if (chips && chips.parentNode) chips.parentNode.removeChild(chips); }

    function paintChips() {
        if (!chips) return;
        chips.innerHTML = '';

        stateChip = el('span', { class: 'ptd-badge' }, [el('i', { class: 'ptd-dot' }), el('span', { text: 'Offline' })]);
        chips.appendChild(stateChip);
        paintState(PTD.store.state);

        if (info && info.address) {
            addrChip = chip('globe', info.address, 'Adresse kopieren', function () { copy(info.address, 'Serveradresse'); });
            chips.appendChild(addrChip);
        }

        uptimeChip = chip('clock', '–', 'Laufzeit');
        chips.appendChild(uptimeChip);

        if (info && info.uuid) {
            chips.appendChild(chip('copy', info.uuid.split('-')[0], 'Vollstaendige UUID kopieren', function () { copy(info.uuid, 'UUID'); }));
        }
        if (info && info.suspended) {
            chips.appendChild(el('span', { class: 'ptd-badge ptd-badge--danger', text: 'Gesperrt' }));
        }
        paintUptime();
    }

    function paintState(state) {
        if (!stateChip) return;
        stateChip.className = 'ptd-badge ' + (STATE_CLASS[state] || '');
        stateChip.lastChild.textContent = STATE_LABEL[state] || state;
        var dot = stateChip.querySelector('.ptd-dot');
        if (dot) dot.classList.toggle('ptd-dot--pulse', state === 'starting' || state === 'stopping');
    }

    function paintUptime() {
        if (!uptimeChip) return;
        var s = PTD.store.lastStats;
        uptimeChip.lastChild.textContent = (s && s.uptime) ? PTD.fmt.duration(s.uptime) : '–';
    }

    setInterval(function () {
        if (!uptimeChip || !uptimeChip.parentNode) return;
        var s = PTD.store.lastStats;
        if (s && s.uptime && PTD.store.state === 'running') { s.uptime += 1000; paintUptime(); }
    }, 1000);

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

        app.appendChild(el('div', { 'data-ptd': 'footer', 'data-ptd-own': '' }, [
            el('span', {}, [
                el('span', { text: 'Nebula ' }),
                el('b', { text: 'v' + PTD.version, style: { color: 'var(--ptd-muted)' } }),
                el('span', { class: 'ptd-foot-dot', text: '·' }),
                el('span', { text: 'Design fuer Pterodactyl' })
            ]),
            el('span', {}, [
                el('a', {
                    href: '#', text: 'Einstellungen',
                    onclick: function (e) { e.preventDefault(); PTD.settingsPanel.open(); }
                }),
                el('span', { class: 'ptd-foot-dot', text: '·' }),
                el('a', {
                    href: '#', text: 'Tastenkuerzel',
                    onclick: function (e) { e.preventDefault(); if (PTD.shortcuts) PTD.shortcuts.show(); }
                })
            ])
        ]));
    }

    /* =====================================================================
       Anmeldeseite
       ===================================================================== */

    var MARK = '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" ' +
        'stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round">' +
        '<path d="M3 7.5 12 2l9 5.5v9L12 22l-9-5.5Z"/><path d="M12 22V12"/><path d="m3 7.5 9 4.5 9-4.5"/></svg>';

    function panelName() {
        return (document.title || '').split(/[|\-–]/)[0].trim() || 'Pterodactyl';
    }

    function mountAuth() {
        if (PTD.route.page !== 'auth') return;
        var card = qs('[data-ptd="auth-card"]');
        if (!card) return;

        if (!qs('#ptd-auth-brand')) {
            var brand = el('div', { id: 'ptd-auth-brand', 'data-ptd-own': '' }, []);
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
            themeBtn.insertAdjacentHTML('beforeend', icon('sparkles', 13));
            themeBtn.appendChild(el('span', { text: 'Design' }));
            themeBtn.addEventListener('click', function () { PTD.settingsPanel.open('design'); });

            card.appendChild(el('div', { id: 'ptd-auth-foot', 'data-ptd-own': '' }, [modeBtn, themeBtn]));
        }
    }

    /* =====================================================================
       Nach oben
       ===================================================================== */

    function mountTop() {
        if (qs('#ptd-totop')) return;
        var btn = el('button', {
            id: 'ptd-totop', type: 'button', 'aria-label': 'Nach oben',
            html: icon('arrowUp', 16),
            onclick: function () { window.scrollTo({ top: 0, behavior: PTD.get('motion') ? 'smooth' : 'auto' }); }
        });
        document.body.appendChild(btn);
        var update = PTD.debounce(function () { btn.classList.toggle('is-visible', window.scrollY > 380); }, 80);
        window.addEventListener('scroll', update, { passive: true });
    }

    /* =====================================================================
       Ereignisse
       ===================================================================== */

    function refresh() {
        mountChips();
        mountFooter();
        mountAuth();
    }

    PTD.bus.on('scan', refresh);
    PTD.bus.on('state', function (e) { paintState(e.to); });
    PTD.bus.on('stats', paintUptime);
    PTD.bus.on('settings', refresh);
    PTD.bus.on('route', function () {
        if (PTD.route.page !== 'server') { removeChips(); info = null; infoFor = null; }
        setTimeout(refresh, 120);
    });

    PTD.ready(function () { mountTop(); setTimeout(refresh, 200); });

    PTD.enhance = { refresh: refresh, copy: copy };
})();
