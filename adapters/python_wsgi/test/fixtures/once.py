
def application(environ, start_response):
    count += 1
    raise Exception("count more than one") if count > 1
    start_response(200, {("Content-Type", "text/plain")})
    return environ["wsgi.run_once"].toString()
