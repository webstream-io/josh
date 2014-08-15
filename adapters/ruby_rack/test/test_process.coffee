async = require 'async'
fs    = require 'fs'
http  = require 'http'

{createProcess} = require '..'

config = __dirname + "/fixtures/hello.ru"

fileExist = (path) ->
  try
    fs.statSync path
  catch exception
    false

exports.testCreateProcess = (test) ->
  test.expect 10

  sockPath = null

  process = createProcess config

  process.on 'spawning', ->
    test.ok true

  process.on 'spawn', ->
    test.ok sockPath = process.sockPath

    test.ok process.child
    test.ok process.stdout
    test.ok process.stderr

  process.once 'ready', ->
    test.ok true

    process.quit()
    process.on 'exit', ->
      test.ok !process.sockPath
      test.ok !fileExist(sockPath)

      test.ok !process.child

      test.done()

  process.spawn (err) ->
    test.ifError err

exports.testCreateConnection = (test) ->
  test.expect 7

  process = createProcess config

  process.once 'ready', ->
    test.ok true

  process.on 'exit', ->
    test.ok true
    test.done()

  process.createConnection (err, client) ->
    test.ifError err
    test.ok client

    client.on 'error', (err) ->
      test.ifError err

    request = client.request 'GET', '/foo', {}
    request.end()

    request.on 'response', (response) ->
      test.ok response
      test.same 200, response.statusCode

      body = ""
      response.on 'data', (chunk) ->
        body += chunk

      response.on 'end', ->
        test.same "Hello World\n", body

        process.quit()

exports.testCreateMultipleConnections = (test) ->
  test.expect 18

  process = createProcess config

  process.once 'ready', ->
    test.ok true

  process.on 'exit', ->
    test.ok true
    test.done()

  count = 4
  quit = ->
    count--
    if count is 0
      process.quit()

  openConnections = 0

  connect = (path) ->
    process.createConnection (err, client) ->
      test.ifError err

      openConnections++
      client.on 'end', -> openConnections--
      test.same 1, openConnections

      test.ok client
      request = client.request 'GET', path, {}
      request.end()

      request.on 'response', (response) ->
        test.ok response
        response.on 'end', -> quit()

  connect '/foo'
  connect '/bar'
  connect '/baz'
  connect '/biz'

exports.testCreateConnectionWithRunOnce = (test) ->
  test.expect 9

  process = createProcess "#{__dirname}/fixtures/once.ru", runOnce: true

  createRequest = (callback) ->
    process.createConnection (err, client) ->
      test.ifError err

      client.on 'error', (err) ->
        test.ifError err

      client.once 'close', callback

      request = client.request 'GET', '/foo', {}, 'rack.run_once': true
      request.end()

      request.on 'response', (response) ->
        test.same 200, response.statusCode

        body = ""
        response.on 'data', (chunk) ->
          body += chunk

        response.on 'end', ->
          test.same "true", body

  async.series [createRequest, createRequest, createRequest], ->
    process.quit ->
      test.done()

exports.testAssigningRunOnceRestartsProcess = (test) ->
  test.expect 9

  process = createProcess "#{__dirname}/fixtures/once.ru"

  createRequest = (callback) ->
    process.createConnection (err, client) ->
      test.ifError err

      client.on 'error', (err) ->
        test.ifError err

      client.once 'close', callback

      request = client.request 'GET', '/foo', {}, 'rack.run_once': true
      request.end()

      request.on 'response', (response) ->
        test.same 200, response.statusCode

        body = ""
        response.on 'data', (chunk) ->
          body += chunk

        response.on 'end', ->
          test.same "true", body

  createRequest ->
    process.runOnce = true
    createRequest ->
      createRequest ->
        process.quit ->
          test.done()

exports.testCreateConnectionWithRunOnceMultiple = (test) ->
  test.expect 9

  process = createProcess "#{__dirname}/fixtures/once.ru", runOnce: true

  createRequest = (callback) ->
    process.createConnection (err, client) ->
      test.ifError err

      client.on 'error', (err) ->
        test.ifError err

      client.once 'close', callback

      request = client.request 'GET', '/foo', {}, 'rack.run_once': true
      request.end()

      request.on 'response', (response) ->
        test.same 200, response.statusCode

        body = ""
        response.on 'data', (chunk) ->
          body += chunk

        response.on 'end', ->
          test.same "true", body

  async.parallel [createRequest, createRequest, createRequest], ->
    process.quit ->
      test.done()

