
def application(environ, start_response):
    start_response(200, {("Content-Type", "text/plain")})
    return ["foor", "bar", "\nbaz"]
