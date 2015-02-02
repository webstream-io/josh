
def simple_app(environ, start_response):
    headers = [('Content-Type', 'text/plain')]
    start_response('200 OK', headers)

    def content():
        # We start streaming data just fine.
        yield 'The dwarves of yore made mighty spells,'
        yield 'While hammers fell like ringing bells'

        # Then the back-end fails!
        try:
            1/0
        except:
            start_response('500 Error', headers, sys.exc_info())
            return

        # So rest of the response data is not available.
        yield 'In places deep, where dark things sleep,'
        yield 'In hollow halls beneath the fells.'

    return content()
