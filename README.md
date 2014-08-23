## josh - http server for developers. [![Build Status](https://travis-ci.org/webstream-io/josh.svg)](https://travis-ci.org/webstream-io/josh)

**josh** (with lower case **j**) is a minimal configuration http(s) server for developers which responds to all `*.dev` domains and after a simple symlink it can start serving your application `myapp` at `myapp.dev`.

It,
  * automatically starts the server when you first access `myapp.dev`
  * works with `any.depth.of.subdomains.you.want.at.myapp.dev`
  * can serve multiple projects at the same time on different `*.dev` domains

josh is a fork of [Pow rack server for Mac OS X](https://github.com/basecamp/pow).


### How does it work?

josh takes advantage of Linux's Name Server Switch and ships with a NSS service which forwards all `*.dev` domains to `127.0.0.1` where it is listening on port `80`.

### Supported web server interfaces

Web server interfaces are supported in josh using `adapters`. Adapters currently included in core are:

* `ruby_rack` - implements `Rack` interface which serves pretty much all Ruby frameworks (including Ruby on Rails).

Support for more interfaces is planned.

### Supported platforms

* [Upstart](http://upstart.ubuntu.com/) based operating systems (Ubuntu family).

Support for [systemd](http://www.freedesktop.org/wiki/Software/systemd/) is in works.

### Installation

    git clone https://github.com/webstream-io/josh.git
    cd josh
    ./install.sh
    
### Usage

To serve application `myapp`

    cd ~/.josh
    ln -s /path/to/myapp
    
That's it! Access `myapp.dev` in a browser to start the application.

### TODO

* [HTTPS support](https://github.com/webstream-io/josh/issues/8)
* [Python WSGI support](https://github.com/webstream-io/josh/issues/4)
* Support more languages and operating systems.

### About name

TODO
