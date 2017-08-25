require 'spec_helper'

describe Satori::RTM::WebSocket do
  before(:each) do
    @transport = Satori::RTM::WebSocket.new
    @mailbox = []
    @transport.on :* do |*args|
      @mailbox << args
    end
    @messages = []
    @transport.on :message do |*args|
      @messages << args
    end
  end

  after(:each) do
    @transport.close
  end

  it 'should connect, send and close' do
    @transport.connect(endpoint_with_path)
    expect(@mailbox.shift).to eq [:open]
    @transport.send('ping', type: :ping)
    @transport.read_with_timeout(10)

    (name, data) = @mailbox.shift
    expect(name).to eq :pong
    expect(data).to eq 'ping'

    @transport.close
    expect(@mailbox.shift).to eq [:close, 1000, nil]
  end

  it 'should raise exception when do operation on closed socket' do
    @transport.connect(endpoint_with_path)
    expect(@mailbox.shift).to eq [:open]

    @transport.close
    expect(@mailbox.shift).to eq [:close, 1000, nil]

    expect { @transport.send('ping', type: :ping) }.to raise_error Satori::RTM::ConnectionError
    expect { @transport.read }.to raise_error Satori::RTM::ConnectionError
    expect { @transport.read_nonblock }.to raise_error Satori::RTM::ConnectionError
    expect { @transport.read_with_timeout(1) }.to raise_error Satori::RTM::ConnectionError
  end

  it 'should raise exception when connection is not established' do
    expect { @transport.send('ping', type: :ping) }.to raise_error Satori::RTM::ConnectionError
    expect { @transport.read }.to raise_error Satori::RTM::ConnectionError
    expect { @transport.read_nonblock }.to raise_error Satori::RTM::ConnectionError
    expect { @transport.read_with_timeout(1) }.to raise_error Satori::RTM::ConnectionError
  end

  it 'should send and receive text frames' do
    @transport.connect(endpoint_with_path)

    pdu = JSON.generate(
      action: 'rtm/publish',
      id: 0,
      body: {
        channel: 'channel',
        message: 'hello world'
      }
    )
    @transport.send(pdu, type: :text)
    @transport.read

    (text, type) = @messages.shift
    expect(type).to eq :text
    json = JSON.parse(text, symbolize_names: true)
    expect(json[:action]).to eq 'rtm/publish/ok'
  end
end
