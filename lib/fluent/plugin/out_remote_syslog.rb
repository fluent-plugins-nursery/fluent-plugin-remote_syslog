require "fluent/mixin/config_placeholders"
require "fluent/mixin/plaintextformatter"
require 'fluent/mixin/rewrite_tag_name'

module Fluent
  class RemoteSyslogOutput < Fluent::BufferedOutput
    Fluent::Plugin.register_output("remote_syslog", self)

    config_param :hostname, :string, :default => ""

    include Fluent::Mixin::PlainTextFormatter
    include Fluent::Mixin::ConfigPlaceholders
    include Fluent::HandleTagNameMixin
    include Fluent::Mixin::RewriteTagName

    config_param :host, :string
    config_param :port, :integer, :default => 25

    config_param :facility, :string, :default => "user"
    config_param :severity, :string, :default => "notice"
    config_param :tag, :string, :default => "fluentd"

    config_param :protocol, :string, :default => "udp"
    config_param :tls, :bool, :default => false
    config_param :ca_file, :string, :default => nil
    config_param :verify_mode, :integer, default: nil

    config_param :keep_alive, :bool, :default => false
    config_param :keep_alive_idle, :integer, :default => nil
    config_param :keep_alive_cnt, :integer, :default => nil
    config_param :keep_alive_intvl, :integer, :default => nil

    config_set_default :flush_interval, 5

    def initialize
      super
      require "remote_syslog_logger"
      @loggers = {}
    end

    def shutdown
      super
      @loggers.each do |_, thread_loggers|
        thread_loggers.values.each(&:close)
      end
    end

    def format(tag, time, record)
      emit_tag = tag.dup
      filter_record(emit_tag, time, record)
      body = super(emit_tag, time, record)
      {"tag" => emit_tag, "body" => body}.to_msgpack
    end

    def write(chunk)
      chunk.msgpack_each do |data|
        loggers = (@loggers[Thread.current.object_id] ||= {})
        begin
          if @protocol == "tcp"
            options = {
              facility: @facility,
              severity: @severity,
              program: data["tag"],
              local_hostname: @hostname,
              tls: @tls,
              whinyerrors: true,
              keep_alive: @keep_alive,
              keep_alive_idle: @keep_alive_idle,
              keep_alive_cnt: @keep_alive_cnt,
              keep_alive_intvl: @keep_alive_intvl,
            }
            options[:ca_file] = @ca_file if @ca_file
            options[:verify_mode] = @verify_mode if @verify_mode
            loggers[data["tag"]] ||= RemoteSyslogLogger::TcpSender.new(
              @host,
              @port,
              options
            )
          else
            loggers[data["tag"]] ||= RemoteSyslogLogger::UdpSender.new(
              @host,
              @port,
              facility: @facility,
              severity: @severity,
              program: data["tag"],
              local_hostname: @hostname,
              whinyerrors: true,
            )
          end
          loggers[data["tag"]].transmit(data["body"])
        rescue
          loggers[data["tag"]] = nil
          raise
        end
      end
    end
  end
end
