require 'spec_helper'
require 'openssl'
require 'erb'

describe 'Client - TLS spec' do

  context 'when server requires TLS and no auth needed' do
    before(:each) do
      opts = {
        'pid_file' => '/tmp/test-nats-4444.pid',
        'host' => '127.0.0.1',
        'port' => 4444
      }
      config = ERB.new(%Q(
        net:  "<%= opts['host'] %>"
        port: <%= opts['port'] %>

        tls {
          cert_file:  "./spec/configs/certs/server.pem"
          key_file:   "./spec/configs/certs/key.pem"
          timeout:    10

          <% if RUBY_PLATFORM == "java" %>
          # JRuby is sensible to the ciphers being used
          # so we specify the ones that are available on it here.
          # See: https://github.com/jruby/jruby/issues/1738
          cipher_suites: [
            "TLS_ECDHE_RSA_WITH_AES_128_GCM_SHA256",
            "TLS_ECDHE_RSA_WITH_AES_128_CBC_SHA",
            "TLS_ECDHE_RSA_WITH_AES_256_CBC_SHA",
            "TLS_RSA_WITH_AES_128_CBC_SHA",
            "TLS_RSA_WITH_AES_256_CBC_SHA",
            "TLS_RSA_WITH_3DES_EDE_CBC_SHA"
          ]
          <% end %>
      }))
      @tls_no_auth = NatsServerControl.init_with_config_from_string(config.result(binding), opts)
      @tls_no_auth.start_server
    end

    after(:each) do
      @tls_no_auth.kill_server
    end

    it 'should error if client does not set secure connection and server requires it' do
      errors = []
      closes = 0
      reconnects = 0
      disconnects = 0
      reconnects = 0

      nats = NATS::IO::Client.new
      nats.on_close      { closes += 1 }
      nats.on_reconnect  { reconnects += 1 }
      nats.on_disconnect { disconnects += 1 }
      nats.on_error do |e|
        errors << e
      end

      expect do
        nats.connect(:servers => ['nats://127.0.0.1:4444'], :reconnect => false)
      end.to raise_error(NATS::IO::ConnectError)

      # No async errors, only synchronous error of disconnection failing
      expect(errors.count).to eql(0)

      # No close since we were not even connected
      expect(closes).to eql(0)
      expect(reconnects).to eql(0)
      expect(disconnects).to eql(1)
    end

    it 'should allow to connect client with secure connection if server requires it' do
      errors = []
      closes = 0
      reconnects = 0
      disconnects = 0
      reconnects = 0

      nats = NATS::IO::Client.new
      nats.on_close      { closes += 1 }
      nats.on_reconnect  { reconnects += 1 }
      nats.on_disconnect { disconnects += 1 }
      nats.on_error do |e|
        errors << e
      end

      expect do
        nats.connect(:servers => ['tls://127.0.0.1:4444'], :reconnect => false)
      end.to_not raise_error

      # Confirm basic secure publishing works
      msgs = []
      nats.subscribe("hello.*") do |msg|
        msgs << msg
      end
      nats.flush

      # Send some messages...
      100.times {|n| nats.publish("hello.#{n}", "world") }
      nats.flush
      sleep 0.5

      # Gracefully disconnect
      nats.close

      # Should have published 100 messages without errors
      expect(msgs.count).to eql(100)
      expect(errors.count).to eql(0)
      expect(closes).to eql(1)
      expect(reconnects).to eql(0)
      expect(disconnects).to eql(1)
    end

    it 'should allow custom secure connection contexts' do
      errors = []
      closes = 0
      reconnects = 0
      disconnects = 0
      reconnects = 0

      nats = NATS::IO::Client.new
      nats.on_close      { closes += 1 }
      nats.on_reconnect  { reconnects += 1 }
      nats.on_disconnect { disconnects += 1 }
      nats.on_error do |e|
        errors << e
      end

      expect do
        tls_context = OpenSSL::SSL::SSLContext.new
        tls_context.ssl_version = :SSLv3
        tls_context

        nats.connect({
         servers: ['tls://127.0.0.1:4444'],
         reconnect: false,
         tls: {
           context: tls_context
         }
        })
      end.to raise_error(OpenSSL::SSL::SSLError)
    end
  end
end
