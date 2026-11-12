import asyncio
import json
import ssl
import time
import pytest
from websockets.asyncio.client import connect
from websockets.exceptions import ConnectionClosed
from gamelingo.network import Hub, envelope, local_address


def test_address():
    assert local_address("192.168.3.70");assert not local_address("0.0.0.0");assert not local_address("8.8.8.8")

def test_pair_reconnect_expiry_and_unauthorized(tmp_path):
    hub=Hub(tmp_path,"127.0.0.1",lambda *_:None,port=0)
    hub.thread.start();assert hub.ready.wait(8);assert not hub.error
    async def check():
        context=ssl.SSLContext(ssl.PROTOCOL_TLS_CLIENT)
        context.check_hostname=False
        from cryptography import x509
        from cryptography.hazmat.primitives.serialization import Encoding
        from gamelingo.storage import unprotect
        cert=json.loads(unprotect((tmp_path/"identity.bin").read_bytes()))["cert"]
        context.load_verify_locations(cadata=cert)
        url=f"wss://127.0.0.1:{hub.port}"
        async def opened():return await connect(url,ssl=context,proxy=None)
        ws=await opened();await ws.send(json.dumps(envelope("pair",pin="bad")))
        with pytest.raises(ConnectionClosed):await ws.recv()
        ws=await opened();await ws.send(json.dumps(envelope("pair",pin=hub.pin)))
        token=json.loads(await ws.recv())["token"]
        assert json.loads(await ws.recv())["type"]=="connection_status"
        hub.publish(envelope("subtitle_show",translated="افتح الباب",expires_at=int(time.time()*1000)+8000))
        msg=json.loads(await ws.recv());assert msg["seq"]==1 and msg["translated"]=="افتح الباب"
        await ws.close();await asyncio.sleep(.4)
        ws=await opened();await ws.send(json.dumps(envelope("hello",token=token)))
        assert json.loads(await ws.recv())["type"]=="connection_status"
        await ws.send(json.dumps(envelope("heartbeat")))
        assert json.loads(await ws.recv())["type"]=="heartbeat"
        await ws.send("{}")
        with pytest.raises(ConnectionClosed):await ws.recv()
    try:asyncio.run(check())
    finally:hub.stop()

