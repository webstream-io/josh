run lambda { |env|
  [200, {
     'Content-Type' => 'text/plain',
     'Content-Length' => '10'
   }, ['foo', 'bar', "\nbaz"]]
}
