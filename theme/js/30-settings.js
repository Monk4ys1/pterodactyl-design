/* =========================================================================
   Nebula · 30-settings.js
   Schwebender Schalter + Einstellungs-Drawer. Alle Aenderungen wirken
   sofort und werden im localStorage des Browsers gespeichert.
   ========================================================================= */

(function () {
    'use strict';
    var PTD = window.PTD;
    if (!PTD) return;

    var el = PTD.el, qs = PTD.qs, icon = PTD.icon;

    var PRESETS = [
        { id: 'nebula',   name: 'Nebula',   a: '#7c6cff', b: '#22d3ee' },
        { id: 'ocean',    name: 'Ocean',    a: '#3b82f6', b: '#06b6d4' },
        { id: 'forest',   name: 'Forest',   a: '#22c55e', b: '#a3e635' },
        { id: 'ember',    name: 'Ember',    a: '#f97316', b: '#ef4444' },
        { id: 'rose',     name: 'Rose',     a: '#ec4899', b: '#a855f7' },
        { id: 'solar',    name: 'Solar',    a: '#eab308', b: '#f97316' },
        { id: 'midnight', name: 'Midnight', a: '#6366f1', b: '#8b5cf6' },
        { id: 'mono',     name: 'Mono',     a: '#e5e7eb', b: '#9ca3af' }
    ];

    var drawer = null, overlay = null, fab = null;

    /* =====================================================================
       Bausteine
       ===================================================================== */

    function section(title, rows) {
        return el('div', { class: 'ptd-d-section' }, [el('h3', { text: title })].concat(rows));
    }

    function row(label, control, hint) {
        return el('div', { class: 'ptd-d-row' }, [
            el('div', {}, [
                el('span', { class: 'ptd-d-label', text: label }),
                hint ? el('span', { class: 'ptd-d-hint', text: hint }) : null
            ]),
            control
        ]);
    }

    function toggle(path, onChange) {
        var b = el('button', {
            class: 'ptd-switch',
            type: 'button',
            'aria-pressed': PTD.get(path) ? 'true' : 'false',
            'aria-label': path
        });
        b.addEventListener('click', function () {
            var v = !PTD.get(path);
            b.setAttribute('aria-pressed', v ? 'true' : 'false');
            PTD.set(path, v);
            if (onChange) onChange(v);
        });
        return b;
    }

    function segmented(path, options, onChange) {
        var wrap = el('div', { class: 'ptd-seg' });
        options.forEach(function (o) {
            var b = el('button', {
                type: 'button',
                text: o.label,
                'aria-pressed': PTD.get(path) === o.value ? 'true' : 'false'
            });
            b.addEventListener('click', function () {
                PTD.set(path, o.value);
                Array.prototype.forEach.call(wrap.children, function (c) { c.setAttribute('aria-pressed', 'false'); });
                b.setAttribute('aria-pressed', 'true');
                if (onChange) onChange(o.value);
            });
            wrap.appendChild(b);
        });
        return wrap;
    }

    function range(path, min, max, step, suffix) {
        var wrap = el('div', { style: { display: 'flex', alignItems: 'center', gap: '.5rem' } });
        var out = el('span', {
            style: { fontSize: '.72rem', color: 'var(--ptd-muted)', minWidth: '38px', textAlign: 'right' },
            text: PTD.get(path) + (suffix || '')
        });
        var input = el('input', {
            type: 'range', class: 'ptd-range',
            min: min, max: max, step: step || 1, value: PTD.get(path)
        });
        input.addEventListener('input', function () {
            out.textContent = input.value + (suffix || '');
            PTD.set(path, Number(input.value));
        });
        wrap.appendChild(input);
        wrap.appendChild(out);
        return wrap;
    }

    /* =====================================================================
       Drawer aufbauen
       ===================================================================== */

    function buildSwatches() {
        var grid = el('div', { class: 'ptd-swatches' });
        PRESETS.forEach(function (p) {
            var b = el('button', {
                type: 'button',
                class: 'ptd-swatch',
                title: p.name,
                'aria-pressed': PTD.get('preset') === p.id ? 'true' : 'false',
                style: { background: 'linear-gradient(135deg,' + p.a + ',' + p.b + ')' }
            }, [el('span', { text: p.name })]);
            b.addEventListener('click', function () {
                PTD.settings.accent = '';
                PTD.set('preset', p.id);
                Array.prototype.forEach.call(grid.children, function (c) { c.setAttribute('aria-pressed', 'false'); });
                b.setAttribute('aria-pressed', 'true');
                var picker = qs('#ptd-accent-picker');
                if (picker) picker.value = p.a;
            });
            grid.appendChild(b);
        });
        return grid;
    }

    function currentAccent() {
        var v = PTD.get('accent');
        if (v) return v;
        var p = PRESETS.filter(function (x) { return x.id === PTD.get('preset'); })[0];
        return p ? p.a : '#7c6cff';
    }

    function build() {
        overlay = el('div', { class: 'ptd-overlay', id: 'ptd-drawer-overlay' });
        overlay.addEventListener('click', close);

        var accent = el('input', {
            type: 'color', id: 'ptd-accent-picker',
            value: currentAccent(),
            style: {
                width: '42px', height: '26px', padding: '0', border: '1px solid var(--ptd-line)',
                borderRadius: '7px', background: 'transparent', cursor: 'pointer'
            }
        });
        accent.addEventListener('input', function () { PTD.set('accent', accent.value); });

        var bgUrlRow = el('div', { class: 'ptd-d-row', style: { display: PTD.get('bg') === 'image' ? 'block' : 'none' } }, [
            el('input', {
                type: 'url', class: 'ptd-input-text', id: 'ptd-bg-url',
                placeholder: 'https://… Bild-URL', value: PTD.get('bgImage') || ''
            })
        ]);
        bgUrlRow.querySelector('input').addEventListener('change', function (e) {
            PTD.set('bgImage', e.target.value.trim());
        });

        var body = el('div', { class: 'ptd-d-body' }, [
            section('Erscheinungsbild', [
                row('Farbschema', segmented('mode', [
                    { value: 'dark', label: 'Dunkel' },
                    { value: 'light', label: 'Hell' },
                    { value: 'auto', label: 'Auto' }
                ])),
                el('div', { class: 'ptd-d-row', style: { display: 'block' } }, [
                    el('span', { class: 'ptd-d-label', text: 'Farbpreset', style: { display: 'block', marginBottom: '.55rem' } }),
                    buildSwatches()
                ]),
                row('Eigene Akzentfarbe', accent, 'Ueberschreibt die Preset-Farbe')
            ]),

            section('Layout', [
                row('Eckenradius', range('radius', 0, 24, 1, 'px')),
                row('Glas-Unschaerfe', range('blur', 0, 40, 2, 'px')),
                row('Glaseffekt', toggle('glass')),
                row('Kompakte Ansicht', toggle('compact'), 'Geringere Abstaende, schmalere Navigation'),
                row('Breites Layout', toggle('wide'), 'Container bis 1600 px'),
                row('Animationen', toggle('motion'))
            ]),

            section('Hintergrund', [
                row('Stil', segmented('bg', [
                    { value: 'aurora', label: 'Aurora' },
                    { value: 'plain', label: 'Schlicht' },
                    { value: 'image', label: 'Bild' }
                ], function (v) { bgUrlRow.style.display = v === 'image' ? 'block' : 'none'; })),
                bgUrlRow
            ]),

            section('Funktionen', [
                row('Command-Palette', toggle('modules.palette'), 'Strg + K'),
                row('Konsolen-Werkzeuge', toggle('modules.console', remount), 'Suche, Export, Filter, Vollbild'),
                row('Live-Graphen', toggle('modules.charts', remount), 'CPU, RAM, Netzwerk, Festplatte'),
                row('Statusmeldungen', toggle('modules.notify')),
                row('Tastenkuerzel', toggle('modules.shortcuts')),
                row('UI-Erweiterungen', toggle('modules.enhance'), 'Serverleiste, Kopierfelder, Fusszeile')
            ]),

            section('Benachrichtigungen', [
                row('Desktop-Hinweise', toggle('notifyDesktop', function (v) {
                    if (v && 'Notification' in window && Notification.permission === 'default') {
                        Notification.requestPermission();
                    }
                }), 'Meldung bei Statuswechsel des Servers'),
                row('Signalton', toggle('notifySound'))
            ]),

            section('Konsole', [
                row('Zeitstempel', toggle('consoleTimestamps')),
                row('Schriftgroesse', range('consoleFontSize', 10, 20, 1, 'px')),
                row('Verlaufspunkte', range('historyPoints', 30, 300, 10, ''))
            ]),

            section('Sonstiges', [
                row('Schnellzugriff-Knopf', toggle('fab'), 'Dieses Zahnrad ausblenden'),
                row('Webfonts laden', toggle('webfonts'), 'Inter + JetBrains Mono von Google Fonts'),
                row('Begruessung', toggle('greeting')),
                row('Fusszeile', toggle('footer')),
                el('div', { class: 'ptd-d-actions' }, [
                    el('button', { type: 'button', text: 'Export', onclick: exportSettings }),
                    el('button', { type: 'button', text: 'Import', onclick: importSettings }),
                    el('button', { type: 'button', text: 'Zuruecksetzen', onclick: resetSettings })
                ])
            ])
        ]);

        drawer = el('div', { id: 'ptd-drawer', role: 'dialog', 'aria-label': 'Nebula Einstellungen' }, [
            el('div', { class: 'ptd-d-head' }, [
                el('h2', {}, [
                    el('span', { html: icon('wand', 17), style: { color: 'var(--ptd-accent)', display: 'inline-flex' } }),
                    el('span', { text: 'Nebula' }),
                    el('span', { class: 'ptd-ver', text: 'v' + PTD.version })
                ]),
                el('button', { class: 'ptd-d-close', type: 'button', html: icon('close', 16), onclick: close, 'aria-label': 'Schliessen' })
            ]),
            body
        ]);

        document.body.appendChild(overlay);
        document.body.appendChild(drawer);
    }

    /* =====================================================================
       Aktionen
       ===================================================================== */

    function remount() {
        PTD.bus.emit('remount');
    }

    function exportSettings() {
        var json = JSON.stringify(PTD.settings, null, 2);
        if (navigator.clipboard && navigator.clipboard.writeText) {
            navigator.clipboard.writeText(json).then(function () {
                PTD.toast({ type: 'ok', title: 'Kopiert', msg: 'Einstellungen liegen in der Zwischenablage.' });
            }, function () { window.prompt('Einstellungen kopieren:', json); });
        } else {
            window.prompt('Einstellungen kopieren:', json);
        }
    }

    function importSettings() {
        var raw = window.prompt('Exportierte Einstellungen einfuegen:');
        if (!raw) return;
        try {
            var parsed = JSON.parse(raw);
            Object.keys(parsed).forEach(function (k) {
                if (k in PTD.settings) PTD.settings[k] = parsed[k];
            });
            PTD.save();
            PTD.apply();
            PTD.toast({ type: 'ok', title: 'Uebernommen', msg: 'Seite wird neu geladen …' });
            setTimeout(function () { location.reload(); }, 800);
        } catch (e) {
            PTD.toast({ type: 'danger', title: 'Fehler', msg: 'Ungueltiges JSON.' });
        }
    }

    function resetSettings() {
        if (!window.confirm('Alle Nebula-Einstellungen zuruecksetzen?')) return;
        PTD.reset();
        PTD.toast({ type: 'ok', title: 'Zurueckgesetzt' });
        setTimeout(function () { location.reload(); }, 600);
    }

    function open() {
        if (!drawer) build();
        overlay.classList.add('is-open');
        drawer.classList.add('is-open');
        document.documentElement.setAttribute('data-ptd-drawer', 'open');
    }

    function close() {
        if (!drawer) return;
        overlay.classList.remove('is-open');
        drawer.classList.remove('is-open');
        document.documentElement.removeAttribute('data-ptd-drawer');
    }

    function isOpen() { return !!drawer && drawer.classList.contains('is-open'); }

    /* =====================================================================
       Schwebender Knopf
       ===================================================================== */

    PTD.ready(function () {
        fab = el('button', {
            id: 'ptd-fab', type: 'button',
            'aria-label': 'Nebula Einstellungen oeffnen',
            title: 'Nebula Einstellungen',
            html: icon('settings', 21),
            onclick: function () { isOpen() ? close() : open(); }
        });
        document.body.appendChild(fab);
    });

    PTD.settingsPanel = { open: open, close: close, toggle: function () { isOpen() ? close() : open(); }, isOpen: isOpen };
})();
