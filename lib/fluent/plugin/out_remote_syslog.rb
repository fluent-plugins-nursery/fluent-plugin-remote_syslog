require "fluent/mixin/config_placeholders"
require "fluent/mixin/plaintextformatter"

module Fluent
  class RemoteSyslogOutput < Fluent::Output
    Fluent::Plugin.register_output("remote_syslog", self)

    config_param :hostname, :string, :default => ""

    include Fluent::Mixin::PlainTextFormatter
    include Fluent::Mixin::ConfigPlaceholders

    config_param :host, :string
    config_param :port, :integer, :default => 25

    config_param :facility, :string, :default => "user"
    config_param :severity, :string, :default => "notice"
    config_param :tag, :string, :default => "fluentd"

    def initialize
      super
      require "remote_syslog_logger"
    end

    def configure(conf)
      super
      @logger = RemoteSyslogLogger::UdpSender.new(@host,
                                                  @port,
                                                  facility: @facility,
                                                  severity: @severity,
                                                  program: @tag,
                                                  local_hostname: @hostname)
    end

    def shutdown
      super
      @logger.close if @logger
    end

    def emit(tag, es, chain)
      chain.next
      es.each do |time, record|
        @logger.transmit format(tag, time, record)
      end
    end
  end
end
