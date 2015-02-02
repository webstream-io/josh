async         = require 'async'
fs            = require 'fs'
{print}       = require 'util'
{spawn, exec} = require 'child_process'

brewCoffee = (watch, dest, src, callback) ->
  if typeof watch is 'function'
    callback = watch
    watch = false
  options = ['-c', '-m', '-o', dest, src]
  options.unshift '-w' if watch

  coffee = spawn 'node_modules/.bin/coffee', options
  coffee.stdout.on 'data', (data) -> print data.toString()
  coffee.stderr.on 'data', (data) -> print data.toString()
  coffee.on 'exit', (status) -> callback?() if status is 0
  
build = (watch, callback) ->
  brewCoffee(watch, 'lib', 'src', callback)

buildAdapters = (watch, callback) ->
  brewCoffee(watch, 'adapters/ruby_rack/lib', 'adapters/ruby_rack/src', callback)
  
buildTemplates = (callback) ->
  exec = require('child_process').exec;
  exec("mkdir -p lib/templates/http_server")
  exec("mkdir -p lib/templates/installer")
  eco = require 'eco'
  compile = (name) ->
    (callback) ->
      fs.readFile "src/templates/#{name}.eco", "utf8", (err, data) ->
        if err then callback err
        else fs.writeFile "lib/templates/#{name}.js", "module.exports = #{eco.precompile(data)}", callback

  async.parallel [
    compile("http_server/application_not_found.html")
    compile("http_server/error_starting_application.html")
    compile("http_server/layout.html")
    compile("http_server/proxy_error.html")
    compile("http_server/rackup_file_missing.html")
    compile("http_server/rvm_deprecation_notice.html")
    compile("http_server/welcome.html")
    compile("installer/cx.pow.firewall.plist")
    compile("installer/cx.pow.powd.plist")
    compile("installer/resolver")
  ], callback

task 'docs', 'Generate annotated source code with Docco', ->
  fs.readdir 'src', (err, contents) ->
    files = ("src/#{file}" for file in contents when /\.coffee$/.test file)
    docco = spawn 'node_modules/.bin/docco', files
    docco.stdout.on 'data', (data) -> print data.toString()
    docco.stderr.on 'data', (data) -> print data.toString()
    docco.on 'exit', (status) -> callback?() if status is 0

task 'build', 'Compile CoffeeScript source files', ->
  build()
  buildTemplates()
  buildAdapters()

task 'watch', 'Recompile CoffeeScript source files when modified', ->
  build true
  buildAdapters true

task 'pretest', "Install test dependencies", ->
  exec 'which ruby gem', (err) ->
    throw "ruby not found" if err

    exec 'ruby -rubygems -e \'require "rack"\'', (err) ->
      if err
        exec 'gem install rack', (err, stdout, stderr) ->
          throw err if err

task 'test', 'Run the Pow test suite', ->
  build ->
    buildTemplates ->
      buildAdapters ->
        process.env["NODE_ENV"] = "test"

        # Because nodeunit isn't printing the error otherwise
        process.on 'uncaughtException', (err) ->
          throw err

        {reporters} = require 'nodeunit'
        process.chdir __dirname
        reporters.default.run ['test'], null

task 'adapter-test', "Test all the adapters", ->
  build ->
    buildTemplates ->
      buildAdapters ->
        child = spawn "./adapter-make", ["test"], stdio: "inherit", cwd: "#{__dirname}/adapters/ruby_rack"
        child.on "exit", (code) ->
          throw "Error #{code}: Tests failed for ruby_rack" unless code == 0
          child = spawn "./adapter-make", ["test"], stdio: "inherit", cwd: "#{__dirname}/adapters/python_wsgi"
          child.on "exit", (code) ->
            throw "Error #{code}: Tests failed for python_wsgi" unless code == 0

task 'install', 'Install pow configuration files', ->
  sh = (command, callback) ->
    exec command, (err, stdout, stderr) ->
      if err
        console.error stderr
        callback err
      else
        callback()

  createHostsDirectory = (callback) ->
    sh 'mkdir -p "$HOME/Library/Application Support/Pow/Hosts"', (err) ->
      fs.stat "#{process.env['HOME']}/.pow", (err) ->
        if err then sh 'ln -s "$HOME/Library/Application Support/Pow/Hosts" "$HOME/.pow"', callback
        else callback()

  installLocal = (callback) ->
    console.error "*** Installing local configuration files..."
    sh "./bin/pow --install-local", callback

  installSystem = (callback) ->
    exec "./bin/pow --install-system --dry-run", (needsRoot) ->
      if needsRoot
        console.error "*** Installing system configuration files as root..."
        sh "sudo ./bin/pow --install-system", (err) ->
          if err
            callback err
          else
            sh "sudo launchctl load /Library/LaunchDaemons/cx.pow.firewall.plist", callback
      else
        callback()

  async.parallel [createHostsDirectory, installLocal, installSystem], (err) ->
    throw err if err
    console.error "*** Installed"

task 'start', 'Start pow server', ->
  agent = "#{process.env['HOME']}/Library/LaunchAgents/cx.pow.powd.plist"
  console.error "*** Starting the Pow server..."
  exec "launchctl load '#{agent}'", (err, stdout, stderr) ->
    console.error stderr if err

task 'stop', 'Stop pow server', ->
  agent = "#{process.env['HOME']}/Library/LaunchAgents/cx.pow.powd.plist"
  console.error "*** Stopping the Pow server..."
  exec "launchctl unload '#{agent}'", (err, stdout, stderr) ->
    console.error stderr if err
