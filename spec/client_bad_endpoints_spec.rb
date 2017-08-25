require 'spec_helper'

describe 'client with bad endpoints' do
  before(:each) do
    @old_logger = Satori::RTM::Logger.logger
    @events = QueueWithTimeout.new
    Satori::RTM::Logger.use_std_logger(::Logger::FATAL)
  end

  after(:each) do
    Satori::RTM::Logger.use_logger @old_logger
  end

  it 'should fail when endpoint has expired certificate' do
    client = Satori::RTM::Client.new('wss://expired.badssl.com/', appkey)
    client.onclose { |e| @events << e }
    expect { client.connect }.to raise_error Satori::RTM::ConnectionError

    expect(@events.size).to be > 0
    err = @events.pop
    expect(err.code).to eq 1006
    # don't check reason bcz it's different on YARV and JRuby
  end

  it 'should fail when endpoint has self-signed certificate' do
    client = Satori::RTM::Client.new('wss://self-signed.badssl.com/', appkey)
    client.onclose { |e| @events << e }
    expect { client.connect }.to raise_error Satori::RTM::ConnectionError

    expect(@events.size).to be > 0
    err = @events.pop
    expect(err.code).to eq 1006
    # don't check reason bcz it's different on YARV and JRuby
  end

  it 'should dont fail on ssl when endpoint has good certificate' do
    client = Satori::RTM::Client.new('wss://sha256.badssl.com/', appkey)
    client.onclose { |e| @events << e }
    expect { client.connect }.to raise_error Satori::RTM::ConnectionError

    expect(@events.size).to be > 0
    err = @events.pop
    expect(err.code).to eq 1006
    expect(err.reason).to include('invalid_status_code')
  end

  it 'should fail when connect to unknown host' do
    client = Satori::RTM::Client.new('wss://xxx.non-api-endpoint.satori.com/', appkey)
    client.onclose { |e| @events << e }
    expect { client.connect }.to raise_error Satori::RTM::ConnectionError

    expect(@events.size).to be > 0
    err = @events.pop
    expect(err.code).to eq 1006
    # don't check reason bcz it's different on YARV and JRuby
  end

  it 'should fail when connect with wrong appkeys' do
    client = Satori::RTM::Client.new(endpoint, appkey + 'x')
    client.onclose { |e| @events << e }
    expect { client.connect }.to raise_error Satori::RTM::ConnectionError

    expect(@events.size).to be > 0
    err = @events.pop
    expect(err.code).to eq 1006
    expect(err.reason).to include('invalid_status_code')
  end
end