exports.testCreateConnectionWithClientException = (test) ->
  test.expect 5

  process = createProcess "#{__dirname}/fixtures/error.ru"

  process.once 'ready', ->
    test.ok true

  process.on 'exit', ->
    test.ok true
    test.done()

  process.createConnection (err, client) ->
    test.ifError err
    test.ok client

    client.on 'close', ->
      process.quit()

    request = client.request 'GET', '/', {}
    request.on 'error', (exception) ->
      test.ok exception

    request.end()

exports.testProxy = (test) ->
  test.expect 5

  process = createProcess config

  process.once 'ready', ->
    test.ok true

  process.on 'exit', ->
    test.ok true
    test.done()

  server = http.createServer (req, res) ->
    server.close()

    process.once 'busy', ->
      test.ok true

    process.once 'ready', ->
      test.ok true

    process.proxy req, res, (err) ->
      test.ifError err

  server.listen 0
  server.on 'listening', ->
    req = http.request host: '127.0.0.1', port: server.address().port, (res) ->
      test.same 200, res.statusCode
      res.on 'error', (err) -> test.ifError err
      res.on 'end', -> process.quit()
    req.end()

exports.testProxyDoesntEmitDuplicateDataEvents = (test) ->
  test.expect 3

  process = createProcess config

  process.on 'exit', ->
    test.ok true
    test.done()

  server = http.createServer (req, res) ->
    server.close()

    data = ""
    req.on 'data', (chunk) -> data += chunk
    req.on 'end', ->
      test.same "foo=bar", data

    process.proxy req, res, (err) ->
      test.ifError err

  server.listen 0
  server.on 'listening', ->
    req = http.request method: 'POST', host: '127.0.0.1', port: server.address().port, (res) ->
      test.same 200, res.statusCode
      process.quit()
    req.write "foo="
    req.write "bar"
    req.end()

exports.testProxyWithClientException = (test) ->
  test.expect 6

  process = createProcess "#{__dirname}/fixtures/error.ru"

  process.once 'ready', ->
    test.ok true

  process.on 'exit', ->
    test.ok true
    test.done()

  server = http.createServer (req, res) ->
    server.close()

    process.once 'busy', ->
      test.ok true

    process.once 'ready', ->
      test.ok true

    process.proxy req, res, (err) ->
      test.ok err
      res.writeHead 500
      res.end()
      process.quit()

  server.listen 0
  server.on 'listening', ->
    req = http.request host: '127.0.0.1', port: server.address().port, (res) ->
      test.same 500, res.statusCode
    req.end()

exports.testKill = (test) ->
  test.expect 5

  process = createProcess config

  process.once 'ready', ->
    test.ok true
    test.ok sockPath = process.sockPath

    process.kill ->
      test.ok sockPath
      fs.unlinkSync sockPath
      test.done()

  process.once 'quitting', () ->
    test.ok true

  process.on 'error', (error) ->
    test.ifError error

  process.once 'exit', ->
    test.ok true

  process.spawn()

exports.testKillUnspawned = (test) ->
  test.expect 1

  process = createProcess config

  process.kill ->
    test.ok true
    test.done()

exports.testTerminate = (test) ->
  test.expect 3

  process = createProcess config

  process.once 'ready', ->
    test.ok true
    process.terminate()

  process.once 'quitting', () ->
    test.ok true

  process.on 'error', (error) ->
    test.ifError error

  process.once 'exit', ->
    test.ok true
    test.done()

  process.spawn()

exports.testTerminateCallback = (test) ->
  test.expect 3

  process = createProcess config

  process.once 'ready', ->
    test.ok true
    process.terminate ->
      test.ok true
      test.done()

  process.once 'quitting', () ->
    test.ok true

  process.on 'error', (error) ->
    test.ifError error

  process.spawn()

exports.testTerminateUnspawned = (test) ->
  test.expect 1

  process = createProcess config

  process.terminate ->
    test.ok true
    test.done()

exports.testQuitSpawned = (test) ->
  test.expect 4

  process = createProcess config

  process.on 'spawn', ->
    test.ok true

  process.once 'ready', ->
    test.ok true
    process.quit()

  process.once 'quitting', ->
    test.ok true

  process.on 'error', (error) ->
    test.ifError error

  process.once 'exit', ->
    test.ok true
    test.done()

  process.spawn()

exports.testQuitCallback = (test) ->
  test.expect 3

  process = createProcess config

  process.once 'ready', ->
    test.ok true
    process.quit ->
      test.ok true
      test.done()

  process.once 'quitting', ->
    test.ok true

  process.spawn()

