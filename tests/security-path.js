'use strict';

const assert = require('assert');
const fs = require('fs');
const os = require('os');
const path = require('path');
const { safeFile } = require('./safe-path');

const root = fs.mkdtempSync(path.join(os.tmpdir(), 'nebula-safe-'));
fs.writeFileSync(path.join(root, 'index.html'), 'ok');

assert.strictEqual(path.basename(safeFile(root, 'index.html')), 'index.html');
assert.strictEqual(safeFile(root, '../etc/passwd'), null);
assert.strictEqual(safeFile(root, '..\\..\\etc\\passwd'), null);
var abs = safeFile(root, '/etc/passwd');
assert.notStrictEqual(abs, '/etc/passwd');
assert.ok(abs === null || abs.indexOf(path.resolve(root) + path.sep) === 0);
assert.strictEqual(safeFile(root, 'foo/../../etc/passwd'), null);
assert.strictEqual(safeFile(root, 'ok\0.html'), null);

const nested = safeFile(root, 'sub/../index.html');
assert.ok(nested && nested.startsWith(path.resolve(root) + path.sep));

const outside = path.join(os.tmpdir(), 'nebula-outside-' + process.pid);
fs.writeFileSync(outside, 'secret');
fs.symlinkSync(outside, path.join(root, 'leak'));
assert.strictEqual(safeFile(root, 'leak'), null);
fs.unlinkSync(outside);

fs.rmSync(root, { recursive: true, force: true });
console.log('path ok');

const vm = require('vm');
const boot = fs.readFileSync(path.join(__dirname, '..', 'theme', 'js', '00-boot.js'), 'utf8')
    .replace('__PTD_VERSION__', 'test');
const html = {
    style: { setProperty() {}, removeProperty() {} },
    setAttribute() {}
};
const sandbox = {
    window: null,
    document: { documentElement: html },
    localStorage: { getItem() { return null; }, setItem() {} },
    matchMedia() { return { matches: false, addEventListener() {} }; },
    WebSocket: function WebSocket() {},
    fetch: function fetch() { return Promise.resolve({ clone() { return this; }, json() { return Promise.resolve({}); } }); },
    console,
    Date,
    JSON,
    Object,
    Array,
    String,
    Number,
    Math,
    RegExp,
    Promise,
    setTimeout,
    clearTimeout
};
sandbox.window = sandbox;
sandbox.globalThis = sandbox;
vm.createContext(sandbox);
vm.runInContext(boot, sandbox);
const PTD = sandbox.PTD;
assert.ok(PTD && typeof PTD.merge === 'function');
const imported = PTD.merge(PTD.defaults, JSON.parse(
    '{"preset":"ocean","compact":"yes","__proto__":{"admin":true},"constructor":{"admin":true},"prototype":{"admin":true},' +
    '"snippets":{"srv-1":["stop",1,"say hi"],"__proto__":["pwn"],"constructor":["x"]},' +
    '"tags":{"srv-1":{"color":"#112233","label":"AB"},"prototype":{"color":"#000000"}},' +
    '"favorites":["s1",{"pwn":true},4],"unknown":"drop-me"}'
));
assert.strictEqual(imported.preset, 'ocean');
assert.strictEqual(imported.compact, false);
assert.strictEqual(JSON.stringify(imported.snippets['srv-1']), JSON.stringify(['stop', 'say hi']));
assert.strictEqual(Object.prototype.hasOwnProperty.call(imported.snippets, '__proto__'), false);
assert.strictEqual(Object.prototype.hasOwnProperty.call(imported.snippets, 'constructor'), false);
assert.strictEqual(imported.tags['srv-1'].color, '#112233');
assert.strictEqual(imported.tags['srv-1'].label, 'AB');
assert.strictEqual(Object.prototype.hasOwnProperty.call(imported.tags, 'prototype'), false);
assert.strictEqual(JSON.stringify(imported.favorites), JSON.stringify(['s1', 4]));
assert.strictEqual(imported.unknown, undefined);
assert.strictEqual({}.admin, undefined);
console.log('import ok');
