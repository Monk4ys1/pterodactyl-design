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
