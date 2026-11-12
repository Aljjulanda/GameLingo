"""A private-address TLS WebSocket listener; one paired TV, no remote control API."""
import asyncio
import datetime as dt
import hashlib
import ipaddress
import json
import secrets
import ssl
import threading
import time
from pathlib import Path
from cryptography import x509
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import ec
from cryptography.x509.oid import NameOID
from websockets.asyncio.server import serve
from websockets.exceptions import ConnectionClosed
from .storage import atomic_write, protect, unprotect

PORT = 38443
ALLOWED = [ipaddress.ip_network(x) for x in ("10.0.0.0/8", "172.16.0.0/12", "192.168.0.0/16", "127.0.0.0/8")]


def local_address(ip):
    try:
        addr = ipaddress.IPv4Address(ip)
        return any(addr in subnet for subnet in ALLOWED)
    except ValueError:
        return False


def envelope(kind, **fields):
    return dict(v=1, type=kind, **fields)


def identity(folder: Path):
    folder.mkdir(parents=True, exist_ok=True)
    path = folder / "identity.bin"
    if path.exists():
        state = json.loads(unprotect(path.read_bytes()))
        key = serialization.load_pem_private_key(state['key'].encode(), password=None)
        cert = x509.load_pem_x509_certificate(state['cert'].encode())
    else:
        key = ec.generate_private_key(ec.SECP256R1())
        name = x509.Name([x509.NameAttribute(NameOID.COMMON_NAME, "GameLingo Desktop")])
        now = dt.datetime.now(dt.timezone.utc)
        cert = (x509.CertificateBuilder().subject_name(name).issuer_name(name).public_key(key.public_key())
                .serial_number(x509.random_serial_number()).not_valid_before(now-dt.timedelta(days=1))
                .not_valid_after(now+dt.timedelta(days=3650)).sign(key, hashes.SHA256()))
        pem = key.private_bytes(serialization.Encoding.PEM, serialization.PrivateFormat.PKCS8, serialization.NoEncryption())
        atomic_write(path, protect(json.dumps(dict(key=pem.decode(), cert=cert.public_bytes(serialization.Encoding.PEM).decode())).encode()))
    # OpenSSL takes filenames. Only an encrypted private key is written here.
    import tempfile
    password = secrets.token_urlsafe(32).encode()
    with tempfile.TemporaryDirectory(dir=folder) as tmp:
        pem_path = Path(tmp) / "tls.pem"
        pem_path.write_bytes(cert.public_bytes(serialization.Encoding.PEM) + key.private_bytes(
            serialization.Encoding.PEM, serialization.PrivateFormat.PKCS8, serialization.BestAvailableEncryption(password)))
        context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
        context.minimum_version = ssl.TLSVersion.TLSv1_2
        context.load_cert_chain(str(pem_path), password=password)
    return context, cert.fingerprint(hashes.SHA256()).hex()


