/* =========================================================================
   Nebula · 85-tags.js
   Servermarkierungen: Farbe und Kuerzel je Server. Sie erscheinen in der
   Schiene, auf den Uebersichtskacheln und in der Befehlspalette und machen
   viele Server auf einen Blick unterscheidbar.
   ========================================================================= */

(function () {
    'use strict';
    var PTD = window.PTD;
    if (!PTD) return;

    var el = PTD.el, qs = PTD.qs;

    var COLORS = [
        '#8b7cff', '#4d90ff', '#2dd4bf', '#34d399', '#a3e635',
        '#f5c542', '#ff8a4c', '#ff5470', '#ff6b9d', '#b57bff'
    ];

    function all() { return PTD.get('tags') || {}; }

    function tagOf(id, name) {
        var t = all()[id];
        return {
            color: (t && t.color) || PTD.autoColor(id),
            label: (t && t.label) || PTD.fmt.initials(name || id),
            custom: !!t
        };
    }

    function setTag(id, color, label) {
        var tags = all();
        if (!color && !label) delete tags[id];
        else tags[id] = { color: color || undefined, label: (label || '').slice(0, 3).toUpperCase() || undefined };
        PTD.settings.tags = tags;
        PTD.save();
        PTD.bus.emit('tags', tags);
    }

    /* =====================================================================
       Kleiner Auswahldialog
       ===================================================================== */

    var pop = null;

    function close() {
        if (pop && pop.parentNode) pop.parentNode.removeChild(pop);
        pop = null;
        document.removeEventListener('mousedown', onOutside, true);
        document.removeEventListener('keydown', onKey, true);
    }

    function onOutside(e) { if (pop && !pop.contains(e.target)) close(); }
    function onKey(e) { if (e.key === 'Escape') { e.stopPropagation(); close(); } }

    function open(anchor, id, name) {
        close();
        var current = tagOf(id, name);

        var swatches = el('div', {
            style: { display: 'grid', gridTemplateColumns: 'repeat(5, 1fr)', gap: '.3rem', marginBottom: '.5rem' }
        });
        COLORS.forEach(function (c) {
            var b = el('button', {
                type: 'button',
                'aria-label': c,
                'aria-pressed': current.color === c ? 'true' : 'false',
                style: {
                    height: '22px', borderRadius: '6px', cursor: 'pointer',
                    background: c,
                    border: '1px solid ' + (current.color === c ? 'var(--ptd-text)' : 'transparent')
                }
            });
            b.addEventListener('click', function () {
                setTag(id, c, labelInput.value);
                current.color = c;
                Array.prototype.forEach.call(swatches.children, function (n) {
                    n.style.border = '1px solid transparent';
                    n.setAttribute('aria-pressed', 'false');
                });
                b.style.border = '1px solid var(--ptd-text)';
                b.setAttribute('aria-pressed', 'true');
            });
            swatches.appendChild(b);
        });

        var labelInput = el('input', {
            type: 'text', class: 'ptd-input-text', maxlength: '3',
            value: current.label, placeholder: 'Kuerzel',
            style: { textTransform: 'uppercase' }
        });
        labelInput.addEventListener('input', function () { setTag(id, current.color, labelInput.value); });

        pop = el('div', {
            class: 'ptd-panel',
            style: {
                position: 'fixed', zIndex: '6100', width: '208px', padding: '.6rem',
                boxShadow: 'var(--ptd-e4)'
            }
        }, [
            el('div', {
                class: 'ptd-d-label',
                text: 'Markierung',
                style: { marginBottom: '.4rem', fontWeight: '620' }
            }),
            swatches,
            labelInput,
            el('div', { class: 'ptd-d-actions' }, [
                el('button', {
                    type: 'button', text: 'Zuruecksetzen',
                    onclick: function () { setTag(id, null, null); close(); }
                }),
                el('button', { type: 'button', text: 'Fertig', onclick: close })
            ])
        ]);

        document.body.appendChild(pop);

        var r = anchor.getBoundingClientRect();
        var top = Math.min(r.bottom + 6, window.innerHeight - pop.offsetHeight - 10);
        var left = Math.min(Math.max(8, r.left), window.innerWidth - pop.offsetWidth - 10);
        pop.style.top = top + 'px';
        pop.style.left = left + 'px';

        setTimeout(function () {
            document.addEventListener('mousedown', onOutside, true);
            document.addEventListener('keydown', onKey, true);
        }, 0);
    }

    PTD.tagOf = tagOf;
    PTD.tags = { all: all, get: tagOf, set: setTag, open: open, close: close, colors: COLORS };
})();
