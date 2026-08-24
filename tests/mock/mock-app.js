/* Vereinfachter Nachbau der Pterodactyl-1.11-DOM-Struktur inkl. Client-Routing. */
(function () {
    var app = document.getElementById('app');
    var SID = 'a1b2c3d4';

    function nav() {
        return '' +
        '<div id="navigation" class="w-full bg-neutral-900 shadow-md overflow-x-auto">' +
          '<div class="mx-auto w-full flex items-center" style="height:3.5rem;max-width:1200px">' +
            '<div id="logo" class="flex-1"><a href="/" class="text-2xl px-4 no-underline text-neutral-200">MeinPanel</a></div>' +
            '<div class="right-navigation flex h-full items-center justify-center">' +
              '<a href="/account" class="flex items-center h-full px-6 text-neutral-300"><svg width="20" height="20"></svg></a>' +
              '<a href="/auth/logout" class="flex items-center h-full px-6 text-neutral-300"><svg width="20" height="20"></svg></a>' +
            '</div>' +
          '</div>' +
        '</div>';
    }

    function subnav(active) {
        var tabs = [['', 'Console'], ['/files', 'Files'], ['/databases', 'Databases'],
                    ['/schedules', 'Schedules'], ['/users', 'Users'], ['/backups', 'Backups'],
                    ['/network', 'Network'], ['/startup', 'Startup'], ['/settings', 'Settings']];
        return '<div class="sub-nav bg-neutral-700 shadow"><div class="mx-auto w-full flex" style="max-width:1200px">' +
            tabs.map(function (t) {
                var href = '/server/' + SID + t[0];
                return '<a href="' + href + '" class="px-4 py-3 text-neutral-300' + (href === active ? ' active' : '') + '">' + t[1] + '</a>';
            }).join('') + '</div></div>';
    }

    function dashboard() {
        var cards = '';
        for (var i = 1; i <= 3; i++) {
            var id = i === 1 ? SID : 'srv' + i;
            cards += '<a href="/server/' + id + '" class="grid grid-cols-12 gap-4 p-4 rounded bg-neutral-700 mb-2 no-underline">' +
                '<div class="col-span-5"><p class="text-lg text-neutral-100">Testserver ' + i + '</p>' +
                '<p class="text-sm text-neutral-400">10.0.0.' + i + ':2503' + i + '</p></div>' +
                '<div class="col-span-7 text-neutral-300">CPU 12% · RAM 512 MiB</div></a>';
        }
        return '<div class="container mx-auto px-4 py-6" style="max-width:1200px"><h1 class="text-2xl text-neutral-100 mb-4">Server</h1>' + cards + '</div>';
    }

    function consolePage() {
        return subnav('/server/' + SID) +
        '<div class="container mx-auto px-4 py-6" style="max-width:1200px">' +
          '<div class="grid grid-cols-4 gap-4">' +
            '<div class="col-span-3">' +
              '<div id="terminal" class="rounded bg-black p-2" style="min-height:260px">' +
                '<div class="xterm"><div class="xterm-viewport"></div><div class="xterm-screen"></div></div>' +
              '</div>' +
              '<div class="mt-4 flex gap-2">' +
                '<button class="bg-neutral-600 px-4 py-2 rounded text-neutral-100">Start</button>' +
                '<button class="bg-neutral-600 px-4 py-2 rounded text-neutral-100">Restart</button>' +
                '<button class="bg-red-600 px-4 py-2 rounded text-white">Stop</button>' +
              '</div>' +
            '</div>' +
            '<div class="col-span-1">' +
              '<div class="rounded bg-neutral-700 p-3 mb-2"><div class="bg-neutral-900 border-b p-2">Status</div><p class="text-neutral-300">Offline</p></div>' +
              '<div class="rounded bg-neutral-700 p-3"><div class="bg-neutral-900 border-b p-2">Info</div><p class="text-neutral-300">Node A</p></div>' +
            '</div>' +
          '</div>' +
          '<div class="mt-6"><button class="bg-primary-500 px-4 py-2 rounded text-white">Speichern</button></div>' +
        '</div>';
    }

    function authPage() {
        return '<div class="flex items-center justify-center min-h-screen">' +
          '<div class="bg-neutral-900 rounded-lg shadow-lg p-8" style="width:420px">' +
            '<form><label class="text-neutral-300">Benutzername</label>' +
            '<input type="text" class="w-full bg-neutral-600 rounded p-2 mb-3">' +
            '<label class="text-neutral-300">Passwort</label>' +
            '<input type="password" class="w-full bg-neutral-600 rounded p-2 mb-4">' +
            '<button type="submit" class="bg-primary-500 w-full rounded p-2 text-white">Anmelden</button></form>' +
          '</div></div>';
    }

    var socket = null;

    function connect() {
        if (socket) { try { socket.close(); } catch (e) {} socket = null; }
        var proto = location.protocol === 'https:' ? 'wss' : 'ws';
        socket = new WebSocket(proto + '://' + location.host + '/api/servers/11111111-2222-3333-4444-555555555555/ws');
    }

    function render() {
        var p = location.pathname;
        var inner;
        if (/^\/auth/.test(p)) inner = authPage();
        else if (/^\/server\//.test(p)) inner = subnavAware(p);
        else inner = dashboard();

        app.innerHTML = (/^\/auth/.test(p) ? '' : nav()) + '<div class="page">' + inner + '</div>';
        if (/^\/server\//.test(p)) connect();
        else if (socket) { try { socket.close(); } catch (e) {} socket = null; }
    }

    function subnavAware(p) {
        var parts = p.split('/');
        if (parts.length > 3 && parts[3]) {
            return subnav(p) + '<div class="container mx-auto px-4 py-6" style="max-width:1200px">' +
                '<div class="rounded bg-neutral-700 p-4"><div class="bg-neutral-900 border-b p-2">' + parts[3] + '</div>' +
                '<p class="text-neutral-300">Inhalt</p></div></div>';
        }
        return consolePage();
    }

    document.addEventListener('click', function (e) {
        var a = e.target.closest ? e.target.closest('a') : null;
        if (!a) return;
        var href = a.getAttribute('href');
        if (!href || href.charAt(0) !== '/' || href === '/auth/logout') return;
        e.preventDefault();
        history.pushState({}, '', href);
        render();
    });
    window.addEventListener('popstate', render);
    render();
    window.__mockReady = true;
})();
