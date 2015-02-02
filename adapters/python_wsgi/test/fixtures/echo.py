
def application(environ, start_response):
    body = environ["wsgi.input"].read()
    start_response(200, {("Content-Type", "text/plain"), ("Set-Cookie", "foo=1\nbar=2")})
    return [body]
