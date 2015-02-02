
import os
import atexit
import fcntl
import json
import signal
import importlib.machinery
from io import StringIO, BytesIO
import socket
import socketserver
import select
import sys
import warnings
import errno
import traceback
import re
import types
from . import netstring, error

def is_closed(socket):
    #TODO: implement me
    return False

class ServerSocketRequestHandler(socketserver.BaseRequestHandler):
    # https://docs.python.org/3/library/socketserver.html
    # not sure what is does, never seems to be called
    def handle(self):
        self.data = self.request.recv(1024).strip()
        print("{} wrote:".format(self.client_address[0]))
        print(self.data)
        # just send back the same data, but upper-cased
        self.request.sendall(self.data.upper())

class Server:
    @classmethod
    def run(cls, *args):
        cls(*args).start()

    def __init__(self, config, options = {}):
        try:
            self.config = config
            self.file   = options["file"]
            self.ppid   = os.getppid()

            atexit.register(self.close)

            self.server = socketserver.UnixStreamServer(self.file, ServerSocketRequestHandler)
            fcntl.fcntl(self.server.socket.fileno(), fcntl.F_SETFD, fcntl.FD_CLOEXEC)

            readable, _, _ = select.select([self.server], [], [], 4)

            if readable and readable[0] == self.server:
                self.server.socket.setblocking(False)
                self.server.socket.listen(0)
                self.heartbeat, _ = self.server.get_request()
                fcntl.fcntl(self.heartbeat.fileno(), fcntl.F_SETFD, fcntl.FD_CLOEXEC)
            else:
                warnings.warn("No heartbeat connected")
                sys.exit(1)

            signal.signal(signal.SIGTERM, self.terminate)
            signal.signal(signal.SIGINT, self.terminate)
            signal.signal(signal.SIGQUIT, self.close)

            self.app = self.load_config()
        except Exception as e:
            self.handle_exception(e)

    # given path to wsgi.py (in self.config), load the application
    def load_config(self):
        # I'm sure there is a better way, I just don't know it yet
        dirname = os.path.dirname(self.config)
        if os.path.exists(os.path.join(dirname, "settings.py")):
            # for Django, we need "app_name.settings" in path to be
            # able to load wsgi.py
            wsgi_name = os.path.basename(re.sub(r'\.py$', '', self.config))
            dirname = os.path.dirname(self.config)
            app_name = os.path.basename(dirname)
            parent_dir = os.path.dirname(dirname)

            sys.path.append(parent_dir)
            app = __import__(app_name, globals(), locals(), ["settings"], 0)
            sys.path.remove(parent_dir)
            
        return importlib.machinery.SourceFileLoader("app", self.config).load_module().application

    def terminate(*args):
        sys.exit(0)

    def close(self, *args):
        if hasattr(self, 'server'):
            self.server.socket.close()
        if hasattr(self, 'heartbeat'):
            self.heartbeat.close()
        if hasattr(self, 'file') and os.path.exists(self.file):
            os.unlink(self.file)

    # http://stackoverflow.com/a/16745561
    def heartbeat_closed(self):
        try:
            self.heartbeat.setblocking(False)
            msg = self.heartbeat.recv(1024)
            return True
        except socket.error as e:
            if(e.errno == errno.EAGAIN or e.errno == errno.EWOULDBLOCK):
                try:
                    # somehow if you read again without any issues, it
                    # means the socket is closed :-/
                    self.heartbeat.recv(1024)
                    return True
                except:
                    pass
        return False

    def start(self):
        try:
            self.heartbeat.sendall(bytes("{0}\n".format(os.getpid()), 'ascii'))
            
            clients = []
            buffers = {}
        
            while(True):
                listeners = clients + [self.heartbeat]
                if not is_closed(self.server):
                    listeners.append(self.server)
                
                readable, writable = None, None
                try:
                    readable, writable, _ = select.select(listeners, [], [], 60)
                except select.error:
                    pass
              
                if (is_closed(self.server) or self.heartbeat_closed()) and len(clients) == 0:
                    return self.close()

                if self.ppid != os.getppid():
                    return self.close()

                if not readable:
                    next

                for sock in readable:
                    if sock == self.server:
                        self.server.socket.setblocking(False)
                        client, _ = self.server.get_request()
                        fcntl.fcntl(client, fcntl.F_SETFD, fcntl.FD_CLOEXEC)
                        clients.append(client)
                    else:
                        if not sock in buffers:
                            buffers[sock] = bytes('', 'ascii')
                        client = sock
                        try:
                            client.setblocking(False)
                            data = client.recv(1024)
                            while data:
                                buffers[client] += data
                                data = client.recv(1024)
                        except BlockingIOError:
                            self.handle(sock, BytesIO(buffers[sock]))
                            del buffers[client]
                            clients.remove(client)
                            client.close()
            return None
        except SystemExit:
            pass
        except Exception as e:
            if hasattr(e, 'errno') and e.errno == errno.EINTR:
                pass
            else:
                self.handle_exception(e)

    def handle(self, sock, buf):
        try:
            status  = 500
            headers = { 'Content-Type' : 'text/html' }
            body    = ["Internal Server Error"]

            environ, input_ = None, StringIO()
        
            def read_callback(data):
                nonlocal environ
                data = data.decode('ascii')
                if environ == None:
                    environ = json.loads(data)
                elif len(data) > 0:
                    input_.write(data)
                else:
                    return

            netstring.read(buf, read_callback)
            sock.shutdown(socket.SHUT_RD)
            input_.seek(0, 0) #rewind

            if environ.get("HTTPS") in ["yes", "on", "1"]:
                url_scheme = "https"
            else:
                url_scheme = "http"

                environ.update({
                    "wsgi.version" : (1, 0),
                    "wsgi.input" : input_,
                    "wsgi.errors" : sys.stderr,
                    "wsgi.multithread" : False,
                    "wsgi.multiprocess" : True,
                    "wsgi.run_once" : False,
                    "wsgi.url_scheme" : url_scheme,
                })
                
                status, headers = None, None
                def start_response(status_, headers_):
                    nonlocal status, headers
                    status = status_
                    headers = headers_
                body = self.app(environ, start_response)

                netstring.write(sock, str(status))

                def transform_headers(headers):
                    h = {}
                    for k, v in headers:
                        h[k] = v
                    return h
                netstring.write(sock, json.dumps(transform_headers(headers)))

                for part in body:
                    if len(part) > 0:
                        netstring.write(sock, part)
                netstring.write(sock, "")

        except Exception as e:
            error = json.dumps({
                'name'    : type(e).__name__,
                'message' : str(e),
                'stack'   : traceback.format_exc()
            })
            netstring.write(sock, error)
        finally:
            sock.shutdown(socket.SHUT_WR)

    def handle_exception(self, e):
        if hasattr(self, 'heartbeat') and not self.heartbeat_closed():
            error = json.dumps({
                'name'    : type(e).__name__,
                'message' : str(e),
                'stack'   : traceback.format_exc()
            })
            self.heartbeat.sendall(bytes("{}\n".format(error), 'ascii'))
            self.heartbeat.close()
            sys.exit(1)
        else:
            raise e
