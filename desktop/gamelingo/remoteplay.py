"""Start a registered local PS5 through chiaki-ng's published command line."""
import ipaddress
import socket
import subprocess
import time
from pathlib import Path
import psutil

SECOND_PROFILE = "GameLingo-B"


def client_args(executable: Path, profile: str) -> list[str]:
    # An explicit empty profile selects the original registration even after
    # another profile was used. Credentials stay inside chiaki-ng.
    return [str(executable), "--profile", profile, "--opengl"]


def discovery_address(local_ip: str) -> str:
    for addresses in psutil.net_if_addrs().values():
        for addr in addresses:
            if addr.family == socket.AF_INET and addr.address == local_ip and addr.netmask:
                interface = ipaddress.IPv4Interface((local_ip, addr.netmask))
                return str(interface.network.broadcast_address)
    raise OSError("Choose the PC's Wi-Fi address in the Television tab.")


def registered_console(executable: Path, profile: str, local_ip: str):
    command = client_args(executable, profile)
    result = subprocess.run(command + ["list"], cwd=executable.parent, capture_output=True,
                            timeout=7, check=True)
    hosts = {line[5:].strip() for line in result.stdout.decode(errors="replace").splitlines()
             if line.startswith("Host:")}
    if not hosts:
        return None
    matches = {}
    with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as sock:
        sock.setsockopt(socket.SOL_SOCKET, socket.SO_BROADCAST, 1)
        sock.bind((local_ip, 0))
        sock.sendto(b"SRCH * HTTP/1.1\ndevice-discovery-protocol-version:00030010\n",
                    (discovery_address(local_ip), 9302))
        deadline = time.monotonic() + 1.2
        while time.monotonic() < deadline:
            sock.settimeout(max(.001, deadline-time.monotonic()))
            try:
                packet, (ip, _) = sock.recvfrom(4096)
            except socket.timeout:
                break
            lines = packet.decode(errors="replace").splitlines()
            if not lines or not lines[0].startswith("HTTP/1.1 200 "):
                continue
            fields = dict(line.split(":",1) for line in lines[1:] if ":" in line)
            nickname = fields.get("host-name","").strip()
            if nickname in hosts and fields.get("host-type","").strip() == "PS5":
                matches[ip] = nickname
    if len(matches) == 1:
        ip, nickname = next(iter(matches.items()))
        return nickname, ip
    return None


def launch(executable: Path, profile: str, console=None):
    args = client_args(executable, profile)
    if console:
        nickname, ip = console
        args += ["--exit-app-on-stream-exit", "stream", nickname, ip]
    return subprocess.Popen(args, cwd=executable.parent, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
