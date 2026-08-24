/* =========================================================================
   Nebula · 25-rail.js
   Seitenschiene und Kopfleiste.

   Die Eintraege der Panel-eigenen Navigation werden gespiegelt statt
   nachgebaut: Was Pterodactyl dort rendert (auch kuenftige Eintraege),
   erscheint automatisch in der Schiene. Danach wird die Originalleiste
   ausgeblendet – entfernt wird sie nie, damit React weiterarbeiten kann.
   ========================================================================= */

(function () {
    'use strict';
    var PTD = window.PTD;
    if (!PTD) return;

    var el = PTD.el, qs = PTD.qs, qsa = PTD.qsa, icon = PTD.icon;

    var rail = null, scrim = null, topbar = null;
    var listHost = null, favHost = null, navHost = null, crumbHost = null, clockEl = null;
    var servers = [], loading = false, clockTimer = null;

    /* =====================================================================
       Zuordnung bekannter Ziele zu Symbolen und Namen
       ===================================================================== */

    var NAV_MAP = [
        { test: /^\/$/,              icon: 'home',   label: 'Dashboard' },
        { test: /^\/account\/api/,   icon: 'key',    label: 'API-Zugangsdaten' },
        { test: /^\/account\/ssh/,   icon: 'shield', label: 'SSH-Schluessel' },
        { test: /^\/account\/activity/, icon: 'activity', label: 'Aktivitaet' },
        { test: /^\/account/,        icon: 'user',   label: 'Konto' },
        { test: /^\/admin/,          icon: 'shield', label: 'Administration' },
        { test: /logout/,            icon: 'logOut', label: 'Abmelden' }
    ];

    function describe(href, fallback) {
        for (var i = 0; i < NAV_MAP.length; i++) {
            if (NAV_MAP[i].test.test(href)) return NAV_MAP[i];
        }
        return { icon: 'chevR', label: fallback || href };
    }

    var TAB_LABEL = {
        '': 'Konsole', console: 'Konsole', files: 'Dateien', databases: 'Datenbanken',
        schedules: 'Zeitplaene', users: 'Benutzer', backups: 'Backups', network: 'Netzwerk',
        startup: 'Startparameter', settings: 'Einstellungen', activity: 'Aktivitaet',
        api: 'API-Zugangsdaten', ssh: 'SSH-Schluessel'
    };

    /* =====================================================================
       Aufbau
       ===================================================================== */

    function markSvg() {
        return '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" ' +
            'stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round">' +
            '<path d="M3 7.5 12 2l9 5.5v9L12 22l-9-5.5Z"/><path d="M12 22V12"/><path d="m3 7.5 9 4.5 9-4.5"/></svg>';
    }

    function panelName() {
        var brand = qs('#navigation a[href="/"]');
        var t = brand && brand.textContent.trim();
        if (t) return t;
        return (document.title || 'Panel').split(/[|\-–]/)[0].trim() || 'Panel';
    }

    function userName() {
        try {
            var u = window.PterodactylUser;
            if (u && u.username) return u.username;
        } catch (e) { /* nicht vorhanden */ }
        return null;
    }

    function railItem(opts) {
        var node = el(opts.href ? 'a' : 'button', {
            class: 'ptd-rail-item',
            href: opts.href || null,
            type: opts.href ? null : 'button',
            'data-tip': opts.label,
            'data-ptd-server': opts.server || null,
            'data-state': opts.state || null,
            style: opts.color ? { '--tag': opts.color } : null
        }, []);

        var ico = el('span', { class: 'ptd-ri-icon' });
        if (opts.initials) ico.textContent = opts.initials;
        else ico.innerHTML = icon(opts.icon || 'chevR', 16);
        node.appendChild(ico);
        node.appendChild(el('span', { class: 'ptd-ri-label', text: opts.label }));

        if (opts.server) {
            node.appendChild(el('span', { class: 'ptd-ri-state' }));
            var pin = el('button', {
                class: 'ptd-rail-pin',
                type: 'button',
                'aria-pressed': opts.pinned ? 'true' : 'false',
                'aria-label': opts.pinned ? 'Loesen' : 'Anheften',
                html: icon('pin', 12)
            });
            pin.addEventListener('click', function (e) {
                e.preventDefault();
                e.stopPropagation();
                toggleFavorite(opts.server);
            });
            node.appendChild(pin);
        }

        if (opts.onClick) {
            node.addEventListener('click', function (e) {
                if (opts.href) { e.preventDefault(); }
                opts.onClick(e);
            });
        } else if (opts.href) {
            node.addEventListener('click', function (e) {
                if (e.metaKey || e.ctrlKey || e.shiftKey || e.button !== 0) return;
                if (/logout/.test(opts.href) || opts.href.indexOf('/admin') === 0) return;
                e.preventDefault();
                PTD.navigate(opts.href);
                closeMobile();
            });
        }
        return node;
    }

    function build() {
        scrim = el('div', { id: 'ptd-rail-scrim' });
        scrim.addEventListener('click', closeMobile);

        navHost = el('div', { class: 'ptd-rail-section' });
        favHost = el('div', { class: 'ptd-rail-section' });
        listHost = el('div', { class: 'ptd-rail-section' });

        var search = el('button', {
            class: 'ptd-rail-search',
            type: 'button',
            'aria-label': 'Suchen',
            onclick: function () { if (PTD.palette) PTD.palette.open(); }
        }, []);
        search.insertAdjacentHTML('beforeend', icon('search', 14));
        search.appendChild(el('span', { text: 'Suchen …' }));
        search.insertAdjacentHTML('beforeend', '<b class="ptd-kbd">⌘K</b>');

        var collapse = el('button', {
            class: 'ptd-rail-collapse',
            type: 'button',
            'aria-label': 'Schiene ein-/ausklappen',
            html: icon('chevL', 15),
            onclick: function () {
                PTD.set('rail', PTD.get('rail') === 'mini' ? 'full' : 'mini');
            }
        });

        var user = el('a', { class: 'ptd-rail-user', href: '/account' }, [
            el('span', { class: 'ptd-rail-avatar', text: PTD.fmt.initials(userName() || 'Konto') }),
            el('span', { class: 'ptd-rail-uname', text: userName() || 'Konto' })
        ]);
        user.addEventListener('click', function (e) { e.preventDefault(); PTD.navigate('/account'); closeMobile(); });

        rail = el('aside', { id: 'ptd-rail', 'aria-label': 'Hauptnavigation' }, [
            el('div', { class: 'ptd-rail-head' }, [
                el('span', { class: 'ptd-rail-mark', html: markSvg() }),
                el('span', { class: 'ptd-rail-name', text: panelName() }),
                collapse
            ]),
            search,
            el('div', { class: 'ptd-rail-body' }, [navHost, favHost, listHost]),
            el('div', { class: 'ptd-rail-foot' }, [
                user,
                el('button', {
                    class: 'ptd-rail-fbtn', type: 'button', 'aria-label': 'Hell / Dunkel',
                    html: icon('sun', 15),
                    onclick: function () { PTD.set('mode', PTD.get('mode') === 'light' ? 'dark' : 'light'); }
                }),
                el('button', {
                    class: 'ptd-rail-fbtn', type: 'button', 'aria-label': 'Einstellungen',
                    html: icon('settings', 15),
                    onclick: function () { if (PTD.settingsPanel) PTD.settingsPanel.open(); }
                })
            ])
        ]);

        document.body.appendChild(scrim);
        document.body.appendChild(rail);
    }

    /* =====================================================================
       Kopfleiste
       ===================================================================== */

    function buildTopbar() {
        crumbHost = el('nav', { class: 'ptd-crumbs', 'aria-label': 'Pfad' });
        clockEl = el('span', { class: 'ptd-tb-clock' });

        var menu = el('button', {
            class: 'ptd-tb-menu', type: 'button', 'aria-label': 'Menue',
            html: icon('menu', 16),
            onclick: openMobile
        });

        topbar = el('header', { id: 'ptd-topbar', 'data-ptd-own': '' }, [
            menu, crumbHost, el('span', { class: 'ptd-tb-spacer' }), clockEl
        ]);

        topbar.appendChild(el('button', {
            class: 'ptd-tb-btn', type: 'button', 'aria-label': 'Suchen (Strg + K)',
            'data-ptd-tip': 'Suchen · Strg K',
            html: icon('search', 16),
            onclick: function () { if (PTD.palette) PTD.palette.open(); }
        }));

        topbar.appendChild(el('button', {
            id: 'ptd-tb-dock', class: 'ptd-tb-btn', type: 'button',
            'aria-label': 'Mini-Konsole', 'data-ptd-tip': 'Mini-Konsole',
            'aria-pressed': 'false',
            html: icon('pip', 16),
            onclick: function () { if (PTD.dock) PTD.dock.toggle(); }
        }));

        topbar.appendChild(el('button', {
            id: 'ptd-tb-focus', class: 'ptd-tb-btn', type: 'button',
            'aria-label': 'Fokusmodus', 'data-ptd-tip': 'Fokusmodus · Strg ⇧ Z',
            'aria-pressed': 'false',
            html: icon('eye', 16),
            onclick: toggleFocus
        }));

        return topbar;
    }

    function toggleFocus() {
        var h = document.documentElement;
        var on = h.getAttribute('data-ptd-focus') === '1';
        if (on) h.removeAttribute('data-ptd-focus'); else h.setAttribute('data-ptd-focus', '1');
        var b = qs('#ptd-tb-focus');
        if (b) b.setAttribute('aria-pressed', on ? 'false' : 'true');
        setTimeout(function () { window.dispatchEvent(new Event('resize')); }, 60);
    }

    function mountTopbar() {
        if (!topbar) buildTopbar();
        var nav = qs('#navigation');
        var anchor = nav || qs('#app');
        if (!anchor) return;
        var parent = nav ? nav.parentNode : anchor;
        if (topbar.parentNode === parent && topbar.previousElementSibling === nav) return;
        if (nav) parent.insertBefore(topbar, nav.nextSibling);
        else anchor.insertBefore(topbar, anchor.firstChild);
    }

    function paintCrumbs() {
        if (!crumbHost) return;
        var r = PTD.route;
        var parts = [];

        function link(label, href) {
            var a = el('a', { href: href, text: label });
            a.addEventListener('click', function (e) { e.preventDefault(); PTD.navigate(href); });
            return a;
        }

        if (r.page === 'server') {
            parts.push(link('Server', '/'));
            var info = servers.filter(function (s) { return s.id === r.server; })[0];
            parts.push(el('span', { class: 'ptd-cr-sep', text: '/' }));
            parts.push(link(info ? info.name : (r.server || 'Server'), '/server/' + r.server));
            parts.push(el('span', { class: 'ptd-cr-sep', text: '/' }));
            parts.push(el('span', { class: 'ptd-cr-now', text: TAB_LABEL[r.sub || ''] || r.sub }));
        } else if (r.page === 'account') {
            parts.push(link('Konto', '/account'));
            if (r.sub) {
                parts.push(el('span', { class: 'ptd-cr-sep', text: '/' }));
                parts.push(el('span', { class: 'ptd-cr-now', text: TAB_LABEL[r.sub] || r.sub }));
            }
        } else if (r.page === 'admin') {
            parts.push(el('span', { class: 'ptd-cr-now', text: 'Administration' }));
        } else {
            parts.push(el('span', { class: 'ptd-cr-now', text: 'Server' }));
        }

        crumbHost.innerHTML = '';
        parts.forEach(function (n) { crumbHost.appendChild(n); });
    }

    function startClock() {
        if (clockTimer) clearInterval(clockTimer);
        if (!PTD.get('clock')) { if (clockEl) clockEl.textContent = ''; return; }
        function tick() {
            if (!clockEl) return;
            var d = new Date();
            clockEl.textContent = ('0' + d.getHours()).slice(-2) + ':' + ('0' + d.getMinutes()).slice(-2);
        }
        tick();
        clockTimer = setInterval(tick, 20000);
    }

    /* =====================================================================
       Serverliste
       ===================================================================== */

    function tagOf(id, name) {
        if (PTD.tagOf) return PTD.tagOf(id, name);
        return { color: PTD.autoColor(id), label: PTD.fmt.initials(name) };
    }

    function favorites() { return PTD.get('favorites') || []; }

    function toggleFavorite(id) {
        var list = favorites().slice();
        var i = list.indexOf(id);
        if (i > -1) list.splice(i, 1); else list.push(id);
        PTD.settings.favorites = list;
        PTD.save();
        paintServers();
        PTD.bus.emit('favorites', list);
    }

    function loadServers(force) {
        if (loading) return;
        var cached = PTD.cache.get('servers', force ? 0 : 45000);
        if (cached) { servers = cached; paintServers(); paintCrumbs(); if (!force) return; }
        loading = true;
        PTD.api('/api/client?per_page=100').then(function (res) {
            loading = false;
            if (!res || !res.data) return;
            servers = res.data.map(function (row) {
                var a = row.attributes || {};
                var alloc = null;
                try {
                    var list = a.relationships.allocations.data;
                    for (var i = 0; i < list.length; i++) {
                        if (list[i].attributes.is_default) { alloc = list[i].attributes; break; }
                    }
                    if (!alloc && list.length) alloc = list[0].attributes;
                } catch (e) { /* keine Allocation sichtbar */ }
                return {
                    id: a.identifier,
                    name: a.name,
                    node: a.node,
                    address: alloc ? ((alloc.ip_alias || alloc.ip) + ':' + alloc.port) : '',
                    suspended: !!a.is_suspended,
                    limits: a.limits || {},
                    state: a.is_suspended ? 'suspended' : 'offline'
                };
            });
            PTD.cache.set('servers', servers);
            paintServers();
            paintCrumbs();
            PTD.bus.emit('servers', servers);
        }).catch(function () { loading = false; });
    }

    function section(title, count) {
        return el('div', { class: 'ptd-rail-title' }, [
            el('span', { text: title }),
            count === undefined ? null : el('b', { text: String(count) })
        ]);
    }

    function serverItem(s) {
        var tag = tagOf(s.id, s.name);
        var item = railItem({
            href: '/server/' + s.id,
            label: s.name,
            initials: tag.label,
            color: tag.color,
            server: s.id,
            state: s.state,
            pinned: favorites().indexOf(s.id) > -1
        });
        if (PTD.route.server === s.id) item.classList.add('is-active');
        return item;
    }

    function paintServers() {
        if (!listHost) return;
        var favs = favorites();
        var pinned = servers.filter(function (s) { return favs.indexOf(s.id) > -1; });
        var rest = servers.filter(function (s) { return favs.indexOf(s.id) === -1; });

        favHost.innerHTML = '';
        if (pinned.length) {
            favHost.appendChild(section('Angeheftet', pinned.length));
            pinned.forEach(function (s) { favHost.appendChild(serverItem(s)); });
        }

        listHost.innerHTML = '';
        listHost.appendChild(section('Server', servers.length));
        if (!servers.length) {
            listHost.appendChild(el('div', {
                class: 'ptd-list-empty',
                style: { padding: '.3rem .6rem' },
                text: loading ? 'Lade …' : 'Keine Server'
            }));
        }
        rest.slice(0, 40).forEach(function (s) { listHost.appendChild(serverItem(s)); });
    }

    function paintNav() {
        if (!navHost) return;
        var seen = {};
        var links = [];

        qsa('#navigation a[href]').forEach(function (a) {
            var href = a.getAttribute('href');
            if (!href || href.charAt(0) !== '/' || seen[href]) return;
            seen[href] = 1;
            var d = describe(href, (a.textContent || '').trim());
            links.push({ href: href, icon: d.icon, label: d.label });
        });

        /* Fallback, falls die Panel-Navigation (noch) nicht gerendert ist */
        if (!links.length) {
            links = [
                { href: '/', icon: 'home', label: 'Dashboard' },
                { href: '/account', icon: 'user', label: 'Konto' }
            ];
        }

        navHost.innerHTML = '';
        navHost.appendChild(section('Navigation'));
        var path = location.pathname.replace(/\/$/, '') || '/';
        links.forEach(function (l) {
            var item = railItem(l);
            var h = l.href.replace(/\/$/, '') || '/';
            if (h === path || (h !== '/' && path.indexOf(h + '/') === 0)) {
                item.setAttribute('aria-current', 'page');
            }
            navHost.appendChild(item);
        });
    }

    /* =====================================================================
       Mobiles Ausklappen
       ===================================================================== */

    function openMobile()  { document.documentElement.setAttribute('data-ptd-railopen', '1'); }
    function closeMobile() { document.documentElement.removeAttribute('data-ptd-railopen'); }

    /* =====================================================================
       Zustandsaktualisierung
       ===================================================================== */

    function setState(id, state) {
        var s = servers.filter(function (x) { return x.id === id; })[0];
        if (s) { if (s.suspended) state = 'suspended'; s.state = state; }
        qsa('#ptd-rail .ptd-rail-item[data-ptd-server="' + id + '"]').forEach(function (n) {
            n.setAttribute('data-state', state);
        });
    }

    function markActive() {
        qsa('#ptd-rail .ptd-rail-item').forEach(function (n) {
            n.classList.remove('is-active');
            n.removeAttribute('aria-current');
        });
        paintNav();
        qsa('#ptd-rail .ptd-rail-item[data-ptd-server="' + PTD.route.server + '"]').forEach(function (n) {
            n.classList.add('is-active');
        });
    }

    /* =====================================================================
       Ein- und Aushaengen
       ===================================================================== */

    function mount() {
        if (!PTD.get('modules.rail')) { unmount(); return; }
        if (PTD.route.page === 'auth') { unmount(); return; }
        if (!rail) build();
        if (!rail.parentNode) { document.body.appendChild(scrim); document.body.appendChild(rail); }
        mountTopbar();
        paintNav();
        paintServers();
        paintCrumbs();
        startClock();
        if (!servers.length) loadServers();
    }

    function unmount() {
        if (rail && rail.parentNode) rail.parentNode.removeChild(rail);
        if (scrim && scrim.parentNode) scrim.parentNode.removeChild(scrim);
        if (topbar && topbar.parentNode) topbar.parentNode.removeChild(topbar);
        if (clockTimer) { clearInterval(clockTimer); clockTimer = null; }
    }

    /* =====================================================================
       Ereignisse
       ===================================================================== */

    PTD.bus.on('scan', mount);
    PTD.bus.on('settings', function () { if (PTD.get('modules.rail')) { mount(); startClock(); } else unmount(); });
    PTD.bus.on('route', function () {
        closeMobile();
        setTimeout(function () { markActive(); paintCrumbs(); }, 40);
        if (PTD.route.server) {
            var rec = (PTD.get('recents') || []).filter(function (x) { return x !== PTD.route.server; });
            rec.unshift(PTD.route.server);
            PTD.settings.recents = rec.slice(0, 8);
            PTD.save();
        }
    });
    PTD.bus.on('resources', function (r) { if (r && r.id) setState(r.id, r.suspended ? 'suspended' : (r.state || 'offline')); });
    PTD.bus.on('state', function (e) { if (PTD.route.server) setState(PTD.route.server, e.to); });
    PTD.bus.on('tags', function () { paintServers(); });

    PTD.ready(function () { setTimeout(mount, 60); });

    PTD.rail = {
        mount: mount, unmount: unmount, servers: function () { return servers; },
        reload: function () { loadServers(true); },
        toggleFavorite: toggleFavorite,
        openMobile: openMobile, closeMobile: closeMobile,
        toggleFocus: toggleFocus
    };
})();
