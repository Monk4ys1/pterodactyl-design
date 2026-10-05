'use strict';

const fs = require('fs');
const path = require('path');

function inside(base, file) {
    return file === base || file.indexOf(base + path.sep) === 0;
}

function safeFile(root, rel) {
    if (typeof rel !== 'string' || rel.indexOf('\0') !== -1 || rel.indexOf('\\') !== -1) return null;
    var base = path.resolve(root);
    var file = path.resolve(base, '.' + path.sep + rel);
    if (!inside(base, file)) return null;
    try {
        var real = fs.realpathSync(file);
        if (!inside(base, real)) return null;
        return real;
    } catch (e) {
        return file;
    }
}

module.exports = { safeFile };
