"""Exercise both public API templates with real nginx (requires nginx and openssl).

Run from the repository root:
    python3 -m unittest discover -s test -p test_nginx_api_proxy.py -v
"""

import base64
import contextlib
import hashlib
import http.client
import http.server
import json
from pathlib import Path
import shutil
import socket
import ssl
import subprocess
import tempfile
import threading
import time
import unittest


ASSETS = Path(__file__).resolve().parents[1] / "home.admin/assets/nginx"


class APIHandler(http.server.BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def do_GET(self):
        if self.path.startswith("/ws?"):
            if (
                self.request_version != "HTTP/1.1"
                or self.headers.get("Upgrade", "").lower() != "websocket"
                or self.headers.get("Connection", "").lower() != "upgrade"
                or self.headers.get("Sec-WebSocket-Version") != "13"
            ):
                self.send_error(400)
                return
            key = self.headers["Sec-WebSocket-Key"]
            accept = base64.b64encode(
                hashlib.sha1(
                    (key + "258EAFA5-E914-47DA-95CA-C5AB0DC85B11").encode()
                ).digest()
            ).decode()
            self.send_response(101)
            self.send_header("Upgrade", "websocket")
            self.send_header("Connection", "Upgrade")
            self.send_header("Sec-WebSocket-Accept", accept)
            self.send_header("X-Upstream-Path", self.path)
            self.end_headers()
            self.wfile.write(b"\x81\x02ok")
            self.close_connection = True
            return

        body = json.dumps({
            "path": self.path,
            "connection": self.headers.get("Connection"),
            "upgrade": self.headers.get("Upgrade"),
            "real_ip": self.headers.get("X-Real-IP"),
            "forwarded_host": self.headers.get("X-Forwarded-Host"),
        }).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, *args):
        pass


def free_port():
    with socket.socket() as listener:
        listener.bind(("127.0.0.1", 0))
        return listener.getsockname()[1]


class NginxAPIProxyTest(unittest.TestCase):
    @contextlib.contextmanager
    def proxy(self, template):
        with tempfile.TemporaryDirectory() as directory:
            prefix = Path(directory)
            snippets = prefix / "snippets"
            shutil.copytree(ASSETS / "snippets", snippets)
            subprocess.run([
                "openssl", "req", "-x509", "-newkey", "rsa:2048", "-nodes",
                "-keyout", str(prefix / "tls.key"), "-out", str(prefix / "tls.cert"),
                "-days", "1", "-subj", "/CN=localhost",
            ], check=True, capture_output=True)
            subprocess.run([
                "openssl", "dhparam", "-dsaparam", "-out", str(prefix / "dhparam.pem"),
                "2048",
            ], check=True, capture_output=True)
            for snippet in snippets.iterdir():
                snippet.write_text(snippet.read_text().replace(
                    "/mnt/hdd/app-data/nginx/", f"{prefix}/"
                ).replace("/etc/ssl/certs/dhparam.pem", str(prefix / "dhparam.pem")))

            backend = http.server.ThreadingHTTPServer(("127.0.0.1", 0), APIHandler)
            worker = threading.Thread(target=backend.serve_forever, daemon=True)
            worker.start()
            self.addCleanup(worker.join)
            self.addCleanup(backend.server_close)
            self.addCleanup(backend.shutdown)
            http_port, https_port = free_port(), free_port()
            config = (ASSETS / "sites-available" / template).read_text()
            # Only relocate listeners, the upstream and filesystem dependencies.
            config = config.replace("listen 80 ", f"listen 127.0.0.1:{http_port} ")
            config = config.replace("listen [::]:80 ", f"listen [::1]:{http_port} ")
            config = config.replace("listen 443 ", f"listen 127.0.0.1:{https_port} ")
            config = config.replace("listen [::]:443 ", f"listen [::1]:{https_port} ")
            config = config.replace("127.0.0.1:11111", f"127.0.0.1:{backend.server_port}")
            config = config.replace("/etc/nginx/snippets/", f"{snippets}/")
            (prefix / "nginx.conf").write_text(
                "daemon off;\nmaster_process off;\npid nginx.pid;\n"
                "error_log stderr;\nevents {}\nhttp {\naccess_log off;\n"
                f"client_body_temp_path {prefix}/client_temp;\n"
                f"proxy_temp_path {prefix}/proxy_temp;\n"
                f"fastcgi_temp_path {prefix}/fastcgi_temp;\n"
                f"uwsgi_temp_path {prefix}/uwsgi_temp;\n"
                f"scgi_temp_path {prefix}/scgi_temp;\n{config}\n}}\n"
            )
            command = ["nginx", "-p", f"{prefix}/", "-c", "nginx.conf"]
            validation = subprocess.run(command + ["-t"], capture_output=True, text=True)
            self.assertEqual(validation.returncode, 0, validation.stderr)
            process = subprocess.Popen(command, stderr=subprocess.PIPE)
            try:
                for _ in range(100):
                    if process.poll() is not None:
                        self.fail(process.stderr.read().decode())
                    try:
                        with socket.create_connection(("127.0.0.1", http_port), timeout=1):
                            break
                    except OSError:
                        time.sleep(0.05)
                else:
                    self.fail("nginx did not start within five seconds")
                yield http_port, https_port
            finally:
                process.terminate()
                process.communicate(timeout=5)

    def check_proxy(self, template):
        with self.proxy(template) as (http_port, https_port):
            connections = [("http", http_port)]
            if template == "public.conf":
                connections.append(("https", https_port))
            for scheme, port in connections:
                for websocket in (False, True):
                    with self.subTest(template=template, scheme=scheme, websocket=websocket):
                        if scheme == "https":
                            connection = http.client.HTTPSConnection(
                                "127.0.0.1", port, timeout=5,
                                context=ssl._create_unverified_context(),
                            )
                        else:
                            connection = http.client.HTTPConnection("127.0.0.1", port, timeout=5)
                        with contextlib.closing(connection):
                            if websocket:
                                connection.request("GET", "/api/ws?test=1", headers={
                                    "Connection": "Upgrade", "Upgrade": "websocket",
                                    "Sec-WebSocket-Version": "13",
                                    "Sec-WebSocket-Key": "dGhlIHNhbXBsZSBub25jZQ==",
                                })
                                response = connection.getresponse()
                                self.assertEqual(response.status, 101)
                                self.assertEqual(response.getheader("Upgrade").lower(), "websocket")
                                self.assertEqual(response.getheader("Connection").lower(), "upgrade")
                                self.assertEqual(response.getheader("Sec-WebSocket-Accept"),
                                                 "s3pPLMBiTxaQ9kYGzzhZRbK+xOo=")
                                self.assertEqual(response.getheader("X-Upstream-Path"), "/ws?test=1")
                                self.assertEqual(response.fp.read(4), b"\x81\x02ok")
                                response.close()
                            else:
                                connection.request("GET", "/api/health?test=1")
                                response = connection.getresponse()
                                self.assertEqual(response.status, 200)
                                data = json.loads(response.read())
                                self.assertEqual(data["path"], "/health?test=1")
                                self.assertEqual(data["connection"].lower(), "close")
                                self.assertIsNone(data["upgrade"])
                                self.assertEqual(data["real_ip"], "127.0.0.1")
                                self.assertEqual(data["forwarded_host"], "127.0.0.1")

    def test_http_only_template(self):
        self.check_proxy("public.httponly.conf")

    def test_https_template(self):
        self.check_proxy("public.conf")


if __name__ == "__main__":
    unittest.main()
