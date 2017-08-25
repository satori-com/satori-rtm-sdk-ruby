require 'spec_helper'

describe 'client read operations' do
  before(:each) do
    @client = Satori::RTM::Client.new(endpoint, appkey)
    @replies = QueueWithTimeout.new

    @channel = generate_channel
    @message = { who: 'zebra', where: [1, 2] }
  end

  after(:each) do
    @client.close
  end

  it 'should read async without blocking' do
    @client.connect
    @client.sock_read_nonblock

    @client.publish @channel, @message do |r|
      @replies << r
    end

    start = Time.now
    while @replies.empty? && Time.now - start < 5
      @client.sock_read_nonblock
      sleep 0.1
    end

    reply = @replies.pop
    expect(reply.success?).to be true
  end

  it 'should read without timeout correctly' do
    @client.connect

    @client.publish @channel, @message do |r|
      @replies << r
    end
    rc = @client.sock_read

    reply = @replies.pop
    expect(reply.success?).to be true
    expect(rc).to eq :ok
  end

  it 'should read with timeout correctly' do
    @client.connect

    start_ts = Time.now
    rc = @client.sock_read timeout_in_secs: 0.1
    end_ts = Time.now

    expect(@replies.size).to eq 0
    expect(end_ts - start_ts).to be_between(0.1, 0.2)
    expect(rc).to eq :timeout
  end

  it 'should read_for some time correctly' do
    @client.connect

    start_ts = Time.now
    @client.sock_read_repeatedly duration_in_secs: 0.1
    end_ts = Time.now

    expect(@replies.size).to eq 0
    expect(end_ts - start_ts).to be_between(0.1, 0.2)
  end

  context 'wait_all_replies' do
    it 'should wait replies with timeout correctly' do
      @client.connect

      @client.publish @channel, @message do |r|
        @replies << r
      end

      start_ts = Time.now
      rc = @client.wait_all_replies timeout_in_secs: 0
      end_ts = Time.now

      expect(@replies.size).to eq 0
      expect(rc).to eq :timeout
      expect(end_ts - start_ts).to be_between(0, 0.05)

      rc = @client.wait_all_replies

      reply = @replies.pop
      expect(rc).to eq :ok
      expect(reply.success?).to be true
    end

    it 'should return immediately if there are no pending requests' do
      @client.connect

      start_ts = Time.now
      rc = @client.wait_all_replies timeout_in_secs: 1
      end_ts = Time.now

      expect(@replies.size).to eq 0
      expect(rc).to eq :ok
      expect(end_ts - start_ts).to be_between(0, 50)
    end

    it 'should wait requests with timeout' do
      @client.connect

      @client.publish @channel, @message do |r|
        @replies << r
      end

      start_ts = Time.now
      rc = @client.wait_all_replies timeout_in_secs: 10
      end_ts = Time.now

      reply = @replies.pop
      expect(rc).to eq :ok
      expect(reply.success?).to be true
      expect(end_ts - start_ts).to be_between(0, 5)
    end
  end
end
