
def application(environ, start_response):
    start_response(200, {("Content-Type", "text/plain"), ("Content-Length", "10")})
    return ["foor", "bar", "\nbaz"]
