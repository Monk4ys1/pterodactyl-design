/* =========================================================================
   Nebula · 00-boot.js
   Laeuft als erstes Skript im <head>, noch vor dem React-Bundle.
   Aufgaben:
     1. Einstellungen laden und sofort auf <html> anwenden (kein Flackern)
     2. window.WebSocket kapseln, um den Wings-Datenstrom mitzulesen
     3. Minimalen Event-Bus und Datenspeicher bereitstellen
   ========================================================================= */

(function () {
    'use strict';

    if (window.PTD) { return; }

    var VERSION = '__PTD_VERSION__';
    var KEY = 'ptd:settings';

    /* ---------------------------------------------------------------------
       Event-Bus
       ------------------------------------------------------------------- */
    function Bus() { this._m = Object.create(null); }
    Bus.prototype.on = function (name, fn) {
        (this._m[name] || (this._m[name] = [])).push(fn);
        return function () { this.off(name, fn); }.bind(this);
    };
    Bus.prototype.off = function (name, fn) {
        var l = this._m[name];
        if (!l) return;
        var i = l.indexOf(fn);
        if (i > -1) l.splice(i, 1);
    };
    Bus.prototype.emit = function (name, data) {
        var l = this._m[name];
        if (!l) return;
        var copy = l.slice();
        for (var i = 0; i < copy.length; i++) {
            try { copy[i](data); } catch (e) { console.warn('[Nebula] listener', name, e); }
        }
    };

    /* ---------------------------------------------------------------------
       Standardeinstellungen
       ------------------------------------------------------------------- */
    var DEFAULTS = {
        v: 1,
        preset: 'nebula',
        mode: 'dark',              // dark | light | auto
        accent: '',                // leer = Preset-Farbe
        radius: 14,
        blur: 18,
        compact: false,
        wide: false,
        glass: true,
        motion: true,
        bg: 'aurora',              // aurora | plain | image
        bgImage: '',
        webfonts: true,
        fab: true,
        greeting: true,
        footer: true,
        modules: {
            palette: true,
            console: true,
            charts: true,
            notify: true,
            shortcuts: true,
            enhance: true
        },
        notifyDesktop: false,
        notifySound: false,
        consoleTimestamps: true,
        consoleFontSize: 13,
        historyPoints: 90
    };

    function deepMerge(base, over) {
        var out = {}, k;
        for (k in base) {
            if (!Object.prototype.hasOwnProperty.call(base, k)) continue;
            if (base[k] && typeof base[k] === 'object' && !Array.isArray(base[k])) {
                out[k] = deepMerge(base[k], (over && over[k]) || {});
            } else {
                out[k] = (over && Object.prototype.hasOwnProperty.call(over, k)) ? over[k] : base[k];
            }
        }
        return out;
    }

    function readSettings() {
        try {
            var raw = window.localStorage.getItem(KEY);
            if (!raw) return deepMerge(DEFAULTS, {});
            return deepMerge(DEFAULTS, JSON.parse(raw));
        } catch (e) {
            return deepMerge(DEFAULTS, {});
        }
    }

    function writeSettings(s) {
        try { window.localStorage.setItem(KEY, JSON.stringify(s)); } catch (e) { /* Private Mode */ }
    }

    /* ---------------------------------------------------------------------
       Einstellungen auf das <html>-Element anwenden
       ------------------------------------------------------------------- */
    function resolveMode(mode) {
        if (mode !== 'auto') return mode;
        try {
            return window.matchMedia('(prefers-color-scheme: light)').matches ? 'light' : 'dark';
        } catch (e) { return 'dark'; }
    }

    function apply(s) {
        var h = document.documentElement;
        h.setAttribute('data-ptd', VERSION);
        h.setAttribute('data-ptd-preset', s.preset);
        h.setAttribute('data-ptd-mode', resolveMode(s.mode));
        h.setAttribute('data-ptd-compact', s.compact ? '1' : '0');
        h.setAttribute('data-ptd-wide', s.wide ? '1' : '0');
        h.setAttribute('data-ptd-glass', s.glass ? '1' : '0');
        h.setAttribute('data-ptd-motion', s.motion ? '1' : '0');
        h.setAttribute('data-ptd-bg', s.bg);
        h.setAttribute('data-ptd-fab', s.fab ? '1' : '0');

        var st = h.style;
        st.setProperty('--ptd-r', s.radius + 'px');
        st.setProperty('--ptd-blur', s.blur + 'px');
        if (s.accent) {
            st.setProperty('--ptd-accent', s.accent);
        } else {
            st.removeProperty('--ptd-accent');
        }
        if (s.bg === 'image' && s.bgImage) {
            st.setProperty('--ptd-bg-image', 'url("' + String(s.bgImage).replace(/["\\]/g, '') + '")');
        } else {
            st.removeProperty('--ptd-bg-image');
        }
    }

    /* ---------------------------------------------------------------------
       Datenspeicher: Konsolenzeilen und Statistikverlauf je Server
       ------------------------------------------------------------------- */
    var store = {
        lines: [],            // { t: epochMs, text: string, lvl: string }
        maxLines: 2500,
        stats: [],            // { t, cpu, mem, memLimit, disk, rx, tx }
        maxStats: 600,
        state: 'offline',
        lastStats: null,
        serverId: null,
        reset: function () {
            this.lines = [];
            this.stats = [];
            this.state = 'offline';
            this.lastStats = null;
        }
    };

    function levelOf(text) {
        var t = text.toLowerCase();
        if (/\b(error|exception|fatal|severe|failed|traceback)\b/.test(t)) return 'error';
        if (/\b(warn|warning|deprecated)\b/.test(t)) return 'warn';
        if (/\b(debug|trace|verbose)\b/.test(t)) return 'debug';
        if (/\b(info|done|ready|started|joined)\b/.test(t)) return 'info';
        return '';
    }

    /* eslint-disable no-control-regex */
    var ANSI = /[\u001b\u009b][[()#;?]*(?:[0-9]{1,4}(?:;[0-9]{0,4})*)?[0-9A-PRZcf-nqry=><]/g;
    /* eslint-enable no-control-regex */

    function stripAnsi(s) { return String(s).replace(ANSI, ''); }

    /* ---------------------------------------------------------------------
       WebSocket kapseln
       ------------------------------------------------------------------- */
    var bus = new Bus();
    var WS_RE = /\/api\/servers\/[0-9a-fA-F-]{8,}\/ws/;

    function hookSocket(ws, url) {
        ws.addEventListener('message', function (ev) {
            var payload;
            try { payload = JSON.parse(ev.data); } catch (e) { return; }
            if (!payload || !payload.event) return;

            var args = payload.args || [];
            var ev0 = args.length ? args[0] : null;

            switch (payload.event) {
                case 'console output':
                case 'install output':
                case 'daemon message': {
                    var raw = stripAnsi(ev0 == null ? '' : String(ev0));
                    var parts = raw.split(/\r?\n/);
                    for (var i = 0; i < parts.length; i++) {
                        if (parts[i] === '' && parts.length > 1) continue;
                        var line = { t: Date.now(), text: parts[i], lvl: levelOf(parts[i]) };
                        store.lines.push(line);
                        if (store.lines.length > store.maxLines) store.lines.shift();
                        bus.emit('console:line', line);
                    }
                    break;
                }
                case 'stats': {
                    var raw2 = ev0;
                    var s;
                    try { s = typeof raw2 === 'string' ? JSON.parse(raw2) : raw2; } catch (e) { return; }
                    if (!s) return;
                    var net = s.network || {};
                    var point = {
                        t: Date.now(),
                        cpu: Number(s.cpu_absolute || 0),
                        mem: Number(s.memory_bytes || 0),
                        memLimit: Number(s.memory_limit_bytes || 0),
                        disk: Number(s.disk_bytes || 0),
                        rx: Number(net.rx_bytes || 0),
                        tx: Number(net.tx_bytes || 0),
                        uptime: Number(s.uptime || 0),
                        state: s.state || store.state
                    };
                    store.lastStats = point;
                    store.stats.push(point);
                    if (store.stats.length > store.maxStats) store.stats.shift();
                    bus.emit('stats', point);
                    if (point.state && point.state !== store.state) {
                        var prev = store.state;
                        store.state = point.state;
                        bus.emit('state', { from: prev, to: point.state });
                    }
                    break;
                }
                case 'status': {
                    var to = String(ev0 || 'offline');
                    if (to !== store.state) {
                        var from = store.state;
                        store.state = to;
                        bus.emit('state', { from: from, to: to });
                    }
                    break;
                }
                case 'daemon error':
                case 'jwt error':
                    bus.emit('daemon:error', String(ev0 || ''));
                    break;
                case 'backup completed':
                    bus.emit('backup:done', ev0);
                    break;
                case 'transfer status':
                    bus.emit('transfer', String(ev0 || ''));
                    break;
                default:
                    break;
            }
        });

        ws.addEventListener('close', function () { bus.emit('socket:close', { url: url }); });
        bus.emit('socket:open', { url: url });
    }

    var Native = window.WebSocket;
    if (typeof Native === 'function') {
        var Wrapped = function (url, protocols) {
            var sock = (arguments.length > 1)
                ? new Native(url, protocols)
                : new Native(url);
            try {
                if (WS_RE.test(String(url))) {
                    store.reset();
                    hookSocket(sock, String(url));
                }
            } catch (e) { /* Der Panel-Betrieb darf niemals blockiert werden */ }
            return sock;
        };
        Wrapped.prototype = Native.prototype;
        ['CONNECTING', 'OPEN', 'CLOSING', 'CLOSED'].forEach(function (k) {
            try { Wrapped[k] = Native[k]; } catch (e) { /* schreibgeschuetzt */ }
        });
        try { window.WebSocket = Wrapped; } catch (e) { /* nicht ueberschreibbar */ }
    }

    /* ---------------------------------------------------------------------
       Panel-eigene API-Antworten mitlesen
       Das Dashboard fragt fuer jede Serverkachel ohnehin den Ressourcen-
       Endpunkt ab. Wir hoeren nur mit, statt zusaetzliche Anfragen zu
       erzeugen. Es wird nichts veraendert oder blockiert.
       ------------------------------------------------------------------- */
    var RES_RE = /\/api\/client\/servers\/([^/?#]+)\/resources/i;

    function readBody(xhr) {
        try {
            if (xhr.responseType === 'json') return xhr.response;
            if (xhr.responseType === '' || xhr.responseType === 'text') return JSON.parse(xhr.responseText);
        } catch (e) { /* keine JSON-Antwort */ }
        return null;
    }

    function emitResources(url, body) {
        if (!body) return;
        var m = String(url).match(RES_RE);
        if (!m) return;
        var attrs = body.attributes || body;
        if (!attrs) return;
        bus.emit('resources', {
            id: m[1],
            state: attrs.current_state || attrs.state || null,
            suspended: !!attrs.is_suspended,
            resources: attrs.resources || null
        });
    }

    try {
        var xopen = XMLHttpRequest.prototype.open;
        var xsend = XMLHttpRequest.prototype.send;
        XMLHttpRequest.prototype.open = function (method, url) {
            try { this.__ptdUrl = String(url); } catch (e) { /* egal */ }
            return xopen.apply(this, arguments);
        };
        XMLHttpRequest.prototype.send = function () {
            var self = this;
            try {
                self.addEventListener('load', function () {
                    if (!self.__ptdUrl || !RES_RE.test(self.__ptdUrl)) return;
                    emitResources(self.__ptdUrl, readBody(self));
                });
            } catch (e) { /* egal */ }
            return xsend.apply(this, arguments);
        };
    } catch (e) { /* XHR bleibt unveraendert */ }

    try {
        var nativeFetch = window.fetch;
        if (typeof nativeFetch === 'function') {
            window.fetch = function (input, init) {
                var url = typeof input === 'string' ? input : (input && input.url) || '';
                var p = nativeFetch.apply(this, arguments);
                if (RES_RE.test(String(url))) {
                    p.then(function (res) {
                        try {
                            res.clone().json().then(function (body) { emitResources(url, body); }, function () {});
                        } catch (e) { /* egal */ }
                        return res;
                    }, function () {});
                }
                return p;
            };
        }
    } catch (e) { /* fetch bleibt unveraendert */ }

    /* ---------------------------------------------------------------------
       Oeffentliche API
       ------------------------------------------------------------------- */
    var settings = readSettings();

    window.PTD = {
        version: VERSION,
        bus: bus,
        store: store,
        defaults: DEFAULTS,
        settings: settings,
        stripAnsi: stripAnsi,
        levelOf: levelOf,
        apply: function () { apply(window.PTD.settings); bus.emit('settings', window.PTD.settings); },
        set: function (path, value) {
            var s = window.PTD.settings;
            var seg = path.split('.');
            var ref = s;
            for (var i = 0; i < seg.length - 1; i++) ref = ref[seg[i]];
            ref[seg[seg.length - 1]] = value;
            writeSettings(s);
            window.PTD.apply();
        },
        get: function (path) {
            var ref = window.PTD.settings;
            var seg = path.split('.');
            for (var i = 0; i < seg.length; i++) {
                if (ref == null) return undefined;
                ref = ref[seg[i]];
            }
            return ref;
        },
        save: function () { writeSettings(window.PTD.settings); },
        reset: function () {
            window.PTD.settings = deepMerge(DEFAULTS, {});
            writeSettings(window.PTD.settings);
            window.PTD.apply();
        }
    };

    apply(settings);

    /* Systemfarbschema live nachziehen, wenn "auto" gewaehlt ist */
    try {
        window.matchMedia('(prefers-color-scheme: light)').addEventListener('change', function () {
            if (window.PTD.settings.mode === 'auto') window.PTD.apply();
        });
    } catch (e) { /* aeltere Browser */ }
})();