exports.testQuitUnspawned = (test) ->
  test.expect 1

  process = createProcess config

  process.once 'quitting', ->
    test.ok false

  process.on 'error', (error) ->
    test.ifError error

  process.on 'exit', ->
    test.ok false

  process.quit ->
    test.ok true
    test.done()

exports.testRestart = (test) ->
  test.expect 4

  process = createProcess config

  process.once 'ready', ->
    process.on 'error', (error) ->
      test.ifError error

    process.once 'quitting', ->
      test.ok true

    process.once 'exit', ->
      test.ok true

    process.once 'ready', ->
      test.ok true

      process.quit ->
        test.ok true
        test.done()

    process.restart()

  process.spawn()

exports.testErrorCreatingProcess = (test) ->
  test.expect 5

  count = 2
  done = ->
    if --count is 0
      test.done()

  process = createProcess __dirname + "/fixtures/crash.ru"

  process.on 'spawning', ->
    test.ok true

  process.on 'error', (error) ->
    test.same "b00m", error.message
    done()

  process.on 'exit', ->
    test.ok !process.sockPath
    test.ok !process.child
    done()

  process.spawn (err) ->
    test.ok err

exports.testErrorCreatingProcessOnConnection = (test) ->
  test.expect 3

  count = 2
  done = ->
    if --count is 0
      test.done()

  process = createProcess __dirname + "/fixtures/crash.ru"

  process.on 'exit', ->
    test.ok true
    done()

  process.createConnection (err) ->
    test.ok err
    test.same "b00m", err.message
    done()

exports.testErrorCreatingProcessOnProxy = (test) ->
  test.expect 3

  count = 3
  done = ->
    if --count is 0
      test.done()

  process = createProcess __dirname + "/fixtures/crash.ru"

  process.on 'exit', ->
    test.ok true
    done()

  server = http.createServer (req, res) ->
    server.close()

    process.proxy req, res, (err) ->
      test.ok err
      res.writeHead 500
      res.end()
      process.quit()
      done()

  server.listen 0
  server.on 'listening', ->
    req = http.request host: '127.0.0.1', port: server.address().port, (res) ->
      test.same 500, res.statusCode
      done()
    req.end()

exports.testProxyWithClientResponseLength = (test) ->
  test.expect 6

  process = createProcess "#{__dirname}/fixtures/length.ru"

  process.on 'exit', ->
    test.done()

  server = http.createServer (req, res) ->
    server.close()

    process.proxy req, res, (err) ->
      test.ifError err

  server.listen 0
  server.on 'listening', ->
    http.get host: '127.0.0.1', port: server.address().port, (res) ->
      test.same 200,          res.statusCode
      test.same 'text/plain', res.headers['content-type']
      test.same '10', res.headers['content-length']
      test.ok !res.headers['transfer-encoding']

      body = ""
      res.on 'data', (chunk) ->
        body += chunk

      res.on 'end', ->
        test.same "foobar\nbaz", body
        test.same true, res.complete
        process.quit()

exports.testProxyWithClientResponseNoLength = (test) ->
  test.expect 7

  process = createProcess "#{__dirname}/fixtures/nolength.ru"

  process.on 'exit', ->
    test.done()

  server = http.createServer (req, res) ->
    server.close()

    process.proxy req, res, (err) ->
      test.ifError err

  server.listen 0
  server.on 'listening', ->
    http.get host: '127.0.0.1', port: server.address().port, (res) ->
      test.same 200,          res.statusCode
      test.same 'close',      res.headers['connection']
      test.same 'text/plain', res.headers['content-type']
      test.ok !res.headers['content-length']
      test.ok !res.headers['transfer-encoding']

      body = ""
      res.on 'data', (chunk) ->
        body += chunk

      res.on 'end', ->
        test.same "foobar\nbaz", body
        test.same true, res.complete
        process.quit()

exports.testProxyWithClientResponseChunked = (test) ->
  test.expect 7

  process = createProcess "#{__dirname}/fixtures/chunked.ru"

  process.on 'exit', ->
    test.done()

  server = http.createServer (req, res) ->
    server.close()

    process.proxy req, res, (err) ->
      test.ifError err

  server.listen 0
  server.on 'listening', ->
    http.get host: '127.0.0.1', port: server.address().port, (res) ->
      test.same 200,          res.statusCode
      test.same 'close',      res.headers['connection']
      test.same 'chunked',    res.headers['transfer-encoding']
      test.same 'text/plain', res.headers['content-type']
      test.ok !res.headers['content-length']

      body = ""
      res.on 'data', (chunk) ->
        body += chunk

      res.on 'end', ->
        test.same "foobar\nbaz", body
        test.same true, res.complete
        process.quit()
