# Reverted changed from https://github.com/josh/nack/commit/4c9c1c85625a9d428be6c67a28c539b8132d4ca0 to make it work with connect 1.x
http    = require 'http'

{createServer} = require '..'

exports.testProxyRequest = (test) ->
  test.expect 2

  server = createServer __dirname + "/fixtures/hello.ru"

  server.on 'close', ->
    test.ok true
    test.done()

  server.listen 0
  server.on 'listening', ->
    req = http.request host: '127.0.0.1', port: server.address().port, (res) ->
      test.same 200, res.statusCode
      server.close()
    req.end()

exports.testProxyRequestWithClientException = (test) ->
  test.expect 3

  server = createServer __dirname + "/fixtures/error.ru"
  server.use (err, req, res, next) ->
   test.ok err
   res.writeHead 500, 'Content-Type': 'text/plain'
   res.end()
  
  server.on 'close', ->
    test.ok true
    test.done()

  server.listen 0
  server.on 'listening', ->
    req = http.request host: '127.0.0.1', port: server.address().port, (res) ->
      test.same 500, res.statusCode
      server.close()
    req.end()

exports.testProxyRequestWithErrorCreatingProcess = (test) ->
  test.expect 3

  server = createServer __dirname + "/fixtures/crash.ru"

  server.use (err, req, res, next) ->
    test.ok err
    res.writeHead 500, 'Content-Type': 'text/plain'
    res.end()

  server.on 'close', ->
    test.ok true
    test.done()

  server.listen 0
  server.on 'listening', ->
    req = http.request host: '127.0.0.1', port: server.address().port, (res) ->
      test.same 500, res.statusCode
      server.close()
    req.end()

exports.testProxyCookies = (test) ->
  test.expect 2

  server = createServer __dirname + "/fixtures/echo.ru"

  server.on 'close', ->
    test.ok true
    test.done()

  server.listen 0
  server.on 'listening', ->
    req = http.request host: '127.0.0.1', port: server.address().port, (res) ->
      test.same 200, res.statusCode
      server.close()
    req.end()

exports.testCloseServer = (test) ->
  test.expect 2

  server = createServer __dirname + "/fixtures/hello.ru"

  server.on 'close', ->
    test.ok true
    test.done()

  server.listen 0
  server.on 'listening', ->
    test.ok true
    server.close()

exports.testCloseUnstartedServer = (test) ->
  test.expect 1

  server = createServer __dirname + "/fixtures/hello.ru"

  test.throws ->
    server.close()

  test.done()
