import base64
import hashlib
import json
import pathlib
import os
import socket
import struct
import subprocess
import tempfile
import time

root = pathlib.Path(__file__).resolve().parents[1]
binary = pathlib.Path(os.environ.get('KANDO_HAPTICS_TEST_BINARY', str(root / 'Kando Haptics.app/Contents/MacOS/KandoHaptics')))

def exact(connection, length):
    result = b''
    while len(result) < length:
        chunk = connection.recv(length - len(result))
        if not chunk:
            raise RuntimeError('Unexpected disconnect')
        result += chunk
    return result

def read_frame(connection):
    header = exact(connection, 2)
    length = header[1] & 127
    if length == 126:
        length = struct.unpack('!H', exact(connection, 2))[0]
    elif length == 127:
        length = struct.unpack('!Q', exact(connection, 8))[0]
    mask = exact(connection, 4) if header[1] & 128 else None
    payload = exact(connection, length)
    if mask:
        payload = bytes(value ^ mask[i % 4] for i, value in enumerate(payload))
    return payload

def send_event(connection, interaction, path):
    payload = json.dumps({'type': 'menu-interaction', 'interaction': interaction, 'path': path}).encode()
    assert len(payload) < 126
    connection.sendall(bytes([0x81, len(payload)]) + payload)

with tempfile.TemporaryDirectory(prefix='kando-haptics-test-') as temp:
    info = pathlib.Path(temp) / 'ipc-info.json'
    server = socket.socket()
    server.bind(('127.0.0.1', 0))
    server.listen()
    server.settimeout(12)
    # Start without connection info, then create it to verify automatic discovery.
    process = subprocess.Popen([str(binary), '--diagnostics-only', '--ipc-info', str(info)],
                               stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    try:
        time.sleep(1)
        info.write_text(json.dumps({'port': server.getsockname()[1], 'apiVersion': 2}))
        for cycle in range(2):
            connection, _ = server.accept()
            connection.settimeout(5)
            request = b''
            while b'\r\n\r\n' not in request:
                request += connection.recv(4096)
            key = next(line.split(b':', 1)[1].strip() for line in request.split(b'\r\n')
                       if line.lower().startswith(b'sec-websocket-key:'))
            accept = base64.b64encode(hashlib.sha1(key + b'258EAFA5-E914-47DA-95CA-C5AB0DC85B11').digest())
            connection.sendall(b'HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Accept: ' + accept + b'\r\n\r\n')
            assert json.loads(read_frame(connection)) == {'type': 'start-observing'}
            events = [('openMenu', []), ('hoverButton', [0]), ('hoverButton', [0]),
                      ('hoverSubmenu', [1]), ('selectButton', [1]), ('closeMenu', [])]
            for event, path in events:
                send_event(connection, event, path)
                time.sleep(0.08)
            connection.sendall(b'\x88\x02\x03\xe8')
            connection.close()
        time.sleep(0.2)
    finally:
        process.terminate()
        out, err = process.communicate(timeout=5)
        server.close()
    assert out.count('FEEDBACK hover') == 4, (out, err)
    assert out.count('FEEDBACK selection') == 2, (out, err)
    assert out.count('STATUS Kandoに接続済み') == 2, (out, err)
    assert '接続情報待ち' in out, (out, err)
    print(out)
    print('PASS: WebSocket subscription, event routing, duplicate suppression, delayed discovery, reconnect')
