/* =========================================================================
   Nebula · 70-notify.js
   Rueckmeldungen zum Serverzustand: Meldungen, Seitentitel, Favicon-Punkt,
   optionale Desktop-Hinweise und Signalton.

   Zusaetzlich zwei Wachfunktionen:
     · Schluesselwoerter, die in der Konsole beobachtet werden
     · Auslastungsschwellen fuer CPU und Arbeitsspeicher
   ========================================================================= */

(function () {
    'use strict';
    var PTD = window.PTD;
    if (!PTD) return;

    var COLORS = {
        running: '#3ddc97', starting: '#f5b73d', stopping: '#f5b73d',
        offline: '#5b6275', missing: '#ff6b7f'
    };
    var TEXT = {
        running: 'Server ist online', starting: 'Server startet',
        stopping: 'Server wird gestoppt', offline: 'Server ist offline',
        missing: 'Container fehlt'
    };
    var TYPE = { running: 'ok', starting: 'info', stopping: 'warn', offline: 'warn', missing: 'danger' };
    var SYMBOL = { running: '●', starting: '◐', stopping: '◑', offline: '○', missing: '⚠' };

    var baseTitle = document.title;
    var originalIcon = null;

    /* =====================================================================
       Favicon
       ===================================================================== */

    function iconLink() {
        var link = document.querySelector('link[rel~="icon"]');
        if (!link) {
            link = document.createElement('link');
            link.rel = 'icon';
            document.head.appendChild(link);
        }
        if (originalIcon === null) originalIcon = link.getAttribute('href') || '/favicon.ico';
        return link;
    }

    function paintFavicon(color) {
        try {
            var link = iconLink();
            var canvas = document.createElement('canvas');
            canvas.width = canvas.height = 64;
            var ctx = canvas.getContext('2d');
            if (!ctx) return;

            function overlay() {
                ctx.beginPath();
                ctx.arc(48, 48, 15, 0, Math.PI * 2);
                ctx.fillStyle = '#07080d';
                ctx.fill();
                ctx.beginPath();
                ctx.arc(48, 48, 11, 0, Math.PI * 2);
                ctx.fillStyle = color;
                ctx.fill();
                try { link.setAttribute('href', canvas.toDataURL('image/png')); } catch (e) { /* getaintet */ }
            }

            var img = new Image();
            img.crossOrigin = 'anonymous';
            img.onload = function () {
                try { ctx.drawImage(img, 0, 0, 64, 64); } catch (e) { /* ignorieren */ }
                overlay();
            };
            img.onerror = function () {
                ctx.fillStyle = '#101219';
                ctx.fillRect(2, 2, 60, 60);
                overlay();
            };
            img.src = originalIcon;
        } catch (e) { /* Favicon ist nur Beiwerk */ }
    }

    function restoreFavicon() {
        if (originalIcon === null) return;
        try { iconLink().setAttribute('href', originalIcon); } catch (e) { /* egal */ }
    }

    function updateTitle(state) {
        if (PTD.route.page !== 'server') { document.title = baseTitle; return; }
        var clean = document.title.replace(/^[●○◐◑⚠]\s*/, '');
        document.title = (SYMBOL[state] || '○') + ' ' + clean;
    }

    /* =====================================================================
       Ton und Desktop-Hinweis
       ===================================================================== */

    function beep(up) {
        if (!PTD.get('notifySound')) return;
        try {
            var Ctx = window.AudioContext || window.webkitAudioContext;
            if (!Ctx) return;
            var ctx = new Ctx();
            var osc = ctx.createOscillator();
            var gain = ctx.createGain();
            osc.type = 'sine';
            osc.frequency.setValueAtTime(up ? 660 : 420, ctx.currentTime);
            osc.frequency.exponentialRampToValueAtTime(up ? 880 : 300, ctx.currentTime + 0.16);
            gain.gain.setValueAtTime(0.0001, ctx.currentTime);
            gain.gain.exponentialRampToValueAtTime(0.08, ctx.currentTime + 0.02);
            gain.gain.exponentialRampToValueAtTime(0.0001, ctx.currentTime + 0.34);
            osc.connect(gain).connect(ctx.destination);
            osc.start();
            osc.stop(ctx.currentTime + 0.36);
            setTimeout(function () { try { ctx.close(); } catch (e) { /* egal */ } }, 700);
        } catch (e) { /* Audio ist optional */ }
    }

    function desktop(title, body) {
        if (!PTD.get('notifyDesktop')) return;
        if (!('Notification' in window) || Notification.permission !== 'granted') return;
        if (!document.hidden) return;
        try { new Notification(title, { body: body, tag: 'ptd-' + PTD.route.server }); } catch (e) { /* egal */ }
    }

    /* =====================================================================
       Statuswechsel
       ===================================================================== */

    PTD.bus.on('state', function (e) {
        paintFavicon(COLORS[e.to] || COLORS.offline);
        updateTitle(e.to);
        if (!PTD.get('modules.notify') || e.from === e.to) return;

        PTD.toast({
            type: TYPE[e.to] || 'info',
            title: TEXT[e.to] || ('Status: ' + e.to),
            msg: e.from ? 'Vorher: ' + (TEXT[e.from] || e.from) : ''
        });
        beep(e.to === 'running');
        desktop(TEXT[e.to] || e.to, 'Server ' + (PTD.route.server || ''));
    });

    PTD.bus.on('daemon:error', function (msg) {
        if (!PTD.get('modules.notify')) return;
        PTD.toast({ type: 'danger', title: 'Daemon-Fehler', msg: String(msg).slice(0, 220), timeout: 9000 });
    });

    PTD.bus.on('backup:done', function () {
        if (!PTD.get('modules.notify')) return;
        PTD.toast({ type: 'ok', title: 'Backup abgeschlossen' });
    });

    PTD.bus.on('transfer', function (status) {
        if (!PTD.get('modules.notify')) return;
        PTD.toast({ type: 'info', title: 'Transfer', msg: String(status) });
    });

    /* =====================================================================
       Absturzerkennung
       ===================================================================== */

    var CRASH = /(exited with code (?!0\b)\d+|marked as offline|Container marked as offline|process exited unexpectedly|OutOfMemory|Killed process)/i;
    var lastCrash = 0;

    /* =====================================================================
       Schluesselwort-Waechter
       Jeder Eintrag ist entweder ein einfacher Text oder ein Ausdruck der
       Form /muster/i. Treffer werden je Eintrag entprellt.
       ===================================================================== */

    var lastHit = {};

    function compile(entry) {
        var m = String(entry).match(/^\/(.*)\/([gimsuy]*)$/);
        if (m) {
            try { return new RegExp(m[1], m[2].replace('g', '')); } catch (e) { return null; }
        }
        return null;
    }

    function checkWatchers(line) {
        var list = PTD.get('watchers') || [];
        if (!list.length) return;
        for (var i = 0; i < list.length; i++) {
            var entry = list[i];
            if (!entry) continue;
            var re = compile(entry);
            var hit = re ? re.test(line.text) : line.text.toLowerCase().indexOf(String(entry).toLowerCase()) > -1;
            if (!hit) continue;
            if (Date.now() - (lastHit[entry] || 0) < 8000) continue;
            lastHit[entry] = Date.now();
            PTD.toast({
                type: 'info',
                title: 'Treffer: ' + entry,
                msg: line.text.slice(0, 180),
                timeout: 8000
            });
            desktop('Konsole: ' + entry, line.text.slice(0, 120));
            beep(true);
        }
    }

    PTD.bus.on('console:line', function (line) {
        if (!PTD.get('modules.notify')) return;
        checkWatchers(line);
        if (!CRASH.test(line.text)) return;
        if (Date.now() - lastCrash < 15000) return;
        lastCrash = Date.now();
        PTD.toast({ type: 'danger', title: 'Moeglicher Absturz erkannt', msg: line.text.slice(0, 200), timeout: 12000 });
        desktop('Moeglicher Absturz', line.text.slice(0, 120));
    });

    /* =====================================================================
       Auslastungsschwellen
       Eine Warnung erst, wenn der Wert laenger als die eingestellte Haltezeit
       ueber der Schwelle liegt – so loesen einzelne Spitzen nichts aus.
       ===================================================================== */

    var over = { cpu: 0, mem: 0 };
    var warned = { cpu: false, mem: false };
    var seenLimit = { cpu: null, mem: null };

    function threshold(kind, ratio) {
        var limit = PTD.get(kind === 'cpu' ? 'alertCpu' : 'alertMem');

        /* Wird die Schwelle veraendert, gilt sie sofort: die Wache wird neu
           scharf gestellt, statt auf das naechste Unterschreiten zu warten. */
        if (seenLimit[kind] !== limit) {
            seenLimit[kind] = limit;
            over[kind] = 0;
            warned[kind] = false;
        }

        if (!limit) { over[kind] = 0; warned[kind] = false; return; }
        var hold = (PTD.get('alertHold') || 20) * 1000;
        var pct = ratio * 100;

        if (pct < limit) {
            if (warned[kind]) {
                PTD.toast({
                    type: 'ok',
                    title: (kind === 'cpu' ? 'CPU' : 'Arbeitsspeicher') + ' wieder normal',
                    msg: PTD.fmt.pct(pct)
                });
            }
            over[kind] = 0;
            warned[kind] = false;
            return;
        }

        if (!over[kind]) over[kind] = Date.now();
        if (warned[kind] || Date.now() - over[kind] < hold) return;

        warned[kind] = true;
        var name = kind === 'cpu' ? 'CPU' : 'Arbeitsspeicher';
        PTD.toast({
            type: 'warn',
            title: name + ' ueber ' + limit + ' %',
            msg: 'Seit ' + Math.round((Date.now() - over[kind]) / 1000) + ' s bei ' + PTD.fmt.pct(pct),
            timeout: 10000
        });
        desktop(name + ' hoch', PTD.fmt.pct(pct));
        beep(false);
    }

    PTD.bus.on('stats', function (p) {
        if (!PTD.get('modules.notify')) return;
        var cap = PTD.cache.get('limits:' + PTD.route.server, 600000);
        var cpuCap = (cap && cap.cpu) || 100;
        threshold('cpu', cpuCap ? p.cpu / cpuCap : 0);
        var memCap = p.memLimit || (cap && cap.memory ? cap.memory * 1048576 : 0);
        threshold('mem', memCap ? p.mem / memCap : 0);
    });

    PTD.bus.on('route', function () {
        baseTitle = document.title.replace(/^[●○◐◑⚠]\s*/, '');
        over = { cpu: 0, mem: 0 };
        warned = { cpu: false, mem: false };
        seenLimit = { cpu: null, mem: null };
        if (PTD.route.page !== 'server') restoreFavicon();
    });

    PTD.notify = { beep: beep, favicon: paintFavicon, restoreFavicon: restoreFavicon, desktop: desktop };
})();
