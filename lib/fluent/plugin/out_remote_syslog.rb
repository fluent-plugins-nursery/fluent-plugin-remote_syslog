require "fluent/mixin/config_placeholders"
require "fluent/mixin/plaintextformatter"

module Fluent
  module Plugin
    class RemoteSyslogOutput < Output
      Fluent::Plugin.register_output("remote_syslog", self)

      config_param :hostname, :string, :default => ""

      include Fluent::Mixin::PlainTextFormatter
      include Fluent::Mixin::ConfigPlaceholders

      config_param :host, :string, :default => nil
      config_param :port, :integer, :default => 25
      config_param :host_with_port, :string, :default => nil

      config_param :facility, :string, :default => "user"
      config_param :severity, :string, :default => "notice"
      config_param :program, :string, :default => "fluentd"

      config_param :protocol, :string, :default => "udp"
      config_param :tls, :bool, :default => false
      config_param :ca_file, :string, :default => nil
      config_param :verify_mode, :integer, default: nil

      config_param :keep_alive, :bool, :default => false
      config_param :keep_alive_idle, :integer, :default => nil
      config_param :keep_alive_cnt, :integer, :default => nil
      config_param :keep_alive_intvl, :integer, :default => nil

      config_section :buffer do
        config_set_default :flush_mode, :interval
        config_set_default :flush_interval, 5
        config_set_default :flush_thread_interval, 0.5
        config_set_default :flush_thread_burst_interval, 0.5
      end

      def initialize
        super
        require "remote_syslog_logger"
        @loggers = {}
      end

      def configure(conf)
        super
        if @host.nil? && @host_with_port.nil?
          raise ConfigError, "host or host_with_port is required"
        end

        validate_target = "host=#{@host}/host_with_port=#{@host_with_port}/facility=#{@facility}/severity=#{@severity}/program=#{@program}"
        placeholder_validate!(:remote_syslog, validate_target)
      end

      def format(tag, time, record)
        emit_tag = tag.dup
        body = super(emit_tag, time, record)
        {"body" => body}.to_msgpack
      end

      def formatted_to_msgpack_binary
        true
      end

      def write(chunk)
        host = extract_placeholders(@host, chunk.metadata)
        port = @port
        if @host_with_port
          host, port = extract_placeholders(@host_with_port, chunk.metadata).split(":")
        end
        facility = extract_placeholders(@facility, chunk.metadata)
        severity = extract_placeholders(@severity, chunk.metadata)
        program = extract_placeholders(@program, chunk.metadata)

        if @protocol == "tcp"
          options = {
            facility: facility,
            severity: severity,
            program: program,
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
          logger = RemoteSyslogLogger::TcpSender.new(
            host,
            port,
            options
          )
        else
          logger = RemoteSyslogLogger::UdpSender.new(
            host,
            port,
            facility: facility,
            severity: severity,
            program: program,
            local_hostname: @hostname,
            whinyerrors: true,
          )
        end

        chunk.each do |data|
          logger.transmit(data["body"])
        end
      ensure
        logger.close
      end
    end
  end
end
