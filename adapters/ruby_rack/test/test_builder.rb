require 'nack/builder'

require 'minitest/autorun'

class TestBuilder < MiniTest::Unit::TestCase
  def test_delegate_builder_methods
    assertProc = lambda { |*args| assert(*args) }
    builder = Nack::Builder.new {
      assertProc.call require('rack/builder')
      run lambda {}
    }
    assert builder.to_app
    assert !require('rack/builder')
  end
end
