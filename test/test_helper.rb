require "rubygems"

require "simplecov"
require "coveralls"
SimpleCov.start do
  add_filter "/test/"
end

require "codeclimate-test-reporter"
CodeClimate::TestReporter.start

require "minitest/autorun"
require "minitest/reporters"
MiniTest::Reporters.use!

require "shoulda"
require "shoulda-context"
require "shoulda-matchers"

# Make the code to be tested easy to load.
$LOAD_PATH.unshift(File.dirname(__FILE__))
$LOAD_PATH.unshift(File.join(File.dirname(__FILE__), "..", "lib"))

require 'active_support/testing/assertions'
include ActiveSupport::Testing::Assertions

require "benchmark"

require 'mail'
Mail.defaults do
  delivery_method :test
end
include Mail::Matchers

require "sms_safe"

# Add helper methods to use in the tests
class MiniTest::Test
  # Calls Interceptor#intercept_message? with a bunch of numbers, and checks that they return the expected result
  def check_interception_rules(interceptor, numbers_to_check, expected_result)
    numbers_to_check.each do |number|
      message = SmsSafe::Message.new(from: number, to: number, text: "Foo")
      assert_equal expected_result, interceptor.intercept_message?(message)
    end
  end

  # Calls process_message for a message that should be intercepted.
  # Checks that the message received back is identical to the one sent
  def process_and_assert_identical_message(interceptor, message)
    original_message = message.clone
    result = interceptor.process_message(message)
    refute_nil result
    assert_equal original_message.class, result.class
    assert_equal original_message.from, result.from
    assert_equal original_message.to, result.to
    assert_equal original_message.text, result.text
  end
end

# Empty Interceptor that we can use for testing. Does what normal interceptors do,
# but it does it with our own internal Message class, no converting or anything fancy.
class TestInterceptor < SmsSafe::Interceptor
  def convert_message(message)
    message
  end

  def redirect(message)
    message.to = redirect_phone_number(message)
    message.text = redirect_text(message)
    message
  end
end
