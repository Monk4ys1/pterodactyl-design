/* =========================================================================
   Nebula · 70-notify.js
   Statuswechsel sichtbar machen: Toasts, Seitentitel, Favicon-Punkt,
   optionale Desktop-Hinweise und ein dezenter Signalton.
   ========================================================================= */

(function () {
    'use strict';
    var PTD = window.PTD;
    if (!PTD) return;

    var COLORS = {
        running: '#34d399',
        starting: '#fbbf24',
        stopping: '#fbbf24',
        offline: '#6b7280',
        missing: '#f87171'
    };

    var TEXT = {
        running: 'Server ist online',
        starting: 'Server startet',
        stopping: 'Server wird gestoppt',
        offline: 'Server ist offline',
        missing: 'Container fehlt'
    };

    var TYPE = {
        running: 'ok', starting: 'info', stopping: 'warn',
        offline: 'warn', missing: 'danger'
    };

    var baseTitle = document.title;
    var originalIcon = null;

    /* =====================================================================
       Favicon mit Statuspunkt
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

            var img = new Image();
            img.crossOrigin = 'anonymous';

            function overlay() {
                ctx.beginPath();
                ctx.arc(48, 48, 15, 0, Math.PI * 2);
                ctx.fillStyle = '#0b0d14';
                ctx.fill();
                ctx.beginPath();
                ctx.arc(48, 48, 11, 0, Math.PI * 2);
                ctx.fillStyle = color;
                ctx.fill();
                try { link.setAttribute('href', canvas.toDataURL('image/png')); } catch (e) { /* getaintet */ }
            }

            img.onload = function () {
                try { ctx.drawImage(img, 0, 0, 64, 64); } catch (e) { /* ignorieren */ }
                overlay();
            };
            img.onerror = function () {
                ctx.fillStyle = '#12151f';
                ctx.beginPath();
                ctx.roundRect ? ctx.roundRect(2, 2, 60, 60, 14) : ctx.rect(2, 2, 60, 60);
                ctx.fill();
                overlay();
            };
            img.src = originalIcon;
        } catch (e) { /* Favicon ist nur Beiwerk */ }
    }

    function restoreFavicon() {
        if (originalIcon === null) return;
        try { iconLink().setAttribute('href', originalIcon); } catch (e) { /* egal */ }
    }

    /* =====================================================================
       Seitentitel
       ===================================================================== */

    var SYMBOL = { running: '●', starting: '◐', stopping: '◑', offline: '○', missing: '⚠' };

    function updateTitle(state) {
        if (PTD.route.page !== 'server') { document.title = baseTitle; return; }
        var clean = document.title.replace(/^[●○◐◑⚠]\s*/, '');
        document.title = (SYMBOL[state] || '○') + ' ' + clean;
    }

    /* =====================================================================
       Signalton
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
            gain.gain.exponentialRampToValueAtTime(0.09, ctx.currentTime + 0.02);
            gain.gain.exponentialRampToValueAtTime(0.0001, ctx.currentTime + 0.35);
            osc.connect(gain).connect(ctx.destination);
            osc.start();
            osc.stop(ctx.currentTime + 0.38);
            setTimeout(function () { try { ctx.close(); } catch (e) { /* egal */ } }, 700);
        } catch (e) { /* Audio ist optional */ }
    }

    /* =====================================================================
       Desktop-Hinweis
       ===================================================================== */

    function desktop(title, body) {
        if (!PTD.get('notifyDesktop')) return;
        if (!('Notification' in window) || Notification.permission !== 'granted') return;
        if (!document.hidden) return;
        try { new Notification(title, { body: body, tag: 'ptd-' + PTD.route.server }); } catch (e) { /* egal */ }
    }

    /* =====================================================================
       Ereignisse
       ===================================================================== */

    PTD.bus.on('state', function (e) {
        paintFavicon(COLORS[e.to] || COLORS.offline);
        updateTitle(e.to);

        if (!PTD.get('modules.notify')) return;
        if (e.from === e.to) return;

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

    /* Absturzerkennung aus dem Konsolenstrom */
    var CRASH = /(exited with code (?!0\b)\d+|marked as offline|Container marked as offline|process exited unexpectedly|OutOfMemory|Killed process)/i;
    var lastCrash = 0;

    PTD.bus.on('console:line', function (line) {
        if (!PTD.get('modules.notify')) return;
        if (!CRASH.test(line.text)) return;
        if (Date.now() - lastCrash < 15000) return;
        lastCrash = Date.now();
        PTD.toast({ type: 'danger', title: 'Moeglicher Absturz erkannt', msg: line.text.slice(0, 200), timeout: 12000 });
        desktop('Moeglicher Absturz', line.text.slice(0, 120));
    });

    PTD.bus.on('route', function () {
        baseTitle = document.title.replace(/^[●○◐◑⚠]\s*/, '');
        if (PTD.route.page !== 'server') restoreFavicon();
    });

    PTD.notify = { beep: beep, favicon: paintFavicon, restoreFavicon: restoreFavicon };
})();
