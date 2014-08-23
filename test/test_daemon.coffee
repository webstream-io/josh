net = require "net"
fs = require "fs"
path = require "path"
{testCase} = require "nodeunit"
{Configuration, Daemon} = require ".."
{prepareFixtures, fixturePath, touch} = require "./lib/test_helper"

module.exports = testCase
  setUp: (proceed) ->
    prepareFixtures proceed

  "start and stop": (test) ->
    test.expect 2

    configuration = new Configuration JOSH_HOST_ROOT: fixturePath("tmp"), JOSH_HTTP_PORT: 0, JOSH_DNS_PORT: 0
    daemon = new Daemon configuration

    daemon.start()
    daemon.on "start", ->
      test.ok daemon.started
      daemon.stop()
      daemon.on "stop", ->
        test.ok !daemon.started
        test.done()

  "start rolls back when it can't boot a server": (test) ->
    test.expect 2

    server = net.createServer()
    server.listen 0, ->
      port = server.address().port
      configuration = new Configuration JOSH_HOST_ROOT: fixturePath("tmp"), JOSH_HTTP_PORT: port
      daemon = new Daemon configuration

      daemon.start()
      daemon.on "error", (err) ->
        test.ok err
        test.ok !daemon.started
        server.close()
        test.done()

  "touching restart.txt removes the file and emits a restart event": (test) ->
    test.expect 1

    restartFilename = path.join fixturePath("tmp"), "restart.txt"
    configuration = new Configuration JOSH_HOST_ROOT: fixturePath("tmp"), JOSH_HTTP_PORT: 0, JOSH_DNS_PORT: 0
    daemon = new Daemon configuration

    daemon.start()

    daemon.once "restart", ->
      fs.exists restartFilename, (exists) ->
        test.ok !exists
        daemon.stop()
        test.done()

    # Because of identifyUidAndGid() method being called within start(), it is delaying
    # the `start` event in daemon which assigns `@watcher`, causing `@watcher` to be
    # assigned _after_ following touch call is completed.
    # 
    # So, delay the touch by a few milliseconds
    setTimeout ->
      touch restartFilename
    , 100
