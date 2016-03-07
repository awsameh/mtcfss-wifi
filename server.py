#!/usr/bin/python3
from http.server import SimpleHTTPRequestHandler, HTTPServer
import sys

"""Basic HTTP server with wpad.dat metadata support
"""

port = 8080
if len(sys.argv) == 2:
    try:
        port = int(sys.argv[1])
    except:
        pass
server_address = ("", port)
SimpleHTTPRequestHandler.protocol_version = "HTTP/1.0"
SimpleHTTPRequestHandler.extensions_map.update({
    '.dat': 'application/x-ns-proxy-autoconfig',
})
httpd = HTTPServer(server_address, SimpleHTTPRequestHandler)
sa = httpd.socket.getsockname()
print("Serving HTTP on", sa[0], "port", sa[1], "...")
try:
    httpd.serve_forever()
except KeyboardInterrupt:
    print("\nKeyboard interrupt received, exiting.")
    httpd.server_close()
    sys.exit(0)
