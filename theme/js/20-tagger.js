/* =========================================================================
   Nebula · 20-tagger.js
   Versieht die von React erzeugten Elemente mit stabilen data-ptd-Attributen.
   Dadurch funktioniert das komplette Styling ohne Rebuild des Frontends und
   unabhaengig von den gehashten Klassennamen der Build-Pipeline.
   ========================================================================= */

(function () {
    'use strict';
    var PTD = window.PTD;
    if (!PTD) return;

    var qs = PTD.qs, qsa = PTD.qsa;

    /* =====================================================================
       Hilfsfunktionen
       ===================================================================== */

    function mark(node, value) {
        if (!node || node.getAttribute('data-ptd') === value) return false;
        node.setAttribute('data-ptd', value);
        return true;
    }

    function hasBg(node) {
        var c = getComputedStyle(node).backgroundColor;
        var m = c.match(/rgba?\(([^)]+)\)/);
        if (!m) return false;
        var p = m[1].split(',').map(parseFloat);
        return p.length < 4 || p[3] > 0.03;
    }

    function rgbToHsl(r, g, b) {
        r /= 255; g /= 255; b /= 255;
        var max = Math.max(r, g, b), min = Math.min(r, g, b);
        var h = 0, s = 0, l = (max + min) / 2;
        var d = max - min;
        if (d) {
            s = l > 0.5 ? d / (2 - max - min) : d / (max + min);
            if (max === r) h = ((g - b) / d + (g < b ? 6 : 0));
            else if (max === g) h = (b - r) / d + 2;
            else h = (r - g) / d + 4;
            h *= 60;
        }
        return [h, s, l];
    }

    /* =====================================================================
       Buttons: Variante bestimmen
       Zuerst ueber die Tailwind-Klassen (dort kennen wir das Original),
       sonst ueber den Farbton der berechneten Hintergrundfarbe.
       ===================================================================== */

    var SKIP_IN = '#ptd-drawer,#ptd-palette,#ptd-console-bar,#ptd-keys,#ptd-toasts,#ptd-fab,'
    + '#ptd-serverbar,#ptd-totop,#ptd-switcher,#ptd-greeting,#ptd-charts,#ptd-log-view,'
    + '#ptd-auth-brand,#ptd-auth-foot,[data-ptd="footer"]';

    function classifyButton(btn) {
        var cls = typeof btn.className === 'string' ? btn.className : '';
        if (/\bbg-(red|rose)-\d/.test(cls)) return 'danger';
        if (/\bbg-(green|emerald)-\d/.test(cls)) return 'success';
        if (/\bbg-(primary|blue|indigo|cyan)-\d/.test(cls)) return 'primary';
        if (/\bbg-(neutral|gray|slate)-\d/.test(cls)) return 'secondary';

        var bg = getComputedStyle(btn).backgroundColor;
        var m = bg.match(/rgba?\((\d+),\s*(\d+),\s*(\d+)(?:,\s*([\d.]+))?\)/);
        if (!m) return null;
        var a = m[4] === undefined ? 1 : parseFloat(m[4]);
        if (a < 0.08) return null;                       /* durchsichtige Icon-Buttons */

        var hsl = rgbToHsl(+m[1], +m[2], +m[3]);
        var h = hsl[0], s = hsl[1];
        if (s < 0.18) return 'secondary';
        if (h >= 330 || h < 18) return 'danger';
        if (h >= 90 && h < 165) return 'success';
        if (h >= 185 && h < 285) return 'primary';
        return 'secondary';
    }

    function tagButtons(root) {
        qsa('button, a[role="button"], input[type="submit"]', root).forEach(function (btn) {
            if (btn.closest(SKIP_IN)) return;
            if (btn.hasAttribute('data-ptd-btn') || btn.hasAttribute('data-ptd-skip')) return;

            var text = (btn.textContent || '').trim();
            var iconOnly = text.length === 0;
            if (iconOnly && btn.closest('[data-ptd="nav"]')) { btn.setAttribute('data-ptd-skip', ''); return; }

            var variant = classifyButton(btn);
            if (!variant) { btn.setAttribute('data-ptd-skip', ''); return; }
            btn.setAttribute('data-ptd-btn', variant);
        });
    }

    /* =====================================================================
       Navigation
       ===================================================================== */

    function tagNav() {
        var nav = qs('#navigation');
        if (!nav) {
            var brand = qs('#app a[href="/"]');
            nav = brand ? brand.closest('div[class]') : null;
            if (nav && nav.parentElement && nav.parentElement.id !== 'app') nav = nav.parentElement;
        }
        if (!nav) return null;
        mark(nav, 'nav');

        var brandLink = qs('a[href="/"]', nav);
        if (brandLink) brandLink.setAttribute('data-ptd', 'nav-brand');

        /* Aktionsleiste rechts: Container des Account-Links bzw. des letzten Icons */
        var acct = qs('a[href^="/account"], a[href="/auth/logout"]', nav);
        var actions = acct ? acct.parentElement : null;
        if (actions && actions !== nav) actions.setAttribute('data-ptd', 'nav-actions');

        return nav;
    }

    /* =====================================================================
       Sub-Navigation
       ===================================================================== */

    function tagSubNav() {
        var links = qsa('#app a[href^="/server/"], #app a[href^="/account"]').filter(function (a) {
            var h = a.getAttribute('href') || '';
            return /^\/server\/[^/]+\/[a-z]/.test(h) || /^\/account\/[a-z]/.test(h) || h === '/account';
        });
        if (links.length < 2) return null;

        /* Haeufigster gemeinsamer Elternknoten = innere Leiste */
        var counts = new Map();
        links.forEach(function (a) {
            var p = a.parentElement;
            if (!p) return;
            counts.set(p, (counts.get(p) || 0) + 1);
        });
        var inner = null, best = 0;
        counts.forEach(function (n, node) { if (n > best) { best = n; inner = node; } });
        if (!inner || best < 2) return null;

        var outer = inner.parentElement && inner.parentElement.id !== 'app' ? inner.parentElement : inner;
        mark(outer, 'subnav');
        if (outer !== inner) inner.setAttribute('data-ptd-sub', 'inner');

        /* Aktiven Eintrag selbst bestimmen – unabhaengig von der Router-Version */
        var path = location.pathname.replace(/\/$/, '');
        var exact = null, prefix = null;
        qsa('a', inner).forEach(function (a) {
            a.removeAttribute('data-ptd-active');
            var h = (a.getAttribute('href') || '').replace(/\/$/, '');
            if (!h) return;
            if (h === path) exact = a;
            else if (path.indexOf(h + '/') === 0 && (!prefix || h.length > (prefix.getAttribute('href') || '').length)) prefix = a;
        });
        var active = exact || prefix;
        if (active) active.setAttribute('data-ptd-active', '1');

        return outer;
    }

    /* =====================================================================
       Serverliste auf dem Dashboard
       ===================================================================== */

    function tagServerCards() {
        if (PTD.route.page !== 'dashboard') return;
        qsa('#app a[href^="/server/"]').forEach(function (a) {
            var h = a.getAttribute('href') || '';
            if (!/^\/server\/[^/]+\/?$/.test(h)) return;
            if (a.getAttribute('data-ptd') === 'server-card') return;
            mark(a, 'server-card');
            a.setAttribute('data-ptd-sid', h.split('/')[2]);
        });
    }

    /* =====================================================================
       Karten (TitledGreyBox & Co.)
       ===================================================================== */

    function tagCards(root) {
        qsa('[class*="bg-neutral-700"]:not([data-ptd-seen]), [class*="bg-gray-700"]:not([data-ptd-seen])', root).forEach(function (n) {
            if (n.hasAttribute('data-ptd')) return;
            if (n.closest(SKIP_IN)) { n.setAttribute('data-ptd-seen', ''); return; }
            var cls = typeof n.className === 'string' ? n.className : '';
            if (!/\brounded/.test(cls)) { n.setAttribute('data-ptd-seen', ''); return; }
            if (n.offsetHeight < 28) return;   /* evtl. noch nicht gerendert – erneut pruefen */
            mark(n, 'card');
            var head = n.firstElementChild;
            if (head) {
                var hc = typeof head.className === 'string' ? head.className : '';
                if (/bg-neutral-900|bg-gray-900|border-b/.test(hc)) head.setAttribute('data-ptd', 'card-header');
            }
        });
    }

    /* =====================================================================
       Konsole
       ===================================================================== */

    function tagConsole() {
        var term = qs('#terminal') || qs('.xterm');
        if (!term) return null;
        var box = term.id === 'terminal' ? term : (term.parentElement || term);
        mark(box, 'console');
        return box;
    }

    /* =====================================================================
       Power-Buttons
       ===================================================================== */

    var POWER_WORDS = /^(start|restart|stop|kill|starten|neustart|stoppen)$/i;

    function tagPower() {
        if (PTD.route.page !== 'server') return;
        var hits = qsa('#app button').filter(function (b) {
            return POWER_WORDS.test((b.textContent || '').trim());
        });
        if (hits.length < 2) return;
        var parent = hits[0].parentElement;
        if (parent && parent.getAttribute('data-ptd') !== 'power') parent.setAttribute('data-ptd', 'power');
    }

    /* =====================================================================
       Modals
       ===================================================================== */

    function tagModals() {
        var portal = qs('#modal-portal');
        if (!portal) return;
        qsa(':scope > div', portal).forEach(function (backdrop) {
            backdrop.setAttribute('data-ptd', 'modal-backdrop');
            var dialog = null;
            qsa('div', backdrop).some(function (d) {
                if (d.offsetWidth > 240 && hasBg(d)) { dialog = d; return true; }
                return false;
            });
            if (dialog) dialog.setAttribute('data-ptd', 'modal');
        });
    }

    /* =====================================================================
       Login-Karte
       ===================================================================== */

    function tagAuthCard() {
        if (PTD.route.page !== 'auth') return null;
        var form = qs('#app form');
        if (!form) return null;
        var node = form.parentElement, best = form.parentElement, level = 0;
        while (node && level < 4) {
            if (node.offsetWidth > 260 && hasBg(node)) { best = node; break; }
            node = node.parentElement;
            level++;
        }
        if (best) mark(best, 'auth-card');
        return best;
    }

    /* =====================================================================
       Seitenanimation
       ===================================================================== */

    function animatePage() {
        if (!PTD.get('motion')) return;
        var root = PTD.contentRoot();
        if (!root) return;

        var host = root;
        if (root.querySelector('[data-ptd="nav"]')) {
            /* Der Container umfasst auch die Navigation. Dann nur den letzten
               echten Inhaltsblock animieren, damit die Leiste ruhig bleibt. */
            host = null;
            for (var i = root.children.length - 1; i >= 0; i--) {
                var k = root.children[i];
                if (k.id && k.id.indexOf('ptd-') === 0) continue;
                if (k.hasAttribute('data-ptd')) continue;
                host = k;
                break;
            }
        }
        if (!host) return;
        host.setAttribute('data-ptd-anim', 'page');
        setTimeout(function () { host.removeAttribute('data-ptd-anim'); }, 500);
    }

    /* =====================================================================
       Kompletter Durchlauf
       ===================================================================== */

    var scanning = false;

    function scan() {
        scanning = true;
        try {
            tagNav();
            tagSubNav();
            tagServerCards();
            tagCards(document);
            tagButtons(document);
            tagPower();
            tagModals();
            tagAuthCard();
            tagConsole();
            PTD._lastScanAt = Date.now();
            PTD.bus.emit('scan');
        } catch (e) {
            console.warn('[Nebula] scan', e);
        } finally {
            scanning = false;
        }
    }

    var pending = false;
    function schedule() {
        if (pending || scanning) return;
        pending = true;
        requestAnimationFrame(function () {
            pending = false;
            scan();
        });
    }

    PTD.ready(function () {
        scan();
        var host = qs('#app') || document.body;
        new MutationObserver(function (records) {
            for (var i = 0; i < records.length; i++) {
                if (records[i].type === 'childList' && (records[i].addedNodes.length || records[i].removedNodes.length)) {
                    schedule();
                    return;
                }
            }
        }).observe(host, { childList: true, subtree: true });

        var portal = qs('#modal-portal');
        if (portal) {
            new MutationObserver(schedule).observe(portal, { childList: true, subtree: true });
        }
    });

    PTD.bus.on('route', function () {
        animatePage();
        schedule();
        setTimeout(schedule, 160);
        setTimeout(schedule, 500);
    });

    PTD.bus.on('settings', schedule);

    PTD.tagger = { scan: scan, schedule: schedule };
})();
