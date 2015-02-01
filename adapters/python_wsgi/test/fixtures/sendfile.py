
def application(environ, start_response):
    start_response(200, {("Content-Type", "text/x-script.python"), ("Content-Length", "0"), ("X-Sendfile", File.expand_path(__FILE__))})
    return []
