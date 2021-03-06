# The `Configuration` class encapsulates various options for a josh
# daemon (port numbers, directories, etc.). It's also responsible for
# creating `Logger` instances and mapping hostnames to application
# root paths.

fs                = require "fs"
path              = require "path"
async             = require "async"
Logger            = require "./logger"
{mkdirp}          = require "./util"
{sourceScriptEnv} = require "./util"
{getUserEnv}      = require "./util"

module.exports = class Configuration
  # The user configuration file, `~/.joshconfig`, is evaluated on
  # boot.  You can configure options such as the top-level domain,
  # number of workers, the worker idle timeout, and listening ports.
  #
  #     export JOSH_DOMAINS=dev,test
  #     export JOSH_WORKERS=3
  #
  # See the `Configuration` constructor for a complete list of
  # environment options.
  @userConfigurationPath: path.join "/etc", "josh", "config"

  # Evaluates the user configuration script and calls the `callback`
  # with the environment variables if the config file exists. Any
  # script errors are passed along in the first argument. (No error
  # occurs if the file does not exist.)
  @loadUserConfigurationEnvironment: (callback) ->
    # FIXME: josh is run under root and env should be loaded through /etc/josh/env instead
    return callback null, process.env
    getUserEnv (err, env) =>
      if err
        callback err
      else
        fs.exists p = @userConfigurationPath, (exists) ->
          if exists
            sourceScriptEnv p, env, callback
          else
            callback null, env

  # Creates a Configuration object after evaluating the user
  # configuration file. Any environment variables in `~/.joshconfig`
  # affect the process environment and will be copied to spawned
  # subprocesses.
  @getUserConfiguration: (callback) ->
    @loadUserConfigurationEnvironment (err, env) ->
      if err
        callback err
      else
        callback null, new Configuration env

  # A list of option names accessible on `Configuration` instances.
  @optionNames: [
    "bin", "dstPort", "httpPort", "dnsPort", "timeout", "workers",
    "domains", "extDomains", "hostRoot", "logRoot", "rvmPath"
  ]

  # Pass in any environment variables you'd like to override when
  # creating a `Configuration` instance.
  constructor: (env = process.env) ->
    @loggers = {}
    @loadConfig env
    @initialize env

  # Load the configuration from /etc/josh/config.json or from a
  # custom config file set by `JOSH_CONFIG_PATH` env variable.
  loadConfig: (env) ->
    configPath = env.JOSH_CONFIG_PATH ? '/etc/josh/config.json'
    if fs.existsSync(configPath)
      @config = JSON.parse fs.readFileSync configPath
    else
      @config = {}

  # Valid environment variables and their defaults:
  initialize: (@env) ->
    # `JOSHD_BIN`: the path to the `josh` binary. (This should be
    # correctly configured for you.)
    @bin        = env.JOSHD_BIN         ? path.join __dirname, "../bin/joshd"

    # `JOSH_RUN_AS_USER`: value for `setuid`.
    # User to which the process will make its owner after
    # doing privileged work like binding to restricted ports (e.g., 80 & 443).
    @runAsUser  = env.JOSH_RUN_AS_USER  ? @config["run as user"]

    # `JOSH_RUN_AS_GROUP`: value for `setguid()`, defaults to `@runAsUser`
    @runAsGroup  = env.JOSH_RUN_AS_GROUP  ? @config["run as group"] ? @runAsUser

    # `JOSH_DST_PORT`: the public port josh expects to be forwarded or
    # otherwise proxied for incoming HTTP requests. Defaults to `80`.
    # 
    # FIXME: This needs to be removed
    @dstPort    = env.JOSH_DST_PORT    ? 80

    # `JOSH_HTTP_PORT`: the TCP port josh opens for accepting incoming
    # HTTP requests. Defaults to `20559`.
    @httpPort   = env.JOSH_HTTP_PORT   ? @config["http port"] ? 20559

    # `JOSH_DNS_PORT`: the UDP port josh listens on for incoming DNS
    # queries. Defaults to `20560`.
    @dnsPort    = env.JOSH_DNS_PORT    ? 20560

    # `JOSH_TIMEOUT`: how long (in seconds) to leave inactive Rack
    # applications running before they're killed. Defaults to 16
    # minutes (960 seconds).
    @timeout    = env.JOSH_TIMEOUT     ? @config["inactive app timeout in seconds"] ? 16 * 60

    # `JOSH_WORKERS`: the maximum number of worker processes to spawn
    # for any given application. Defaults to `2`.
    @workers    = env.JOSH_WORKERS     ? @config["max workers per application"] ? 2

    # `JOSH_DOMAINS`: the top-level domains for which josh will respond
    # to DNS `A` queries with `127.0.0.1`. Defaults to `dev`. If you
    # configure this in your `~/.joshconfig` you will need to re-run
    # `sudo josh --install-system` to make `/etc/resolver` aware of
    # the new TLDs.
    @domains    = env.JOSH_DOMAINS     ? env.JOSH_DOMAIN ? @config["tlds"] ? "dev"

    # `JOSH_EXT_DOMAINS`: additional top-level domains for which josh
    # will serve HTTP requests (but not DNS requests -- hence the
    # "ext").
    # FIXME: This is not required as no DNS server is implemented in
    # josh and is handled by josh's NSS service instead.
    @extDomains = env.JOSH_EXT_DOMAINS ? []

    # Allow for comma-separated domain lists, e.g. `JOSH_DOMAINS=dev,test`
    @domains    = @domains.split?(",")    ? @domains
    @extDomains = @extDomains.split?(",") ? @extDomains
    @allDomains = @domains.concat @extDomains

    # Support *.xip.io top-level domains.
    @allDomains.push /\d+\.\d+\.\d+\.\d+\.xip\.io$/, /[0-9a-z]{1,7}\.xip\.io$/

    # `JOSH_HOST_ROOT`: path to the directory containing symlinks to
    # applications that will be served by josh. Defaults to
    # `~/Library/Application Support/josh/Hosts`.
    @hostRoot   = env.JOSH_HOST_ROOT   ? @config["hosts directory"] ? "/var/lib/josh"

    # `JOSH_LOG_ROOT`: path to the directory that josh will use to store
    # its log files. Defaults to `~/Library/Logs/josh`.
    @logRoot    = env.JOSH_LOG_ROOT    ? @config["log directory"] ? "/tmp/josh-log"

    # `JOSH_RVM_PATH` (**deprecated**): path to the rvm initialization
    # script. Defaults to `~/.rvm/scripts/rvm`.
    @rvmPath    = env.JOSH_RVM_PATH    ? path.join "/tmp/deprecated/so/remove", ".rvm/scripts/rvm"

    # ---
    # Precompile regular expressions for matching domain names to be
    # served by the DNS server and hosts to be served by the HTTP
    # server.
    @dnsDomainPattern  = compilePattern @domains
    @httpDomainPattern = compilePattern @allDomains

  # Gets an object of the `Configuration` instance's options that can
  # be passed to `JSON.stringify`.
  toJSON: ->
    result = {}
    result[key] = @[key] for key in @constructor.optionNames
    result

  # Special logger that also outputs to STDOUT
  serverLogger: ->
    # instance variable can not have same name as instance function or it will return itself.
    @_serverLogger ?= new Logger path.join(@logRoot, "server.log"), null, true

  # Retrieve a `Logger` instance with the given `name`.
  getLogger: (name) ->
    @loggers[name] ||= new Logger path.join @logRoot, name + ".log"

  # Globally disable or enable RVM deprecation notices by touching or
  # removing the `~/Library/Application
  # Support/josh/.disableRvmDeprecationNotices` file.
  disableRvmDeprecationNotices: ->
    fs.writeFile path.join(@hostRoot, ".disableRvmDeprecationNotices"), ""

  enableRvmDeprecationNotices: ->
    fs.unlink path.join @hostRoot, ".disableRvmDeprecationNotices"

  # Search `hostRoot` for files, symlinks or directories matching the
  # domain specified by `host`. If a match is found, the matching domain
  # name and its configuration are passed as second and third arguments
  # to `callback`.  The configuration will either have a `root` or
  # a `port` property.  If no match is found, `callback` is called
  # without any arguments.  If an error is raised, `callback` is called
  # with the error as its first argument.
  findHostConfiguration: (host = "", callback) ->
    @gatherHostConfigurations (err, hosts) =>
      return callback err if err
      for domain in @allDomains
        for file in getFilenamesForHost host, domain
          if config = hosts[file]
            return callback null, domain, config

      if config = hosts["default"]
        return callback null, @allDomains[0], config

      callback null

  # Asynchronously build a mapping of entries in `hostRoot` to
  # application root paths and proxy ports. For each symlink, store the
  # symlink's name and the real path of the application it points to.
  # For each directory, store the directory's name and its full path.
  # For each file that contains a port number, store the file's name and
  # the port.  The mapping is passed as an object to the second argument
  # of `callback`. If an error is raised, `callback` is called with the
  # error as its first argument.
  #
  # The mapping object will look something like this:
  #
  #     {
  #       "basecamp":  { "root": "/Volumes/37signals/basecamp" },
  #       "launchpad": { "root": "/Volumes/37signals/launchpad" },
  #       "37img":     { "root": "/Volumes/37signals/portfolio" },
  #       "couchdb":   { "url":  "http://localhost:5984" }
  #     }
  gatherHostConfigurations: (callback) ->
    hosts = {}
    mkdirp @hostRoot, (err) =>
      return callback err if err
      fs.readdir @hostRoot, (err, files) =>
        return callback err if err
        async.forEach files, (file, next) =>
          root = path.join @hostRoot, file
          name = file.toLowerCase()
          rstat root, (err, stats, path) ->
            if stats?.isDirectory()
              hosts[name] = root: path
              next()
            else if stats?.isFile()
              fs.readFile path, 'utf-8', (err, data) ->
                return next() if err
                data = data.trim()
                if data.length < 10 and not isNaN(parseInt(data))
                  hosts[name] = {url: "http://localhost:#{parseInt(data)}"}
                else if data.match("https?://")
                  hosts[name] = {url: data}
                next()
            else
              next()
        , (err) ->
          callback err, hosts

# Strip a trailing `domain` from the given `host`, then generate a
# sorted array of possible entry names for finding which application
# should serve the host. For example, a `host` of
# `asset0.37s.basecamp.dev` will produce `["asset0.37s.basecamp",
# "37s.basecamp", "basecamp"]`, and `basecamp.dev` will produce
# `["basecamp"]`.
getFilenamesForHost = (host, domain) ->
  host = host.toLowerCase()
  domain = host.match(domain)?[0] ? "" if domain.test?

  if host.slice(-domain.length - 1) is ".#{domain}"
    parts  = host.slice(0, -domain.length - 1).split "."
    length = parts.length
    for i in [0...length]
      parts.slice(i, length).join "."
  else
    []

# Similar to `fs.stat`, but passes the realpath of the file as the
# third argument to the callback.
rstat = (path, callback) ->
  fs.lstat path, (err, stats) ->
    if err
      callback err
    else if stats?.isSymbolicLink()
      fs.realpath path, (err, realpath) ->
        if err then callback err
        else rstat realpath, callback
    else
      callback err, stats, path

# Helper function for compiling a list of top-level domains into a
# regular expression for matching purposes.
compilePattern = (domains) ->
  /// ( (^|\.) (#{domains.join("|")}) ) \.? $ ///i
