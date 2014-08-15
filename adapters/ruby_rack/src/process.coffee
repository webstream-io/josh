client              = require './client'
fs                  = require 'fs'
{dirname}           = require 'path'
{debug, isFunction} = require './util'
{BufferedRequest}   = require './util'
{LineBuffer}        = require './util'
{spawn, exec}       = require 'child_process'
{EventEmitter}      = require 'events'
{Stream}            = require 'net'

exists = fs.exists ? require('path').exists

packageLib = fs.realpathSync __dirname
packageBin = fs.realpathSync "#{__dirname}/../bin"

# **Process** manages a single Ruby worker process.
#
# A Process requires a path to a rackup config file _(config.ru)_.
#
#     process.createProcess("/path/to/app/config.ru");
#
# You can set a idle time so the process dies after a
# specified amount of milliseconds.
#
#     var ms = 15 * 60 * 1000;
#     process.createProcess("/path/to/app/config.ru", { idle: ms });
#
# A Process has 5 states:
#
# > `null`: Not started or dead
# >
# > `spawning`: Is booting and can't accept a connection yet
# >
# > `ready`: Is ready to accept a connection and handle a request
# >
# > `busy`: Is currently handling a request, not ready
# >
# > `quitting`: Was set a kill signal and is shutting down
#
# Anytime a process changes states, an event is fired with the new
# state name. When the process becomes `ready`, a `ready` is fired.
#
# Other events:
#
# > **Event: 'error'**
# >
# > `function (exception) { }`
# >
# > Emitted when an error occurs.
# >
# > **Event: 'spawn'**
# >
# > `function (exception) { }`
# >
# > Emitted when the process moves from `spawning` to `ready` state.
# >
# > **Event: 'exit'**
# >
# > `function () { }`
# >
# > Emitted when the Process terminates.
# >
# > **Event: 'idle'**
# >
# > `function () { }`
# >
# > Emitted when the Process times out because of inactivity.
#
exports.Process = class Process extends EventEmitter
  constructor: (@config, options) ->
    @id = Math.floor Math.random() * 1000

    options ?= {}
    @runOnce = options.runOnce ? false
    @idle    = options.idle
    @cwd     = options.cwd ? dirname(@config)
    @env     = options.env ? {}

    # Set initial state to `null`
    @state = null

    @_connectionQueue = []
    @_activeConnection = null

    raiseConfigError = =>
      @_handleError new Error "configuration \"#{@config}\" doesn't exist"

    if @config?
      exists @config, (ok) ->
        raiseConfigError() if !ok
    else
      raiseConfigError()

  @::__defineGetter__ 'runOnce', ->
    @_runOnce

  @::__defineSetter__ 'runOnce', (value) ->
    # If runOnce is beening changed from false to true and there is a
    # process spawned, restart it.
    if @_runOnce is false and value is true and @child
      debug "enabling runOnce on process ##{@id}"
      @restart()
    @_runOnce = value

  spawn: (callback) ->
    return if @state

    debug "spawning process ##{@id}"

    if callback?
      onSpawn = (err) =>
        @removeListener 'ready', onSpawn
        @removeListener 'error', onSpawn
        callback err

      @on 'ready', onSpawn
      @on 'error', onSpawn

    @changeState 'spawning'

    @sockPath = "#{tmpFile()}.sock"

    env = {}
    for key, value of process.env
      env[key] = value

    for key, value of @env
      env[key] = value

    env['PATH']    = "#{packageBin}:#{env['PATH']}"
    env['RUBYLIB'] = "#{packageLib}:#{env['RUBYLIB']}"

    @heartbeat = new Stream

    @heartbeat.on 'connect', =>
      if @child.pid
        debug "process spawned ##{@id}"
        @emit 'spawn'
      else
        @_handleError new Error "unknown process error"

    @heartbeat.on 'data', (data) =>
      if @child.pid and "#{@child.pid}\n" is data.toString()
        @changeState 'ready'
        @_processConnections()
      else
        try
          exception   = JSON.parse data
          error       = new Error exception.message
          error.name  = exception.name
          error.stack = exception.stack

          debug "heartbeat error", error
          @_handleError error
        catch e
          debug "heartbeat error", e
          @_handleError new Error "unknown process error"

    tryConnect @heartbeat, @sockPath, (err) =>
      if err and out
        @_handleError new Error out
      else if err
        @_handleError err

    @child = spawn "josh-adapter-ruby_rack-worker", [@config, @sockPath],
      cwd: @cwd
      env: env

    @stdout = @child.stdout
    @stderr = @child.stderr

    out = null
    logData = (data) ->
      out ?= ""
      out += data.toString()

    @stdout.on 'data', logData
    @stderr.on 'data', logData

    @on 'spawn', =>
      out = null
      @stdout.removeListener 'data', logData
      @stderr.removeListener 'data', logData

    @child.on 'exit', (code, signal) =>
      debug "process exited ##{@id}"

      @clearTimeout()
      @heartbeat.destroy() if @heartbeat

      @state = @sockPath = null
      @child = @heartbeat = null
      @stdout = @stderr = null

      @emit 'exit'

    this

  # Change the current state and fire a corresponding event
  changeState: (state) ->
    if @state != state
      @state = state
      @emit state

  # Clear current timeout handler.
  clearTimeout: ->
    if @_timeoutId
      clearTimeout @_timeoutId

  # Defer the current idle timer.
  deferTimeout: ->
    self = this
    if @idle
      @clearTimeout()

      callback = ->
        self.emit 'idle'
        self.quit()

      @_timeoutId = setTimeout callback, @idle

  _processConnections: ->
    if not @_activeConnection and @_connectionQueue.length
      debug "accepted connection 1/#{@_connectionQueue.length} ##{@id}"
      @_activeConnection = @_connectionQueue.shift()

    if @_activeConnection and @state is 'ready'
      # Push back the idle time everytime a request is handled
      @deferTimeout()

      @changeState 'busy'

      connection = client.createConnection @sockPath

      connection.on 'close', =>
        delete @_activeConnection

        if @runOnce
          @quit => @_processConnections()
        else
          @changeState 'ready'
          @_processConnections()

      setTimeout =>
        @_activeConnection null, connection
      , 0
    else if @_activeConnection or @_connectionQueue.length
      @spawn()

  _handleError: (error) ->
    callback = @_activeConnection
    delete @_activeConnection

    if callback
      callback error
    else
      @emit 'error', error

  # Create a new **Client** connection
  createConnection: (callback) ->
    @_connectionQueue.push callback
    @_processConnections()
    this

  request: (args...) ->
    req = new BufferedRequest args...
    req.proxyMetaVariables['rack.run_once'] = @runOnce

    @createConnection (err, connection) =>
      if err
        req.emit 'error', err
      else
        debug "proxy #{req.method} #{req.url} to ##{@id}"
        clientRequest = connection.request()
        clientRequest.on 'error', (err) ->
          req.emit 'error', err
        clientRequest.on 'response', (response) ->
          req.emit 'response', response
        req.pipe clientRequest
        req.flush()

    req

  # Proxies a `http.ServerRequest` and `http.ServerResponse` to the process
  proxy: (req, res, next) =>
    installOnce req.connection.server, 'close', @quit

    clientRequest = @request()
    clientRequest.on 'error', next if next?
    clientRequest.on 'response', (clientResponse) ->
      clientResponse.pipe res
    req.pipe clientRequest

  # Send `SIGKILL` to process.
  # This will kill it for sure.
  kill: (callback) ->
    debug "process kill ##{@id}"

    if @child
      @changeState 'quitting'
      @once 'exit', callback if callback
      @child.kill 'SIGKILL'
      @heartbeat.destroy() if @heartbeat
    else
      callback?()

  # Send `SIGTERM` to process.
  # This will immediately kill it.
  terminate: (callback) ->
    debug "process terminate ##{@id}"

    if @child
      @changeState 'quitting'
      @once 'exit', callback if callback
      @child.kill 'SIGTERM'
      @heartbeat.destroy() if @heartbeat

      # Setup a timer to send SIGKILL if the process doesn't
      # exit after 10 seconds.
      timeout = setTimeout =>
        if @state is 'quitting'
          debug "process is hung, sending kill to ##{@id}"
          @kill()
      , 10000
      @once 'exit', -> clearTimeout timeout
    else
      callback?()

  # Send `SIGQUIT` to process.
  # The process will finish serving its request and gracefully quit.
  quit: (callback) =>
    debug "process quit ##{@id}"

    if @child
      @changeState 'quitting'
      @once 'exit', callback if callback
      @child.kill 'SIGQUIT'
      @heartbeat.destroy() if @heartbeat

      # Setup a timer to send SIGTERM if the process doesn't
      # gracefully quit after 3 seconds.
      timeout = setTimeout =>
        if @state is 'quitting'
          @terminate()
      , 3000
      @once 'exit', -> clearTimeout timeout
    else
      callback?()

  # Quit and respawn process
  restart: (callback) ->
    debug "process restart ##{@id}"
    @quit => @spawn callback

