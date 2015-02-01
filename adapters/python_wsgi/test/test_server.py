
import unittest
import os
from os import sys, path
import signal
import errno
import random
import socket
import json
import time

sys.path.append(path.abspath(path.join(path.dirname(__file__), '../lib')))
from josh import netstring
from josh.server import Server

class TestNackWorker(unittest.TestCase):

    def spawn(self, fixture):
        current_dir = os.path.dirname(__file__)
        config = os.path.abspath(os.path.join(current_dir, "./fixtures/{0}.py".format(fixture)))
        pid  = os.getpid()
        rand = int((random.random() * 10000000000))

        self.sock = "/tmp/josh.python_wsgi.{0}.{1}.sock".format(pid, rand)

        self.pid = os.fork()
        if self.pid == 0:
            # for reasons unknown to me, first argument is lost (so passing a blank string)
            os.execl(os.path.abspath(os.path.join(current_dir, "../bin/josh-adapter-python_wsgi-worker")), '', config, self.sock)
            exit(0)

        while not os.path.exists(self.sock):
            pass
        time.sleep(0.2)
        self.heartbeat = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        self.heartbeat.connect(self.sock)

    def wait(self):
        try:
            os.kill(self.pid, signal.SIGTERM)
            os.waitpid(self.pid, 0)
            if self.heartbeat:
                self.heartbeat.close()
        except Exception as e:
            if hasattr(e, 'errno') and e.errno == errno.ESRCH:
                pass
            else:
                raise

    def start(self, fixture = "echo"):
        self.spawn(fixture)
        self.assertEqual(bytes("{0}\n".format(self.pid), 'ascii'), self.heartbeat.recv(1024))

    def request(self, env = {}, body = None):
        socket_ = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        socket_.connect(self.sock)

        netstring.write(socket_, json.dumps(env))
        if body:
            netstring.write(socket_, body)
        netstring.write(socket_, "")

        status, headers, body = None, None, []

        def read_callback(data):
            nonlocal status, headers, body
            if status == None:
                status = data
            elif headers == None:
                headers = json.loads(data.decode('ascii'))
            elif len(data) > 0:
                body.append(data.decode('ascii'))
            else:
                pass

        netstring.read(socket_, read_callback)

        return [status, headers, body]

    def test_request(self):
        try:
            self.start()
            status, headers, body = self.request({}, "foo=bar")

            self.assertEqual(200, int(status))
            self.assertEqual("text/plain", headers['Content-Type'])
            self.assertEqual("foo=1\nbar=2", headers['Set-Cookie'])
            self.assertEqual(["foo=bar"], body)
        finally:
            self.wait()

    def test_multiple_requests(self):
        try:
            self.start()
            for i in range(100):
                status, headers, body = self.request({}, str(i))
                self.assertEqual(200, int(status))
                self.assertEqual([str(i)], body)
        finally:
            self.wait()

    def test_invalid_json_env(self):
        try:
            self.start()
            socket_ = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
            socket_.connect(self.sock)

            netstring.write(socket_, "")

            error = None

            def read_callback(data):
                nonlocal error
                error = json.loads(data.decode('ascii'))

            netstring.read(socket_, read_callback)

            assert(error)

            self.assertEqual("ValueError", error['name'])
            self.assertEqual("Expecting value: line 1 column 1 (char 0)", error['message'])
        finally:
            self.wait()
  
    def test_invalid_netstring(self):
        try:
            self.start()
            socket_ = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
            socket_.connect(self.sock)

            socket_.write("1:{},")
            socket_.close()

            error = None

            def read_callback(data):
                nonlocal error
                error = json.loads(data.decode('ascii'))

            NetString.read(socket_, read_callback)

            assert(error)
            self.assertEqual("Nack::Error", error['name'])
            self.assertEqual("Invalid netstring length, expected to be 1", error['message'])
        except:
            self.wait()

    def test_close_heartbeat(self):
        try:
            self.start()
            status = self.request({}, "foo=bar")[0]
            self.assertEqual(200, int(status))

            self.heartbeat.shutdown(socket.SHUT_RDWR)
            self.heartbeat.close()
            os.waitpid(self.pid, 0)
        finally:
            self.wait()

    def test_app_error(self):
        try:
            self.start("error")

            socket_ = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
            socket_.connect(self.sock)

            netstring.write(socket_, json.dumps({}))
            netstring.write(socket_, "foo=bar")
            netstring.write(socket_, "")

            error = None

            def read_callback(data):
                nonlocal error
                error = json.loads(data.decode("ascii"))

            netstring.read(socket_, read_callback)

            assert(error)
            self.assertEqual("Exception", error['name'])
            self.assertEqual("b00m", error['message'])
        finally:
            self.wait()

    def test_spawn_error(self):
        try:
            self.spawn("crash")
            data = b""
            packet = self.heartbeat.recv(1024)
            while packet:
                data += packet
                packet = self.heartbeat.recv(1024)                
            error = json.loads(data.decode('ascii'))

            assert error
            self.assertEqual("Exception", error['name'])
            self.assertEqual("b00m", error['message'])
        finally:
            self.wait()

    def test_invalid_wsgi_path(self):
        try:
            self.spawn("non-existent")
            data = b""
            packet = self.heartbeat.recv(1024)
            while packet:
                data += packet
                packet = self.heartbeat.recv(1024)                
            error = json.loads(data.decode('ascii'))
            assert error
            self.assertEqual("FileNotFoundError", error['name'])
        finally:
            self.wait()

    def test_django_app(self):
        try:
            self.spawn("django_example_app/django_example_app/wsgi")
            status, headers, body = self.request({ "REQUEST_METHOD": "GET", "HTTP_HOST": "test" })
            self.assertEqual(b"200 OK", status)
            self.assertEqual("text/html", headers['Content-Type'])
            self.assertTrue("Congratulations on your first Django-powered page." in body[0])

            status, headers, body = self.request({ "REQUEST_METHOD": "GET", "HTTP_HOST": "test", "PATH_INFO": "/admin/" })
            self.assertEqual("http://test/admin/login/?next=/admin/", headers["Location"])
        finally:
            self.wait()
