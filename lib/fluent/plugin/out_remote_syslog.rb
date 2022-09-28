require "remote_syslog_sender"

module Fluent
  module Plugin
    class RemoteSyslogOutput < Output
      Fluent::Plugin.register_output("remote_syslog", self)

      helpers :formatter, :inject

      config_param :hostname, :string, :default => ""

      config_param :host, :string, :default => nil
      config_param :port, :integer, :default => 514
      config_param :host_with_port, :string, :default => nil

      config_param :facility, :string, :default => "user"
      config_param :severity, :string, :default => "notice"
      config_param :program, :string, :default => "fluentd"

      config_param :protocol, :enum, list: [:udp, :tcp], :default => :udp
      config_param :tls, :bool, :default => false
      config_param :ca_file, :string, :default => nil
      config_param :verify_mode, :integer, default: nil
      config_param :packet_size, :size, default: 1024
      config_param :timeout, :time, default: nil
      config_param :timeout_exception, :bool, default: false

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

      config_section :format do
        config_set_default :@type, 'ltsv'
      end

      def initialize
        super
      end

      def configure(conf)
        super
        if @host.nil? && @host_with_port.nil?
          raise ConfigError, "host or host_with_port is required"
        end

        @formatter = formatter_create
        unless @formatter.formatter_type == :text_per_line
          raise ConfigError, "formatter_type must be text_per_line formatter"
        end

        validate_target = "host=#{@host}/host_with_port=#{@host_with_port}/hostname=#{@hostname}/facility=#{@facility}/severity=#{@severity}/program=#{@program}"
        placeholder_validate!(:remote_syslog, validate_target)
        @senders = []
      end

      def multi_workers_ready?
        true
      end

      def close
        super
        @senders.each { |s| s.close if s }
        @senders.clear
      end

      def format(tag, time, record)
        r = inject_values_to_record(tag, time, record)
        @formatter.format(tag, time, r)
      end

      def write(chunk)
        return if chunk.empty?

        host = extract_placeholders(@host, chunk.metadata)
        port = @port

        if @host_with_port
          host, port = extract_placeholders(@host_with_port, chunk.metadata).split(":")
        end

        host_with_port = "#{host}:#{port}"

        Thread.current[host_with_port] ||= create_sender(host, port)
        sender = Thread.current[host_with_port]

        facility = extract_placeholders(@facility, chunk.metadata)
        severity = extract_placeholders(@severity, chunk.metadata)
        program = extract_placeholders(@program, chunk.metadata)
        hostname = extract_placeholders(@hostname, chunk.metadata)

        severity = SeverityMapper.map(severity)

        packet_options = {facility: facility, severity: severity, program: program}
        packet_options[:hostname] = hostname unless hostname.empty?

        begin
          chunk.open do |io|
            io.each_line do |msg|
              sender.transmit(msg.chomp!, packet_options)
            end
          end
        rescue
          if Thread.current[host_with_port]
            Thread.current[host_with_port].close
            @senders.delete(Thread.current[host_with_port])
            Thread.current[host_with_port] = nil
          end
          raise
        end
      end

      private

      def create_sender(host, port)
        if @protocol == :tcp
          options = {
            tls: @tls,
            whinyerrors: true,
            packet_size: @packet_size,
            timeout: @timeout,
            timeout_exception: @timeout_exception,
            keep_alive: @keep_alive,
            keep_alive_idle: @keep_alive_idle,
            keep_alive_cnt: @keep_alive_cnt,
            keep_alive_intvl: @keep_alive_intvl,
            program: @program,
          }
          options[:ca_file] = @ca_file if @ca_file
          options[:verify_mode] = @verify_mode if @verify_mode
          sender = RemoteSyslogSender::TcpSender.new(
            host,
            port,
            options
          )
        else
          sender = RemoteSyslogSender::UdpSender.new(
            host,
            port,
            whinyerrors: true,
            program: @program,
            packet_size: @packet_size,
          )
        end
        @senders << sender
        sender
      end

      # Convert some Severity values that is not supported in `syslog_protocol` library:
      #   https://github.com/eric/syslog_protocol
      # We want to fix `syslog_protocol` itself, but it seems to be not maintained for a while.
      # If the following PR is merged, we can remove this implementaion.
      #   https://github.com/eric/syslog_protocol/pull/9
      module SeverityMapper
        DICT = {
          # "warning" is not supported, but we should use it since "warn" is deprecated.
          "warning" => "warn", 
        }

        def self.map(severity)
          DICT[severity] || severity
        end
      end
    end
  end
end
