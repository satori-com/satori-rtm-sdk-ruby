require 'simplecov'
SimpleCov.start do
  add_filter '/spec/'
end

$LOAD_PATH.unshift File.expand_path('../lib', __FILE__)

require 'satori-rtm-sdk'
require 'json'

module ConfigLoader
  def config
    @config ||= load_config
  end

  def endpoint
    config[:endpoint]
  end

  def appkey
    config[:appkey]
  end

  def auth_restricted_channel
    config[:auth_restricted_channel]
  end

  def auth_role_name
    config[:auth_role_name]
  end

  def auth_role_secret_key
    config[:auth_role_secret_key]
  end

  def endpoint_with_path
    URI.join(endpoint, 'v2?appkey=' + appkey).to_s
  end

  def generate_channel(prefix = 'ch-')
    prefix + (0...8).map { (65 + rand(26)).chr }.join
  end

  private

  def load_config
    path = File.expand_path(File.join(File.dirname(__FILE__), '..', 'credentials.json'))
    raise "credentials.json doesn't exist in #{path}" unless File.exist?(path)
    JSON.parse(File.read(path), symbolize_names: true)
  end
end

class QueueWithTimeout
  def initialize
    @mutex = Mutex.new
    @queue = []
    @recieved = ConditionVariable.new
  end

  def <<(x)
    @mutex.synchronize do
      @queue << x
      @recieved.signal
    end
  end

  def concat(xs)
    @mutex.synchronize do
      @queue.concat(xs)
      @recieved.signal
    end
  end

  # prohibit to pop without timeout in tests
  def pop(timeout = 15)
    pop_with_timeout(timeout)
  end

  def pop_with_timeout(timeout = nil)
    @mutex.synchronize do
      if @queue.empty?
        @recieved.wait(@mutex, timeout) if timeout != 0
        # if we're still empty after the timeout, raise exception
        raise ThreadError, 'queue is empty after the timeout' if @queue.empty?
      end
      @queue.shift
    end
  end

  def size
    @mutex.synchronize do
      @queue.size
    end
  end

  def empty?
    size == 0
  end

  def to_s
    @queue.inspect
  end
end

RSpec.configure do |config|
  Satori::RTM::Logger.use_std_logger(::Logger::DEBUG)
  config.include ConfigLoader
  config.filter_run focus: true
  config.run_all_when_everything_filtered = true
end
