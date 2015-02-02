# encoding: utf-8

import unittest
import struct
from io import BytesIO
from os import sys, path
sys.path.append(path.abspath(path.join(path.dirname(__file__), '../lib')))
from josh import netstring

class TestNetString(unittest.TestCase):

  def test_read(self):
    buf, io = [], BytesIO(b"3:abc,1:a,1:b,5:hello,1:c,0:,")
    netstring.read(io, lambda s: buf.append(s))
    self.assertEqual([b"abc", b"a", b"b", b"hello", b"c", b""], buf)

    buf, io = [], BytesIO(bytes("1:a,5:café,3:☃,", "utf-8"))
    netstring.read(io, lambda s: buf.append(s))
    self.assertEqual([b"a", bytes("café", "utf-8"), bytes("☃", "utf-8")], buf)

    # This test is copied from from ruby_rack adapter.
    # I guess the intention is that if a packet is invalid because of
    # EOF then silently discard it and return all earlier packets?
    buf, io = [], BytesIO(b"1:a,5:abc")
    netstring.read(io, lambda s: buf.append(s))
    self.assertEqual([b"a"], buf)

    io = BytesIO(b"4:abc,1:a,")
    with self.assertRaises(netstring.NetStringError) as e:
        netstring.read(io, lambda s: s)
    self.assertEqual("Invalid netstring length, expected to be 4", str(e.exception))

    io = BytesIO(b"30")
    with self.assertRaises(netstring.NetStringError) as e:
        netstring.read(io, lambda s: s)
    self.assertEqual("Invalid netstring terminated after length", str(e.exception))

    io = BytesIO(b":")
    with self.assertRaises(netstring.NetStringError) as e:
        netstring.read(io, lambda s: s)
    self.assertEqual("Invalid netstring with leading ':'", str(e.exception))

    io = BytesIO(b"a:")
    with self.assertRaises(netstring.NetStringError) as e:
        netstring.read(io, lambda s: s)
    self.assertEqual("Unexpected character 'a' found at offset 0", str(e.exception))

    io = BytesIO(b"01:a")
    with self.assertRaises(netstring.NetStringError) as e:
        netstring.read(io, lambda s: s)
    self.assertEqual("Invalid netstring with leading 0", str(e.exception))

    io = BytesIO(b"1000000000:a")
    with self.assertRaises(netstring.NetStringError) as e:
        netstring.read(io, lambda s: s)
    self.assertEqual( "netstring is too large", str(e.exception))

  def test_resume_reading(self):
    io = BytesIO(b"3:abc,1:a,1:b,0:,5:hello,1:c,0:,2:42,")

    buf = []
    netstring.read(io, lambda s: buf.append(s) if len(s) > 0 else False)
    self.assertEqual([b"abc", b"a", b"b"], buf)

    buf = []
    netstring.read(io, lambda s: buf.append(s) if len(s) > 0 else False)
    self.assertEqual([b"hello", b"c"], buf)

    buf = []
    netstring.read(io, lambda s: buf.append(s) if len(s) > 0 else False)
    self.assertEqual([b"42"], buf)

  def test_encode(self):
      self.assertEqual(b"12:hello world!,", netstring.encode("hello world!"))
      self.assertEqual(b"12:hello world!,", netstring.encode("hello world!".encode()))
      self.assertEqual((0x31, 0x32, 0x3a, 0x68, 0x65, 0x6c, 0x6c, 0x6f,
                        0x20, 0x77, 0x6f, 0x72, 0x6c, 0x64, 0x21, 0x2c),
                       struct.unpack("16b", netstring.encode("hello world!")))
      self.assertEqual(b"3:abc,", netstring.encode("abc"))
      self.assertEqual(b"1:a,", netstring.encode("a"))
      self.assertEqual(bytes("5:café,", 'utf-8'), netstring.encode("café"))
      self.assertEqual(b"0:,", netstring.encode(""))

  def test_write(self):
    io_ = BytesIO()
    netstring.write(io_, "abc")
    self.assertEqual(b"3:abc,", io_.getvalue())