class Hub:
    def __init__(self, folder, address, notice, port=PORT):
        if not local_address(address):
            raise ValueError("Choose the computer's LAN IPv4 address")
        self.folder, self.address, self.port, self.notice = folder, address, port, notice
        self.context, self.fingerprint = identity(folder)
        self.pin = f"{secrets.randbelow(1_000_000):06d}"
        self.deadline = time.monotonic() + 300
        self.failures = 0
        self.session = secrets.token_hex(12)
        self.counter = 0
        self.queue = None
        self.loop = None
        self.ready = threading.Event()
        self.stopping = threading.Event()
        self.error = None
        self.thread = threading.Thread(target=self._run, daemon=True)
        self.client = None
        self.last = None
        self.display_settings = None

    def _run(self):
        try:
            asyncio.run(self._serve())
        except Exception as err:
            self.error = str(err)
            self.notice("error", self.error)
        finally:
            self.ready.set()

    async def _serve(self):
        self.loop = asyncio.get_running_loop()
        self.queue = asyncio.Queue(maxsize=8)
        async with serve(self._client, self.address, self.port, ssl=self.context, compression=None,
                         max_size=16384, max_queue=4, open_timeout=5, ping_interval=6, ping_timeout=8, close_timeout=2) as server:
            self.port = server.sockets[0].getsockname()[1]
            self.ready.set()
            self.notice("listening", self.address)
            while not self.stopping.is_set():
                try:
                    item = await asyncio.wait_for(self.queue.get(), .4)
                except asyncio.TimeoutError:
                    continue
                self.counter += 1
                item.update(seq=self.counter, session=self.session)
                self.last = item
                if self.client:
                    try:
                        await asyncio.wait_for(self.client.send(json.dumps(item, ensure_ascii=False)), 1)
                    except (ConnectionClosed, TimeoutError):
                        await self.client.close()
            if self.client:
                await self.client.close()

    async def _client(self, ws):
        try:
            if self.client is not None or not local_address(ws.remote_address[0]):
                await ws.close(1008); return
            msg = json.loads(await asyncio.wait_for(ws.recv(), 8))
            if not isinstance(msg, dict) or msg.get("v") != 1:
                await ws.close(1002); return
            path = self.folder / "paired.sha256"
            if msg.get("type") == "pair":
                if (self.failures >= 5 or time.monotonic() >= self.deadline or not self.pin
                        or not secrets.compare_digest(str(msg.get("pin", "")), self.pin)):
                    self.failures += 1
                    await ws.close(1008); return
                token = secrets.token_urlsafe(32)
                self.pin = ""
                atomic_write(path, hashlib.sha256(token.encode()).hexdigest().encode())
                await ws.send(json.dumps(envelope("paired", token=token)))
            elif (msg.get("type") != "hello" or not path.exists()
                  or not secrets.compare_digest(hashlib.sha256(str(msg.get("token", "")).encode()).hexdigest(), path.read_text())):
                await ws.close(1008); return
            if self.client is not None:
                await ws.close(1008); return
            self.client = ws
            await ws.send(json.dumps(envelope("connection_status", session=self.session, state="connected", time_ms=int(time.time()*1000))))
            if self.display_settings:
                await self._control(envelope("settings_sync",settings=self.display_settings))
            self.notice("connected", ws.remote_address[0])
            if self.last and self.last.get("expires_at", 0) > int(time.time()*1000):
                await ws.send(json.dumps(self.last, ensure_ascii=False))
            async for raw in ws:
                m = json.loads(raw)
                if not isinstance(m, dict) or m.get("v") != 1 or m.get("type") not in ("heartbeat","settings_ack"):
                    await ws.close(1002); return
                if m["type"]=="settings_ack":
                    self.notice("settings_ack",{k:m.get(k) for k in ("revision","width_px","height_px","anchor_x","anchor_y")})
                else:
                    await ws.send(json.dumps(envelope("heartbeat", time_ms=int(time.time()*1000))))
        except (ConnectionClosed, TimeoutError, ValueError, TypeError):
            await ws.close(1002)
        finally:
            if self.client is ws:
                self.client = None; self.notice("disconnected", "")

    def publish(self, message):
        def offer():
            if self.queue.full():
                self.queue.get_nowait()
            self.queue.put_nowait(dict(message))
        if self.ready.is_set() and self.loop and self.loop.is_running() and not self.stopping.is_set():
            self.loop.call_soon_threadsafe(offer)

    async def _control(self, message):
        if not self.client:
            return
        self.counter += 1
        message.update(seq=self.counter, session=self.session)
        try:
            await asyncio.wait_for(self.client.send(json.dumps(message,ensure_ascii=False)),1)
        except (ConnectionClosed,TimeoutError):
            await self.client.close()

    def configure(self, values, kind="settings_sync"):
        self.display_settings=dict(values)
        if self.loop and self.loop.is_running():
            asyncio.run_coroutine_threadsafe(self._control(envelope(kind,settings=values)),self.loop)

    def stop(self):
        self.stopping.set()
        if self.thread.is_alive():
            self.thread.join(6)

