
import socket
from io import BytesIO
from . import error

class NetStringError(error.Error):
    pass

def ns_length(io):
    i = 0
    slength = ''
    terminated_with_colon = False
    byte = _read(io, 1)
    if not byte:
        return None
    while byte:
        char = byte.decode('ascii')
        if i == 0:
            if char == '0':
                nb = _read(io, 1).decode('ascii')
                if nb == ':':
                    return 0
                elif nb.isdigit():
                    raise NetStringError("Invalid netstring with leading 0")
                else:
                    raise NetStringError("Unexpected character '{0}' found at offset {1}".format(char, i))
            elif char == ':':
                raise NetStringError("Invalid netstring with leading ':'")
        elif i >= 10:
            raise NetStringError("netstring is too large")
        
        if char.isdigit():
            slength += char
        elif char == ':':
            terminated_with_colon = True
            break
        else:
            raise NetStringError("Unexpected character '{0}' found at offset {1}".format(char, i))
        byte = _read(io, 1)
        i += 1

    if not terminated_with_colon:
        raise NetStringError("Invalid netstring terminated after length")

    return int(slength)

# can differentiate between io-stream and socket-stream
def _read(io, size = 1):
    if isinstance(io, socket.socket):
        byte = io.recv(size)
    else:
        byte = io.read(size)
    return byte

# differs slightly from Ruby adapater, as peek() isn't available on both socket and IO
# UPDATE: You can peek on sockets, see http://linux.die.net/man/2/recv
def read(io, callback):
    buf = ""
    while True:
        length = ns_length(io)
        if None == length:
            return None
        buf = _read(io, length)
        c = _read(io, 1)
        if not c:
            # b"1:a,5:abc" should be valid
            # see tests for more info
            return
        if c != b",":
            raise NetStringError("Invalid netstring length, expected to be {0}".format(length))
        else:
            if callback(buf) == False:
                return

        buf = ""

def encode(bytes_):
      io_ = BytesIO()
      write(io_, bytes_)
      return io_.getvalue()

def write(io, bytes_):
    if not isinstance(bytes_, (bytes, bytearray)):
        # assume utf-8
        bytes_ = bytes(bytes_, "utf-8")
    payload = bytes(str(len(bytes_)), 'ascii') + b":" + bytes_ + b","
    if isinstance(io, socket.socket):
        io.sendall(payload)
    else:
        io.write(payload)
        io.flush()
