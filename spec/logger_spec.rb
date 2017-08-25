require 'spec_helper'

describe Satori::RTM::Logger do
  class A
    include Satori::RTM::Logger
  end

  class B
    include Satori::RTM::Logger
  end

  before(:each) do
    ENV.delete(Satori::RTM::Logger::ENV_FLAG)
  end

  after(:each) do
    ENV.delete(Satori::RTM::Logger::ENV_FLAG)
  end

  it 'should use same logger instance for sevaral classes' do
    a = A.new
    b = B.new
    logger = a.logger
    expect(a.logger).to be b.logger

    Satori::RTM::Logger.use_std_logger(::Logger::WARN)
    new_logger = a.logger
    expect(a.logger).to be b.logger
    expect(logger).to_not be new_logger
  end

  it 'should change default level if ENV is specified' do
    expect(Satori::RTM::Logger.default_level).to be ::Logger::WARN
    ENV[Satori::RTM::Logger::ENV_FLAG] = 'yes'
    expect(Satori::RTM::Logger.default_level).to be ::Logger::DEBUG
  end

  it 'should log exceptions' do
    buff = StringIO.new
    logger = Satori::RTM::Logger.use_std_logger(::Logger::DEBUG, buff)
    logger.error(IOError.new('foobar'))
    str = buff.string
    expect(str).to include 'foobar'
    expect(str).to include 'IOError'
  end

  it 'should log any object' do
    buff = StringIO.new
    logger = Satori::RTM::Logger.use_std_logger(::Logger::DEBUG, buff)
    logger.error([1])
    expect(buff.string).to include '[1]'

    logger.error('foobar')
    expect(buff.string).to include 'foobar'
  end
end
