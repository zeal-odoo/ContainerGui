import Foundation

enum OdooDatabaseGuest {
    // Fixed helper: only endpoint fields leave the guest, never the full configuration.
    static let script = #"""
import os, sys, stat, json, hashlib, re, uuid, fcntl, ipaddress

def reject(reason):
    print(json.dumps({'error': reason}))
    sys.exit(2)

def read_file(directory, name):
    fd = os.open(name, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK, dir_fd=directory)
    try:
        info = os.fstat(fd)
        if not stat.S_ISREG(info.st_mode) or info.st_nlink != 1 or info.st_size > 131072:
            reject('unavailable')
        data = b''
        while True:
            block = os.read(fd, 4096)
            if not block: break
            data += block
            if len(data) > 131072: reject('unavailable')
        return data, info
    finally:
        os.close(fd)

def parse(data):
    text = data.decode('utf-8')
    if '\x00' in text: reject('invalid')
    lines = text.split('\n')
    options, found = False, False
    end = len(lines) - (1 if lines[-1] == '' else 0)
    indices, values = {}, {}
    for index, line in enumerate(lines):
        stripped = line.strip()
        if not stripped or stripped.startswith(('#', ';')): continue
        if stripped.startswith('['):
            if options: end = index
            options = stripped.lower() == '[options]'
            if options:
                if found: reject('invalid')
                found = True
            continue
        if not options: continue
        if '=' not in line: reject('invalid')
        key, value = line.split('=', 1)
        key = key.strip().lower()
        if not key or key in indices: reject('invalid')
        indices[key], values[key] = index, value.strip()
    if not found: reject('invalid')
    host, port = values.get('db_host', ''), int(values.get('db_port', '5432'))
    if host == 'False': host = ''
    if (host and not valid_host(host)) or not 1 <= port <= 65535: reject('invalid')
    return lines, indices, end, {'host': host, 'port': port, 'revision': hashlib.sha256(data).hexdigest()}

def valid_host(host):
    if not 1 <= len(host) <= 255: return False
    if ':' in host or re.fullmatch(r'[0-9.]+', host):
        try: ipaddress.ip_address(host); return True
        except ValueError: return False
    return all(re.fullmatch(r'[A-Za-z0-9](?:[A-Za-z0-9_-]*[A-Za-z0-9])?', label) and len(label) <= 63 for label in host.split('.'))

def create(directory, name, data, mode, owner=None):
    fd = os.open(name, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o600, dir_fd=directory)
    try:
        offset = 0
        while offset < len(data):
            count = os.write(fd, data[offset:])
            if count <= 0: reject('unavailable')
            offset += count
        if owner: os.fchown(fd, *owner)
        os.fchmod(fd, mode)
        os.fsync(fd)
    finally:
        os.close(fd)

try:
    mode, path = sys.argv[1:3]
    if os.environ.get('ODOO_RC', path) != path: reject('unsupportedLocation')
    parent, name = os.path.split(path)
    directory = os.open(parent, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW)
    try:
        data, info = read_file(directory, name)
        lines, indices, end, endpoint = parse(data)
        if mode == 'write':
            host, port, revision = sys.argv[3:6]
            port = int(port)
            if not valid_host(host) or not 1 <= port <= 65535: reject('invalid')
            if endpoint['revision'] != revision: reject('stale')
            lock = os.open(name, os.O_RDONLY | os.O_NOFOLLOW, dir_fd=directory)
            try:
                fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
                additions = []
                for key, value in [('db_host', host), ('db_port', str(port))]:
                    if key in indices:
                        index = indices[key]
                        prefix = re.match(r'^(.*?=[ \t]*)', lines[index]).group(1)
                        lines[index] = prefix + value + ('\r' if lines[index].endswith('\r') else '')
                    else: additions.append(key + ' = ' + value + ('\r' if b'\r\n' in data else ''))
                lines[end:end] = additions
                updated = '\n'.join(lines).encode('utf-8')
                if len(updated) > 131072: reject('invalid')
                token = str(uuid.uuid4())
                backup, temporary = '.' + name + '.container-gui-' + token + '.bak', '.' + name + '.container-gui-' + token + '.tmp'
                create(directory, backup, data, 0o600)
                try:
                    create(directory, temporary, updated, stat.S_IMODE(info.st_mode), (info.st_uid, info.st_gid))
                    latest, current = read_file(directory, name)
                    if latest != data or (current.st_ino, current.st_dev) != (info.st_ino, info.st_dev): reject('stale')
                    os.rename(temporary, name, src_dir_fd=directory, dst_dir_fd=directory)
                    os.fsync(directory)
                finally:
                    try: os.unlink(temporary, dir_fd=directory)
                    except FileNotFoundError: pass
                endpoint = parse(read_file(directory, name)[0])[3]
                if endpoint['host'] != host or endpoint['port'] != port: reject('invalid')
            finally:
                os.close(lock)
        elif mode != 'read': reject('invalid')
        print(json.dumps(endpoint))
    finally:
        os.close(directory)
except Exception:
    reject('unavailable')
"""#
}
