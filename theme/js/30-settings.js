/* =========================================================================
   Nebula · 30-settings.js
   Einstellungsbereich. Alle Aenderungen wirken sofort und werden im
   localStorage des Browsers gespeichert – am Panel selbst aendert sich
   nichts, die Einstellungen gelten pro Benutzer und Geraet.
   ========================================================================= */

(function () {
    'use strict';
    var PTD = window.PTD;
    if (!PTD) return;

    var el = PTD.el, qs = PTD.qs, icon = PTD.icon;

    var PRESETS = [
        { id: 'nebula', name: 'Nebula', a: '#8b7cff', b: '#2dd4bf' },
        { id: 'ocean',  name: 'Ocean',  a: '#4d90ff', b: '#22d3ee' },
        { id: 'forest', name: 'Forest', a: '#34d399', b: '#a3e635' },
        { id: 'ember',  name: 'Ember',  a: '#ff8a4c', b: '#ff5470' },
        { id: 'rose',   name: 'Rose',   a: '#ff6b9d', b: '#b57bff' },
        { id: 'solar',  name: 'Solar',  a: '#f5c542', b: '#ff9f45' },
        { id: 'carbon', name: 'Carbon', a: '#5eead4', b: '#38bdf8' },
        { id: 'mono',   name: 'Mono',   a: '#d9dde8', b: '#8d95a8' }
    ];

    var TABS = [
        { id: 'design', label: 'Design' },
        { id: 'layout', label: 'Layout' },
        { id: 'modules', label: 'Module' },
        { id: 'alerts', label: 'Warnungen' },
        { id: 'console', label: 'Konsole' },
        { id: 'data', label: 'Daten' }
    ];

    var drawer = null, overlay = null, fab = null, bodyHost = null, tabHost = null;
    var current = 'design';

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

    function block(label, control, hint) {
        return el('div', { class: 'ptd-d-row', style: { display: 'block' } }, [
            el('span', { class: 'ptd-d-label', text: label, style: { display: 'block', marginBottom: '.45rem' } }),
            hint ? el('span', { class: 'ptd-d-hint', text: hint, style: { marginBottom: '.45rem' } }) : null,
            control
        ]);
    }

    function toggle(path, onChange) {
        var b = el('button', {
            class: 'ptd-switch', type: 'button',
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
                type: 'button', text: o.label,
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
        var out = el('span', {
            style: { fontSize: 'var(--ptd-fs-xs)', color: 'var(--ptd-muted)', minWidth: '42px', textAlign: 'right' },
            text: PTD.get(path) + (suffix || '')
        });
        var input = el('input', {
            type: 'range', class: 'ptd-range',
            min: min, max: max, step: step || 1, value: PTD.get(path), 'aria-label': path
        });
        input.addEventListener('input', function () {
            out.textContent = input.value + (suffix || '');
            PTD.set(path, Number(input.value));
        });
        return el('div', { style: { display: 'flex', alignItems: 'center', gap: '.5rem' } }, [input, out]);
    }

    function listEditor(path, placeholder, hint) {
        var host = el('div', { class: 'ptd-list' });

        function paint() {
            var list = PTD.get(path) || [];
            host.innerHTML = '';
            if (!list.length) {
                host.appendChild(el('div', { class: 'ptd-list-empty', text: hint || 'Noch keine Eintraege.' }));
            }
            list.forEach(function (item, i) {
                host.appendChild(el('div', { class: 'ptd-list-row' }, [
                    el('code', { text: item }),
                    el('button', {
                        type: 'button', 'aria-label': 'Entfernen', html: icon('close', 12),
                        onclick: function () {
                            var copy = (PTD.get(path) || []).slice();
                            copy.splice(i, 1);
                            PTD.settings[path] = copy;
                            PTD.save();
                            paint();
                        }
                    })
                ]));
            });
        }

        var input = el('input', { type: 'text', class: 'ptd-input-text', placeholder: placeholder });
        function add() {
            var v = input.value.trim();
            if (!v) return;
            PTD.settings[path] = (PTD.get(path) || []).concat([v]);
            PTD.save();
            input.value = '';
            paint();
        }
        input.addEventListener('keydown', function (e) { if (e.key === 'Enter') { e.preventDefault(); add(); } });

        paint();
        return el('div', {}, [
            host,
            el('div', { class: 'ptd-list-add' }, [
                input,
                el('button', { type: 'button', text: 'Hinzufuegen', onclick: add })
            ])
        ]);
    }

    function currentAccent() {
        var v = PTD.get('accent');
        if (v) return v;
        var p = PRESETS.filter(function (x) { return x.id === PTD.get('preset'); })[0];
        return p ? p.a : '#8b7cff';
    }

    function swatches() {
        var grid = el('div', { class: 'ptd-swatches' });
        PRESETS.forEach(function (p) {
            var b = el('button', {
                type: 'button', class: 'ptd-swatch', title: p.name,
                'aria-pressed': PTD.get('preset') === p.id ? 'true' : 'false',
                style: { background: 'linear-gradient(140deg,' + p.a + ',' + p.b + ')' }
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

    /* =====================================================================
       Reiterinhalte
       ===================================================================== */

    function paneDesign() {
        var accent = el('input', {
            type: 'color', id: 'ptd-accent-picker', value: currentAccent(),
            'aria-label': 'Akzentfarbe',
            style: {
                width: '42px', height: '26px', padding: '0', border: '1px solid var(--ptd-line)',
                borderRadius: '7px', background: 'transparent', cursor: 'pointer'
            }
        });
        accent.addEventListener('input', function () { PTD.set('accent', accent.value); });

        var bgUrl = el('input', {
            type: 'url', class: 'ptd-input-text', placeholder: 'https://… Bild-URL',
            value: PTD.get('bgImage') || ''
        });
        bgUrl.addEventListener('change', function () { PTD.set('bgImage', bgUrl.value.trim()); });
        var bgUrlRow = el('div', {
            class: 'ptd-d-row',
            style: { display: PTD.get('bg') === 'image' ? 'block' : 'none' }
        }, [bgUrl]);

        return [
            section('Farbschema', [
                row('Modus', segmented('mode', [
                    { value: 'dark', label: 'Dunkel' },
                    { value: 'light', label: 'Hell' },
                    { value: 'auto', label: 'Auto' }
                ])),
                block('Preset', swatches()),
                row('Eigene Akzentfarbe', accent, 'Ueberschreibt die Preset-Farbe')
            ]),
            section('Hintergrund', [
                row('Stil', segmented('bg', [
                    { value: 'aurora', label: 'Aurora' },
                    { value: 'plain', label: 'Schlicht' },
                    { value: 'image', label: 'Bild' }
                ], function (v) { bgUrlRow.style.display = v === 'image' ? 'block' : 'none'; })),
                bgUrlRow
            ]),
            section('Schrift', [
                row('Webfonts laden', toggle('webfonts'),
                    'Inter und JetBrains Mono von Google Fonts. Aus = Systemschriften.')
            ]),
            el('p', {
                class: 'ptd-d-hint',
                text: 'Die Farben der Verlaufsdiagramme folgen bewusst nicht dem Preset. Sie sind fest ' +
                      'vergeben und auf Farbfehlsichtigkeit geprueft, damit die vier Reihen unterscheidbar bleiben.'
            })
        ];
    }

    function paneLayout() {
        return [
            section('Navigation', [
                row('Seitenschiene', segmented('rail', [
                    { value: 'full', label: 'Breit' },
                    { value: 'mini', label: 'Schmal' }
                ])),
                row('Uhr in der Kopfleiste', toggle('clock')),
                row('Schnellzugriff-Knopf', toggle('fab'), 'Das Zahnrad unten rechts'),
                row('Fusszeile', toggle('footer'))
            ]),
            section('Form', [
                row('Eckenradius', range('radius', 0, 26, 1, 'px')),
                row('Glas-Unschaerfe', range('blur', 0, 40, 2, 'px')),
                row('Glaseffekt', toggle('glass')),
                row('Kompakte Ansicht', toggle('compact'), 'Geringere Abstaende, kleinere Radien'),
                row('Breites Layout', toggle('wide'), 'Inhalt bis 1720 px'),
                row('Animationen', toggle('motion'),
                    'Aus entspricht der Systemeinstellung fuer reduzierte Bewegung.')
            ])
        ];
    }

    function paneModules() {
        function mod(label, key, hint) { return row(label, toggle('modules.' + key, remount), hint); }
        return [
            section('Oberflaeche', [
                mod('Seitenschiene', 'rail', 'Aus = Panel-eigene Kopfleiste'),
                mod('Befehlspalette', 'palette', 'Strg + K'),
                mod('Serveruebersicht', 'overview', 'Kacheln mit Live-Auslastung'),
                mod('UI-Erweiterungen', 'enhance', 'Fusszeile, Kopierfelder, Login-Kopf')
            ]),
            section('Server', [
                mod('Konsolen-Werkzeuge', 'console', 'Suche, Filter, Export, Vollbild'),
                mod('Kurzbefehle', 'snippets', 'Leiste unter der Werkzeugleiste'),
                mod('Mini-Konsole', 'dock', 'Schwebendes Fenster'),
                mod('Live-Graphen', 'charts', 'CPU, RAM, Netzwerk, Festplatte')
            ]),
            section('Sonstiges', [
                mod('Statusmeldungen', 'notify'),
                mod('Tastenkuerzel', 'shortcuts')
            ])
        ];
    }

    function paneAlerts() {
        return [
            section('Zustellung', [
                row('Desktop-Hinweise', toggle('notifyDesktop', function (v) {
                    if (v && 'Notification' in window && Notification.permission === 'default') {
                        Notification.requestPermission();
                    }
                }), 'Nur wenn der Tab im Hintergrund ist'),
                row('Signalton', toggle('notifySound'))
            ]),
            section('Auslastung', [
                row('CPU-Schwelle', range('alertCpu', 0, 100, 5, '%'), '0 = aus'),
                row('RAM-Schwelle', range('alertMem', 0, 100, 5, '%'), '0 = aus'),
                row('Haltezeit', range('alertHold', 5, 120, 5, 's'),
                    'Erst nach dieser Dauer ueber der Schwelle wird gewarnt.')
            ]),
            section('Schluesselwoerter in der Konsole', [
                block('Ueberwachte Begriffe',
                    listEditor('watchers', 'z. B. joined the game oder /error/i'),
                    'Einfacher Text oder ein Ausdruck der Form /muster/i.')
            ])
        ];
    }

    function paneConsole() {
        var id = PTD.route.server;
        var rows = [
            section('Darstellung', [
                row('Zeitstempel', toggle('consoleTimestamps')),
                row('Schriftgroesse', range('consoleFontSize', 10, 20, 1, 'px'),
                    'Gilt fuer die Puffer-Ansicht. Das Terminal selbst rendert auf Canvas.'),
                row('Verlaufspunkte', range('historyPoints', 30, 400, 10, ''),
                    'Wie viele Messpunkte die Diagramme zeigen.')
            ])
        ];

        if (id) {
            var host = el('div', { class: 'ptd-list' });
            function paint() {
                var all = PTD.get('snippets') || {};
                var list = all[id] || [];
                host.innerHTML = '';
                if (!list.length) host.appendChild(el('div', { class: 'ptd-list-empty', text: 'Noch keine Kurzbefehle fuer diesen Server.' }));
                list.forEach(function (cmd, i) {
                    host.appendChild(el('div', { class: 'ptd-list-row' }, [
                        el('code', { text: cmd }),
                        el('button', {
                            type: 'button', 'aria-label': 'Entfernen', html: icon('close', 12),
                            onclick: function () {
                                var copy = list.slice();
                                copy.splice(i, 1);
                                var m = PTD.get('snippets') || {};
                                if (copy.length) m[id] = copy; else delete m[id];
                                PTD.settings.snippets = m;
                                PTD.save();
                                paint();
                                PTD.bus.emit('settings', PTD.settings);
                            }
                        })
                    ]));
                });
            }
            var input = el('input', { type: 'text', class: 'ptd-input-text', placeholder: 'z. B. say Neustart in 5 Minuten' });
            function add() {
                var v = input.value.trim();
                if (!v) return;
                var m = PTD.get('snippets') || {};
                m[id] = (m[id] || []).concat([v]);
                PTD.settings.snippets = m;
                PTD.save();
                input.value = '';
                paint();
                PTD.bus.emit('settings', PTD.settings);
            }
            input.addEventListener('keydown', function (e) { if (e.key === 'Enter') { e.preventDefault(); add(); } });
            paint();

            rows.push(section('Kurzbefehle dieses Servers', [
                block('Befehle', el('div', {}, [
                    host,
                    el('div', { class: 'ptd-list-add' }, [input, el('button', { type: 'button', text: 'Hinzufuegen', onclick: add })])
                ]), 'Ein Klick sendet den Befehl ueber die bestehende Konsolenverbindung.')
            ]));
        } else {
            rows.push(el('p', { class: 'ptd-d-hint', text: 'Kurzbefehle werden je Server verwaltet. Oeffne einen Server, um sie zu bearbeiten.' }));
        }

        return rows;
    }

    function paneData() {
        return [
            section('Sicherung', [
                el('p', { class: 'ptd-d-hint', text: 'Alle Einstellungen liegen im Browser dieses Geraets. Der Export enthaelt auch Markierungen, Kurzbefehle und angeheftete Server.' }),
                el('div', { class: 'ptd-d-actions' }, [
                    el('button', { type: 'button', text: 'Exportieren', onclick: exportSettings }),
                    el('button', { type: 'button', text: 'Importieren', onclick: importSettings })
                ])
            ]),
            section('Zuruecksetzen', [
                row('Angeheftete Server', el('button', {
                    class: 'ptd-cbtn', type: 'button', text: String((PTD.get('favorites') || []).length) + ' loeschen',
                    onclick: function () { PTD.settings.favorites = []; PTD.save(); PTD.bus.emit('favorites', []); rebuild(); }
                })),
                row('Markierungen', el('button', {
                    class: 'ptd-cbtn', type: 'button', text: String(Object.keys(PTD.get('tags') || {}).length) + ' loeschen',
                    onclick: function () { PTD.settings.tags = {}; PTD.save(); PTD.bus.emit('tags', {}); rebuild(); }
                })),
                row('Kurzbefehle', el('button', {
                    class: 'ptd-cbtn', type: 'button', text: String(Object.keys(PTD.get('snippets') || {}).length) + ' Server',
                    onclick: function () { PTD.settings.snippets = {}; PTD.save(); PTD.bus.emit('settings', PTD.settings); rebuild(); }
                })),
                el('div', { class: 'ptd-d-actions' }, [
                    el('button', { type: 'button', text: 'Alles zuruecksetzen', onclick: resetSettings })
                ])
            ]),
            el('p', { class: 'ptd-d-hint', text: 'Nebula ' + PTD.version + ' · Entfernen des Themes am Server: nebula uninstall' })
        ];
    }

    var PANES = {
        design: paneDesign, layout: paneLayout, modules: paneModules,
        alerts: paneAlerts, console: paneConsole, data: paneData
    };

    /* =====================================================================
       Aufbau
       ===================================================================== */

    function paintPane() {
        if (!bodyHost) return;
        bodyHost.innerHTML = '';
        (PANES[current] || paneDesign)().forEach(function (n) { if (n) bodyHost.appendChild(n); });
        Array.prototype.forEach.call(tabHost.children, function (b) {
            b.setAttribute('aria-selected', b.getAttribute('data-tab') === current ? 'true' : 'false');
        });
    }

    function rebuild() { paintPane(); }

    function build() {
        overlay = el('div', { class: 'ptd-overlay', id: 'ptd-drawer-overlay' });
        overlay.addEventListener('click', close);

        tabHost = el('div', { class: 'ptd-d-tabs', role: 'tablist' });
        TABS.forEach(function (t) {
            var b = el('button', {
                type: 'button', role: 'tab', 'data-tab': t.id, text: t.label,
                'aria-selected': current === t.id ? 'true' : 'false'
            });
            b.addEventListener('click', function () { current = t.id; paintPane(); });
            tabHost.appendChild(b);
        });

        bodyHost = el('div', { class: 'ptd-d-body' });

        drawer = el('aside', { id: 'ptd-drawer', role: 'dialog', 'aria-label': 'Nebula Einstellungen' }, [
            el('div', { class: 'ptd-d-head' }, [
                el('h2', {}, [
                    el('span', { html: icon('sparkles', 16), style: { color: 'var(--ptd-accent)', display: 'inline-flex' } }),
                    el('span', { text: 'Nebula' }),
                    el('span', { class: 'ptd-ver', text: 'v' + PTD.version })
                ]),
                el('button', {
                    class: 'ptd-d-close', type: 'button', html: icon('close', 15),
                    onclick: close, 'aria-label': 'Schliessen'
                })
            ]),
            tabHost,
            bodyHost
        ]);

        document.body.appendChild(overlay);
        document.body.appendChild(drawer);
        paintPane();
    }

    /* =====================================================================
       Aktionen
       ===================================================================== */

    function remount() { PTD.bus.emit('remount'); }

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

    function open(tab) {
        if (!drawer) build();
        if (tab && PANES[tab]) { current = tab; }
        paintPane();
        overlay.classList.add('is-open');
        drawer.classList.add('is-open');
    }

    function close() {
        if (!drawer) return;
        overlay.classList.remove('is-open');
        drawer.classList.remove('is-open');
    }

    function isOpen() { return !!drawer && drawer.classList.contains('is-open'); }

    /* =====================================================================
       Schwebender Knopf
       ===================================================================== */

    PTD.ready(function () {
        fab = el('button', {
            id: 'ptd-fab', type: 'button',
            'aria-label': 'Nebula Einstellungen',
            'data-ptd-tip': 'Nebula · Strg ⇧ E',
            html: icon('sparkles', 19),
            onclick: function () { isOpen() ? close() : open(); }
        });
        document.body.appendChild(fab);
    });

    PTD.settingsPanel = {
        open: open, close: close,
        toggle: function () { isOpen() ? close() : open(); },
        isOpen: isOpen
    };
})();
