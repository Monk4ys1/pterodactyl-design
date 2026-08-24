/* =========================================================================
   Nebula · 10-core.js
   DOM-Hilfen, Icon-Set, Toasts, Routen-Erkennung, API-Zugriff, Formatierung.
   ========================================================================= */

(function () {
    'use strict';
    var PTD = window.PTD;
    if (!PTD) return;

    /* =====================================================================
       DOM-Hilfen
       ===================================================================== */

    function qs(sel, root) { return (root || document).querySelector(sel); }
    function qsa(sel, root) { return Array.prototype.slice.call((root || document).querySelectorAll(sel)); }

    function el(tag, attrs, children) {
        var node = document.createElement(tag);
        if (attrs) {
            Object.keys(attrs).forEach(function (k) {
                var v = attrs[k];
                if (v === null || v === undefined || v === false) return;
                if (k === 'class') node.className = v;
                else if (k === 'html') node.innerHTML = v;
                else if (k === 'text') node.textContent = v;
                else if (k === 'style' && typeof v === 'object') {
                    /* Object.assign kann keine Custom Properties setzen –
                       dafuer braucht es setProperty. */
                    Object.keys(v).forEach(function (prop) {
                        if (prop.slice(0, 2) === '--') node.style.setProperty(prop, v[prop]);
                        else node.style[prop] = v[prop];
                    });
                }
                else if (k.slice(0, 2) === 'on' && typeof v === 'function') node.addEventListener(k.slice(2), v);
                else node.setAttribute(k, v === true ? '' : v);
            });
        }
        (children || []).forEach(function (c) {
            if (c == null) return;
            node.appendChild(typeof c === 'string' ? document.createTextNode(c) : c);
        });
        return node;
    }

    function on(target, type, handler, opts) {
        target.addEventListener(type, handler, opts || false);
        return function () { target.removeEventListener(type, handler, opts || false); };
    }

    function ready(fn) {
        if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', fn, { once: true });
        else fn();
    }

    function debounce(fn, ms) {
        var t;
        return function () {
            var a = arguments, self = this;
            clearTimeout(t);
            t = setTimeout(function () { fn.apply(self, a); }, ms || 120);
        };
    }

    function escapeHtml(s) {
        return String(s).replace(/[&<>"']/g, function (c) {
            return { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c];
        });
    }

    /* =====================================================================
       Icons (16px, currentColor)
       ===================================================================== */

    var ICON = {
        search:   '<path d="M11 19a8 8 0 1 0 0-16 8 8 0 0 0 0 16Zm10 2-4.35-4.35"/>',
        settings: '<circle cx="12" cy="12" r="3"/><path d="M19.4 15a1.65 1.65 0 0 0 .33 1.82l.06.06a2 2 0 1 1-2.83 2.83l-.06-.06a1.65 1.65 0 0 0-1.82-.33 1.65 1.65 0 0 0-1 1.51V21a2 2 0 1 1-4 0v-.09A1.65 1.65 0 0 0 9 19.4a1.65 1.65 0 0 0-1.82.33l-.06.06a2 2 0 1 1-2.83-2.83l.06-.06A1.65 1.65 0 0 0 4.6 15a1.65 1.65 0 0 0-1.51-1H3a2 2 0 1 1 0-4h.09A1.65 1.65 0 0 0 4.6 9a1.65 1.65 0 0 0-.33-1.82l-.06-.06a2 2 0 1 1 2.83-2.83l.06.06A1.65 1.65 0 0 0 9 4.6a1.65 1.65 0 0 0 1-1.51V3a2 2 0 1 1 4 0v.09a1.65 1.65 0 0 0 1 1.51 1.65 1.65 0 0 0 1.82-.33l.06-.06a2 2 0 1 1 2.83 2.83l-.06.06A1.65 1.65 0 0 0 19.4 9v0a1.65 1.65 0 0 0 1.51 1H21a2 2 0 1 1 0 4h-.09a1.65 1.65 0 0 0-1.51 1Z"/>',
        server:   '<rect x="2" y="3" width="20" height="7" rx="2"/><rect x="2" y="14" width="20" height="7" rx="2"/><line x1="6" y1="6.5" x2="6.01" y2="6.5"/><line x1="6" y1="17.5" x2="6.01" y2="17.5"/>',
        terminal: '<polyline points="4 17 10 11 4 5"/><line x1="12" y1="19" x2="20" y2="19"/>',
        folder:   '<path d="M22 19a2 2 0 0 1-2 2H4a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h5l2 3h9a2 2 0 0 1 2 2Z"/>',
        database: '<ellipse cx="12" cy="5" rx="9" ry="3"/><path d="M21 12c0 1.66-4 3-9 3s-9-1.34-9-3"/><path d="M3 5v14c0 1.66 4 3 9 3s9-1.34 9-3V5"/>',
        clock:    '<circle cx="12" cy="12" r="10"/><polyline points="12 6 12 12 16 14"/>',
        users:    '<path d="M17 21v-2a4 4 0 0 0-4-4H5a4 4 0 0 0-4 4v2"/><circle cx="9" cy="7" r="4"/><path d="M23 21v-2a4 4 0 0 0-3-3.87"/>',
        archive:  '<rect x="2" y="4" width="20" height="5" rx="1"/><path d="M4 9v10a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V9"/><line x1="10" y1="13" x2="14" y2="13"/>',
        network:  '<rect x="2" y="14" width="20" height="8" rx="2"/><path d="M6 14V8a6 6 0 0 1 12 0v6"/>',
        sliders:  '<line x1="4" y1="21" x2="4" y2="14"/><line x1="4" y1="10" x2="4" y2="3"/><line x1="12" y1="21" x2="12" y2="12"/><line x1="12" y1="8" x2="12" y2="3"/><line x1="20" y1="21" x2="20" y2="16"/><line x1="20" y1="12" x2="20" y2="3"/><line x1="1" y1="14" x2="7" y2="14"/><line x1="9" y1="8" x2="15" y2="8"/><line x1="17" y1="16" x2="23" y2="16"/>',
        home:     '<path d="M3 9.5 12 3l9 6.5V20a1 1 0 0 1-1 1h-5v-7H9v7H4a1 1 0 0 1-1-1Z"/>',
        user:     '<path d="M20 21v-2a4 4 0 0 0-4-4H8a4 4 0 0 0-4 4v2"/><circle cx="12" cy="7" r="4"/>',
        key:      '<path d="m21 2-2 2m-7.6 7.6a5.5 5.5 0 1 1-7.8 7.8 5.5 5.5 0 0 1 7.8-7.8Zm0 0L15.5 7.5m0 0 3 3L22 7l-3-3"/>',
        shield:   '<path d="M12 22s8-4 8-10V5l-8-3-8 3v7c0 6 8 10 8 10Z"/>',
        activity: '<polyline points="22 12 18 12 15 21 9 3 6 12 2 12"/>',
        play:     '<polygon points="6 3 20 12 6 21 6 3"/>',
        stop:     '<rect x="5" y="5" width="14" height="14" rx="2"/>',
        restart:  '<polyline points="23 4 23 10 17 10"/><path d="M20.49 15a9 9 0 1 1-2.12-9.36L23 10"/>',
        power:    '<path d="M18.36 6.64a9 9 0 1 1-12.73 0"/><line x1="12" y1="2" x2="12" y2="12"/>',
        copy:     '<rect x="9" y="9" width="13" height="13" rx="2"/><path d="M5 15H4a2 2 0 0 1-2-2V4a2 2 0 0 1 2-2h9a2 2 0 0 1 2 2v1"/>',
        download: '<path d="M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4"/><polyline points="7 10 12 15 17 10"/><line x1="12" y1="15" x2="12" y2="3"/>',
        trash:    '<polyline points="3 6 5 6 21 6"/><path d="M19 6v14a2 2 0 0 1-2 2H7a2 2 0 0 1-2-2V6m3 0V4a2 2 0 0 1 2-2h4a2 2 0 0 1 2 2v2"/>',
        expand:   '<polyline points="15 3 21 3 21 9"/><polyline points="9 21 3 21 3 15"/><line x1="21" y1="3" x2="14" y2="10"/><line x1="3" y1="21" x2="10" y2="14"/>',
        collapse: '<polyline points="4 14 10 14 10 20"/><polyline points="20 10 14 10 14 4"/><line x1="14" y1="10" x2="21" y2="3"/><line x1="3" y1="21" x2="10" y2="14"/>',
        chevron:  '<polyline points="6 9 12 15 18 9"/>',
        close:    '<line x1="18" y1="6" x2="6" y2="18"/><line x1="6" y1="6" x2="18" y2="18"/>',
        check:    '<polyline points="20 6 9 17 4 12"/>',
        alert:    '<path d="M10.29 3.86 1.82 18a2 2 0 0 0 1.71 3h16.94a2 2 0 0 0 1.71-3L13.71 3.86a2 2 0 0 0-3.42 0Z"/><line x1="12" y1="9" x2="12" y2="13"/><line x1="12" y1="17" x2="12.01" y2="17"/>',
        info:     '<circle cx="12" cy="12" r="10"/><line x1="12" y1="16" x2="12" y2="12"/><line x1="12" y1="8" x2="12.01" y2="8"/>',
        moon:     '<path d="M21 12.79A9 9 0 1 1 11.21 3 7 7 0 0 0 21 12.79Z"/>',
        sun:      '<circle cx="12" cy="12" r="4"/><path d="M12 2v2m0 16v2M4.9 4.9l1.4 1.4m11.4 11.4 1.4 1.4M2 12h2m16 0h2M4.9 19.1l1.4-1.4M17.7 6.3l1.4-1.4"/>',
        arrowUp:  '<line x1="12" y1="19" x2="12" y2="5"/><polyline points="5 12 12 5 19 12"/>',
        keyboard: '<rect x="2" y="5" width="20" height="14" rx="2"/><path d="M6 9h.01M10 9h.01M14 9h.01M18 9h.01M6 13h.01M18 13h.01M10 13h4"/>',
        cpu:      '<rect x="6" y="6" width="12" height="12" rx="2"/><path d="M9 2v2m6-2v2M9 20v2m6-2v2M2 9h2m-2 6h2m16-6h2m-2 6h2"/>',
        chip:     '<rect x="4" y="4" width="16" height="16" rx="2"/><rect x="9" y="9" width="6" height="6"/>',
        disk:     '<circle cx="12" cy="12" r="10"/><circle cx="12" cy="12" r="3"/>',
        globe:    '<circle cx="12" cy="12" r="10"/><path d="M2 12h20M12 2a15 15 0 0 1 0 20 15 15 0 0 1 0-20Z"/>',
        filter:   '<polygon points="22 3 2 3 10 12.46 10 19 14 21 14 12.46 22 3"/>',
        bell:     '<path d="M18 8a6 6 0 1 0-12 0c0 7-3 9-3 9h18s-3-2-3-9"/><path d="M13.73 21a2 2 0 0 1-3.46 0"/>',
        wand:     '<path d="m15 4 5 5M3 21l9.5-9.5M14.5 3.5 20.5 9.5M18 2l1 3 3 1-3 1-1 3-1-3-3-1 3-1Z"/>',
        pin:      '<path d="M12 17v5"/><path d="M9 10.8V4h6v6.8l2.3 3.4a1 1 0 0 1-.83 1.56H7.53a1 1 0 0 1-.83-1.56Z"/>',
        menu:     '<line x1="3" y1="6" x2="21" y2="6"/><line x1="3" y1="12" x2="21" y2="12"/><line x1="3" y1="18" x2="21" y2="18"/>',
        panelLeft:'<rect x="3" y="3" width="18" height="18" rx="2"/><line x1="9" y1="3" x2="9" y2="21"/>',
        chevL:    '<polyline points="15 18 9 12 15 6"/>',
        chevR:    '<polyline points="9 18 15 12 9 6"/>',
        plus:     '<line x1="12" y1="5" x2="12" y2="19"/><line x1="5" y1="12" x2="19" y2="12"/>',
        zap:      '<polygon points="13 2 3 14 12 14 11 22 21 10 12 10 13 2"/>',
        gauge:    '<path d="M12 15a3 3 0 1 0 0-6 3 3 0 0 0 0 6Z"/><path d="M13.4 10.6 19 5"/><path d="M20.5 16a9 9 0 1 0-17 0"/>',
        eye:      '<path d="M2 12s3.6-7 10-7 10 7 10 7-3.6 7-10 7-10-7-10-7Z"/><circle cx="12" cy="12" r="3"/>',
        layers:   '<polygon points="12 2 2 7 12 12 22 7 12 2"/><polyline points="2 17 12 22 22 17"/><polyline points="2 12 12 17 22 12"/>',
        grid:     '<rect x="3" y="3" width="7" height="7" rx="1"/><rect x="14" y="3" width="7" height="7" rx="1"/><rect x="3" y="14" width="7" height="7" rx="1"/><rect x="14" y="14" width="7" height="7" rx="1"/>',
        pip:      '<rect x="2" y="4" width="20" height="16" rx="2"/><rect x="12" y="12" width="8" height="6" rx="1"/>',
        sparkles: '<path d="M12 2.5c.35 3.4 1.6 4.65 5 5-3.4.35-4.65 1.6-5 5-.35-3.4-1.6-4.65-5-5 3.4-.35 4.65-1.6 5-5Z"/>' +
                  '<path d="M18.5 14c.2 1.9.9 2.6 2.8 2.8-1.9.2-2.6.9-2.8 2.8-.2-1.9-.9-2.6-2.8-2.8 1.9-.2 2.6-.9 2.8-2.8Z"/>',
        logOut:   '<path d="M9 21H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h4"/><polyline points="16 17 21 12 16 7"/><line x1="21" y1="12" x2="9" y2="12"/>',
        table:    '<rect x="3" y="3" width="18" height="18" rx="2"/><line x1="3" y1="9" x2="21" y2="9"/><line x1="9" y1="9" x2="9" y2="21"/>',
        mark:     '<path d="M3 7.5 12 2l9 5.5v9L12 22l-9-5.5Z"/><path d="M12 22V12"/><path d="m3 7.5 9 4.5 9-4.5"/>'
    };

    function icon(name, size) {
        var body = ICON[name] || ICON.info;
        return '<svg xmlns="http://www.w3.org/2000/svg" width="' + (size || 16) + '" height="' + (size || 16) +
            '" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.9" ' +
            'stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">' + body + '</svg>';
    }

    /* =====================================================================
       Formatierung
       ===================================================================== */

    function bytes(n, digits) {
        n = Number(n) || 0;
        if (n < 1024) return n.toFixed(0) + ' B';
        var u = ['KiB', 'MiB', 'GiB', 'TiB', 'PiB'], i = -1;
        do { n /= 1024; i++; } while (n >= 1024 && i < u.length - 1);
        return n.toFixed(digits === undefined ? (n < 10 ? 2 : 1) : digits) + ' ' + u[i];
    }

    function pct(n) { return (Math.round((Number(n) || 0) * 10) / 10).toFixed(1) + ' %'; }

    function duration(ms) {
        var s = Math.floor((Number(ms) || 0) / 1000);
        var d = Math.floor(s / 86400); s -= d * 86400;
        var h = Math.floor(s / 3600);  s -= h * 3600;
        var m = Math.floor(s / 60);    s -= m * 60;
        var out = [];
        if (d) out.push(d + 'd');
        if (d || h) out.push(h + 'h');
        if (d || h || m) out.push(m + 'm');
        out.push(s + 's');
        return out.slice(0, 3).join(' ');
    }

    /* Zwei Initialen aus einem Servernamen – dient als Bildmarke. */
    function initials(name) {
        var parts = String(name || '?').trim().split(/[\s_\-.]+/).filter(Boolean);
        if (!parts.length) return '?';
        if (parts.length === 1) return parts[0].slice(0, 2).toUpperCase();
        return (parts[0][0] + parts[1][0]).toUpperCase();
    }

    /* Stabile Farbe aus einer Zeichenkette – gleicher Server, gleiche Farbe. */
    var TAG_HUES = [265, 190, 42, 330, 155, 210, 15, 290];
    function autoColor(key) {
        var h = 0, i;
        for (i = 0; i < String(key).length; i++) h = (h * 31 + String(key).charCodeAt(i)) >>> 0;
        return 'hsl(' + TAG_HUES[h % TAG_HUES.length] + ' 62% 62%)';
    }

    function toCsv(rows) {
        return rows.map(function (r) {
            return r.map(function (c) {
                var v = String(c === null || c === undefined ? '' : c);
                return /[",\n;]/.test(v) ? '"' + v.replace(/"/g, '""') + '"' : v;
            }).join(';');
        }).join('\n');
    }

    function download(name, text, mime) {
        try {
            var blob = new Blob([text], { type: (mime || 'text/plain') + ';charset=utf-8' });
            var url = URL.createObjectURL(blob);
            var a = el('a', { href: url, download: name });
            document.body.appendChild(a);
            a.click();
            document.body.removeChild(a);
            setTimeout(function () { URL.revokeObjectURL(url); }, 2000);
            return true;
        } catch (e) { return false; }
    }

    function clockTime(t) {
        var d = new Date(t);
        function p(n) { return (n < 10 ? '0' : '') + n; }
        return p(d.getHours()) + ':' + p(d.getMinutes()) + ':' + p(d.getSeconds());
    }

    /* =====================================================================
       Routen-Erkennung
       ===================================================================== */

    function pageOf(path) {
        if (/^\/auth(\/|$)/.test(path)) return 'auth';
        if (/^\/admin(\/|$)/.test(path)) return 'admin';
        if (/^\/account(\/|$)/.test(path)) return 'account';
        if (/^\/server\//.test(path)) return 'server';
        return 'dashboard';
    }

    function serverIdOf(path) {
        var m = path.match(/^\/server\/([^/?#]+)/);
        return m ? m[1] : null;
    }

    /* Container, in dem der Seiteninhalt gerendert wird – bewusst ueber
       Ankerelemente statt ueber feste Kindpositionen bestimmt. */
    function isOurs(node) {
        return !!node && ((node.id && node.id.indexOf('ptd-') === 0) || node.hasAttribute('data-ptd-own'));
    }

    function nextForeign(node) {
        var n = node && node.nextElementSibling;
        while (n && isOurs(n)) n = n.nextElementSibling;
        return n;
    }

    function contentRoot() {
        var app = qs('#app');
        if (!app) return document.body;
        var sub = qs('[data-ptd="subnav"]');
        if (sub && sub.parentElement && sub.parentElement !== app) return sub.parentElement;
        var nav = qs('[data-ptd="nav"]') || qs('#navigation');
        var after = nextForeign(nav);
        if (after) return after;
        if (nav && nav.parentElement && nav.parentElement !== app) return nav.parentElement;
        var last = app.lastElementChild;
        while (last && isOurs(last)) last = last.previousElementSibling;
        return last || app;
    }

    var route = {
        path: location.pathname,
        page: pageOf(location.pathname),
        server: serverIdOf(location.pathname),
        sub: null
    };

    function refreshRoute() {
        var p = location.pathname;
        var changed = p !== route.path;
        var prev = { path: route.path, page: route.page, server: route.server };
        route.path = p;
        route.page = pageOf(p);
        route.server = serverIdOf(p);
        route.sub = route.server ? (p.split('/')[3] || 'console') : (p.split('/')[2] || null);
        document.documentElement.setAttribute('data-ptd-page', route.page);
        if (changed) PTD.bus.emit('route', { from: prev, to: route });
        return changed;
    }

    (function patchHistory() {
        ['pushState', 'replaceState'].forEach(function (m) {
            var orig = history[m];
            if (typeof orig !== 'function') return;
            history[m] = function () {
                var r = orig.apply(this, arguments);
                setTimeout(refreshRoute, 0);
                return r;
            };
        });
        window.addEventListener('popstate', function () { setTimeout(refreshRoute, 0); });
    })();

    /* =====================================================================
       Ladebalken
       ===================================================================== */

    var progress = (function () {
        var bar = null, timer = null;
        function node() {
            if (!bar) {
                bar = el('div', { id: 'ptd-progress' });
                (document.body || document.documentElement).appendChild(bar);
            }
            return bar;
        }
        return {
            start: function () {
                var b = node();
                clearTimeout(timer);
                b.style.opacity = '1';
                b.style.width = '18%';
                setTimeout(function () { b.style.width = '68%'; }, 140);
            },
            done: function () {
                var b = node();
                b.style.width = '100%';
                clearTimeout(timer);
                timer = setTimeout(function () {
                    b.style.opacity = '0';
                    setTimeout(function () { b.style.width = '0'; }, 260);
                }, 180);
            }
        };
    })();

    PTD.bus.on('route', function () {
        progress.start();
        setTimeout(function () { progress.done(); }, 420);
    });

    /* =====================================================================
       Toasts
       ===================================================================== */

    function toastHost() {
        var host = qs('#ptd-toasts');
        if (!host) {
            host = el('div', { id: 'ptd-toasts' });
            document.body.appendChild(host);
        }
        return host;
    }

    function toast(opts) {
        opts = opts || {};
        var type = opts.type || 'info';
        var ic = { ok: 'check', warn: 'alert', danger: 'alert', info: 'info' }[type] || 'info';
        var node = el('div', { class: 'ptd-toast ptd-toast--' + type, role: 'status' }, [
            el('span', { class: 'ptd-t-ico', html: icon(ic) }),
            el('div', { class: 'ptd-t-body' }, [
                el('div', { class: 'ptd-t-title', text: opts.title || 'Nebula' }),
                opts.msg ? el('div', { class: 'ptd-t-msg', text: opts.msg }) : null
            ]),
            el('button', { class: 'ptd-t-x', 'aria-label': 'Schliessen', html: '&times;', onclick: close })
        ]);
        toastHost().appendChild(node);

        var to = setTimeout(close, opts.timeout === undefined ? 5200 : opts.timeout);
        function close() {
            clearTimeout(to);
            if (!node.parentNode) return;
            node.classList.add('is-out');
            setTimeout(function () { if (node.parentNode) node.parentNode.removeChild(node); }, 240);
        }
        return close;
    }

    /* =====================================================================
       API-Zugriff (Session-Cookie der Panel-Oberflaeche)
       ===================================================================== */

    function cookie(name) {
        var m = document.cookie.match(new RegExp('(^|;\\s*)' + name + '=([^;]*)'));
        return m ? decodeURIComponent(m[2]) : null;
    }

    function api(path, options) {
        options = options || {};
        var headers = {
            'Accept': 'application/json',
            'X-Requested-With': 'XMLHttpRequest'
        };
        if (options.body) headers['Content-Type'] = 'application/json';
        var xsrf = cookie('XSRF-TOKEN');
        if (xsrf) headers['X-XSRF-TOKEN'] = xsrf;

        return fetch(path, {
            method: options.method || 'GET',
            credentials: 'same-origin',
            headers: Object.assign(headers, options.headers || {}),
            body: options.body ? JSON.stringify(options.body) : undefined
        }).then(function (res) {
            if (res.status === 204) return null;
            if (!res.ok) {
                var err = new Error('HTTP ' + res.status);
                err.status = res.status;
                throw err;
            }
            var ct = res.headers.get('content-type') || '';
            return ct.indexOf('json') > -1 ? res.json() : res.text();
        });
    }

    /* =====================================================================
       Webfonts (optional, mit vollstaendigem System-Fallback)
       ===================================================================== */

    function loadFonts() {
        if (!PTD.get('webfonts')) {
            qsa('link[data-ptd-fonts]').forEach(function (n) { n.parentNode.removeChild(n); });
            return;
        }
        if (qs('link[data-ptd-fonts]')) return;
        var pre1 = el('link', { rel: 'preconnect', href: 'https://fonts.googleapis.com', 'data-ptd-fonts': '1' });
        var pre2 = el('link', { rel: 'preconnect', href: 'https://fonts.gstatic.com', crossorigin: '', 'data-ptd-fonts': '1' });
        var css = el('link', {
            rel: 'stylesheet',
            'data-ptd-fonts': '1',
            href: 'https://fonts.googleapis.com/css2?family=Inter:wght@400;500;600;700&family=JetBrains+Mono:wght@400;500;700&display=swap'
        });
        document.head.appendChild(pre1);
        document.head.appendChild(pre2);
        document.head.appendChild(css);
    }

    /* =====================================================================
       Persistenter Cache fuer Serverlisten (Command-Palette)
       ===================================================================== */

    var cache = {
        get: function (k, maxAgeMs) {
            try {
                var raw = sessionStorage.getItem('ptd:cache:' + k);
                if (!raw) return null;
                var o = JSON.parse(raw);
                if (maxAgeMs && Date.now() - o.t > maxAgeMs) return null;
                return o.v;
            } catch (e) { return null; }
        },
        set: function (k, v) {
            try { sessionStorage.setItem('ptd:cache:' + k, JSON.stringify({ t: Date.now(), v: v })); } catch (e) { /* voll */ }
        }
    };

    /* =====================================================================
       Export
       ===================================================================== */

    Object.assign(PTD, {
        qs: qs, qsa: qsa, el: el, on: on, ready: ready, debounce: debounce, escapeHtml: escapeHtml,
        icon: icon, ICON: ICON,
        fmt: { bytes: bytes, pct: pct, duration: duration, clockTime: clockTime, initials: initials },
        autoColor: autoColor, toCsv: toCsv, download: download,
        route: route, refreshRoute: refreshRoute, contentRoot: contentRoot, isOurs: isOurs,
        progress: progress, toast: toast, api: api, cookie: cookie, cache: cache,
        loadFonts: loadFonts
    });

    PTD.bus.on('settings', loadFonts);

    refreshRoute();
    ready(function () {
        loadFonts();
        PTD.bus.emit('ready');
    });
})();
