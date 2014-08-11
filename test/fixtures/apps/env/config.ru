require "json"

run lambda { |env|
  body = ENV.keys.grep(/^JOSH/).inject({}) { |e, k| e.merge(k => ENV[k]) }.to_json
  [200, {'Content-Type' => 'text/plain', 'Content-Length' => body.length.to_s}, [body]]
}
