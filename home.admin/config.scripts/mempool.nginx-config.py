"""Render the optional donation proxy with the DNS configured on this node."""

from ipaddress import ip_address
from pathlib import Path
from tempfile import NamedTemporaryFile


def render(template, resolv_conf):
    servers = []
    for line in resolv_conf.splitlines():
        fields = line.split()
        if len(fields) < 2 or fields[0] != "nameserver":
            continue
        try:
            address = ip_address(fields[1])
        except ValueError:
            continue
        if "%" in str(address):
            continue
        server = str(address) if address.version == 4 else f"[{address}]"
        if server not in servers:
            servers.append(server)
    resolver = "resolver " + " ".join(servers) + ";" if servers else ""
    return template.replace("# MEMPOOL_SYSTEM_DNS", resolver)


if __name__ == "__main__":
    source = Path("/home/admin/assets/nginx/snippets/mempool.conf")
    target = Path("/etc/nginx/snippets/mempool.conf")
    try:
        dns = Path("/etc/resolv.conf").read_text(errors="replace")
    except OSError:
        dns = ""
    contents = render(source.read_text(), dns)
    with NamedTemporaryFile(mode="w", dir=target.parent, delete=False) as stage:
        path = Path(stage.name)
        try:
            stage.write(contents)
            stage.flush()
            path.chmod(0o644)
            path.replace(target)
        finally:
            path.unlink(missing_ok=True)