# Public API for creating a **Process**
exports.createProcess = (args...) ->
  new Process args...

# Generates a random path.
tmpFile = ->
  pid  = process.pid
  rand = Math.floor Math.random() * 10000000000
  "/tmp/nack." + pid + "." + rand

# TODO: Don't poll FS
onceFileExists = (path, callback, timeout = 3000) ->
  timeoutError = null
  timeoutId = setTimeout ->
    timeoutError = new Error "timeout: waiting for #{path}"
  , timeout

  decay = 1

  statPath = (err, stat) ->
    if !err and stat and stat.isSocket()
      clearTimeout timeoutId
      callback err, path
    else if timeoutError
      callback timeoutError, path
    else
      setTimeout ->
        fs.stat path, statPath
      , decay *= 2

  statPath()

tryConnect = (connection, path, callback) ->
  errors = 0

  reconnect = ->
    onceFileExists path, (err) ->
      return callback err if err
      connection.connect path

  onError = (err) ->
    if err and ++errors > 3
      connection.removeListener 'error', onError
      callback new Error "timeout: couldn't connect to #{path}"
    else
      reconnect()

  connection.on 'error', onError

  connection.on 'connect', ->
    connection.removeListener 'error', onError
    callback null, connection

  reconnect()

installOnce = (emitter, type, listener) ->
  if events = emitter._events[type]
    return if events is listener
    return for event in events when event is listener

  emitter.on type, listener
