require "test_helper"
require "fluent/plugin/out_remote_syslog"
require "fluent/plugin/in_syslog"
require 'fluent/test/driver/input'

require "socket"

# Returns nil for the "skip" message, like a custom formatter that drops a record.
class RemoteSyslogTestSkippingFormatter < Fluent::Plugin::SingleValueFormatter
  Fluent::Plugin.register_formatter("remote_syslog_test_skipping", self)

  def format(tag, time, record)
    return nil if record["message"] == "skip"
    super
  end
end

class RemoteSyslogOutputTest < Test::Unit::TestCase
  def setup
    Fluent::Test.setup
  end

  def create_driver_out_syslog(conf)
    Fluent::Test::Driver::Output.new(Fluent::Plugin::RemoteSyslogOutput).configure(conf)
  end

  def create_driver_in_syslog(conf)
    Fluent::Test::Driver::Input.new(Fluent::Plugin::SyslogInput).configure(conf)
  end

  def test_configure
    d = create_driver_out_syslog %[
      @type remote_syslog
      hostname foo.com
      host example.com
      port 5566
      severity debug
      program minitest
    ]

    loggers = d.instance.instance_variable_get(:@senders)
    assert_equal loggers, []

    assert_equal "example.com", d.instance.instance_variable_get(:@host)
    assert_equal 5566, d.instance.instance_variable_get(:@port)
    assert_equal "debug", d.instance.instance_variable_get(:@severity)
  end

  data("debug", {severity: "debug"})
  data("warn", {severity: "warn"})
  data("warning", {severity: "warning", expected_severity: "warn"})
  def test_write_udp(data)
    out_driver = create_driver_out_syslog %[
      @type remote_syslog
      hostname foo.com
      host localhost
      port 5566
      severity #{data[:severity]}
      program minitest

      <format>
        @type single_value
        message_key message
      </format>
    ]

    in_driver = create_driver_in_syslog %[
      @type syslog
      tag tag
      port 5566
      bind 127.0.0.1
    ]

    in_driver.run(expect_records: 1, timeout: 5) do
      out_driver.run do
        out_driver.feed("tag", Fluent::EventTime.now, {"message" => "This is a test message."})
      end
    end

    assert_equal 1, in_driver.events.length

    tag, _, msg = in_driver.events[0]

    expected_facility = "user"
    expected_severity = data[:expected_severity] || data[:severity]
    assert_equal("tag.#{expected_facility}.#{expected_severity}", tag)
    assert_equal("foo.com", msg["host"])
    assert_equal("minitest", msg["ident"])
    assert_equal("This is a test message.", msg["message"])
  end

  data("debug", {severity: "debug"})
  data("warn", {severity: "warn"})
  data("warning", {severity: "warning", expected_severity: "warn"})
  def test_write_tcp(data)
    out_driver = create_driver_out_syslog %[
      @type remote_syslog
      hostname foo.com
      host localhost
      port 5566
      severity #{data[:severity]}
      program minitest

      protocol tcp

      <format>
        @type single_value
        message_key message
      </format>
    ]

    in_driver = create_driver_in_syslog %[
      @type syslog
      tag tag
      port 5566
      bind 127.0.0.1
      protocol_type tcp
    ]

    in_driver.run(expect_records: 1, timeout: 5) do
      out_driver.run do
        out_driver.feed("tag", Fluent::EventTime.now, {"message" => "This is a test message."})
      end
    end

    assert_equal 1, in_driver.events.length

    tag, _, msg = in_driver.events[0]

    expected_facility = "user"
    expected_severity = data[:expected_severity] || data[:severity]
    assert_equal("tag.#{expected_facility}.#{expected_severity}", tag)
    assert_equal("foo.com", msg["host"])
    assert_equal("minitest", msg["ident"])
    assert_equal("This is a test message.", msg["message"])
  end

  data("udp", {protocol: "udp"})
  data("tcp", {protocol: "tcp"})
  def test_write_with_use_event_time(data)
    out_driver = create_driver_out_syslog %[
      @type remote_syslog
      hostname foo.com
      host localhost
      port 5566
      program minitest
      protocol #{data[:protocol]}
      use_event_time true

      <format>
        @type single_value
        message_key message
      </format>
    ]

    in_driver = create_driver_in_syslog %[
      @type syslog
      tag tag
      port 5566
      bind 127.0.0.1
      protocol_type #{data[:protocol]}
    ]

    # RFC 3164 has no year and in_syslog uses the current one, so the times
    # must not cross a year boundary.
    base = Time.local(Time.now.year, 1, 2, 12).to_i
    times = [base, base + 300]

    in_driver.run(expect_records: 2, timeout: 5) do
      out_driver.run do
        times.each_with_index do |time, i|
          out_driver.feed("tag", Fluent::EventTime.new(time), {"message" => "message #{i}"})
        end
      end
    end

    events = in_driver.events.sort_by { |_, _, record| record["message"] }
    assert_equal(["message 0", "message 1"], events.map { |_, _, record| record["message"] })
    assert_equal(times, events.map { |_, time, _| time.to_i })
  end

  # Sends the records over UDP with use_event_time and returns the messages
  # of the raw packets, without the syslog header.
  def send_with_use_event_time(records, format_type: "single_value")
    out_driver = create_driver_out_syslog %[
      @type remote_syslog
      hostname foo.com
      host 127.0.0.1
      port 5566
      program minitest
      protocol udp
      use_event_time true

      <format>
        @type #{format_type}
        message_key message
      </format>
    ]

    socket = UDPSocket.new
    socket.bind("127.0.0.1", 5566)
    begin
      out_driver.run do
        records.each {|record| out_driver.feed("tag", Fluent::EventTime.now, record) }
      end
      packets = []
      while IO.select([socket], nil, nil, 1)
        packets << socket.recvfrom(4096)[0]
      end
      packets.map {|packet| packet.b.split("minitest: ".b, 2)[1] }
    ensure
      socket.close
    end
  end

  data("invalid UTF-8", "bad \xFF byte".dup.force_encoding("UTF-8"))
  data("ISO-8859-1", "caf\xE9".dup.force_encoding("ISO-8859-1"))
  data("broken Windows-31J", "bad \x82".dup.force_encoding("Windows-31J"))
  def test_write_with_use_event_time_keeps_message_bytes(message)
    messages = send_with_use_event_time([{"message" => message}, {"message" => "valid"}])
    assert_equal([message.b, "valid".b], messages)
  end

  def test_write_with_use_event_time_skips_nil_formatted_record
    records = [{"message" => "first"}, {"message" => "skip"}, {"message" => "last"}]
    messages = send_with_use_event_time(records, format_type: "remote_syslog_test_skipping")
    assert_equal(["first".b, "last".b], messages)
  end

  data("primary true, secondary omitted", ["use_event_time true", ""])
  data("primary false, secondary true", ["", "use_event_time true"])
  def test_configure_rejects_secondary_with_other_use_event_time(data)
    primary, secondary = data
    assert_raise(Fluent::ConfigError.new("use_event_time in <secondary> must be the same as in the primary")) do
      create_driver_out_syslog %[
        @type remote_syslog
        host primary.example.com
        #{primary}
        <secondary>
          @type remote_syslog
          host backup.example.com
          #{secondary}
        </secondary>
      ]
    end
  end

  data("true and true", ["use_event_time true", "use_event_time true"])
  data("false and false", ["use_event_time false", ""])
  def test_configure_accepts_secondary_with_same_use_event_time(data)
    primary, secondary = data
    d = create_driver_out_syslog %[
      @type remote_syslog
      host primary.example.com
      #{primary}
      <secondary>
        @type remote_syslog
        host backup.example.com
        #{secondary}
      </secondary>
    ]
    assert_equal(d.instance.use_event_time, d.instance.instance_variable_get(:@secondary).use_event_time)
  end

  def test_configure_accepts_secondary_file_with_use_event_time
    d = create_driver_out_syslog %[
      @type remote_syslog
      host primary.example.com
      use_event_time true
      <secondary>
        @type secondary_file
        directory /tmp/remote_syslog_secondary
      </secondary>
    ]
    assert_kind_of(Fluent::Plugin::SecondaryFileOutput, d.instance.instance_variable_get(:@secondary))
  end

  def test_write_without_use_event_time_sends_current_time
    out_driver = create_driver_out_syslog %[
      @type remote_syslog
      hostname foo.com
      host localhost
      port 5566
      program minitest
      protocol tcp

      <format>
        @type single_value
        message_key message
      </format>
    ]

    in_driver = create_driver_in_syslog %[
      @type syslog
      tag tag
      port 5566
      bind 127.0.0.1
      protocol_type tcp
    ]

    event_time = Time.now.to_i - 600

    in_driver.run(expect_records: 1, timeout: 5) do
      out_driver.run do
        out_driver.feed("tag", Fluent::EventTime.new(event_time), {"message" => "message"})
      end
    end

    _, time, _ = in_driver.events[0]
    assert_operator(time.to_i, :>=, event_time + 600)
  end

  data("ipv4", {value: "127.0.0.1:514", host: "127.0.0.1", port: "514"})
  data("ipv4 with trailing colon", {value: "127.0.0.1:514:", host: "127.0.0.1", port: "514"})
  data("ipv4 with extra field", {value: "127.0.0.1:514:extra", host: "127.0.0.1", port: "514"})
  data("ipv6", {value: "[2001:db8::1]:514", host: "2001:db8::1", port: "514"})
  def test_split_host_with_port(data)
    d = create_driver_out_syslog %[
      @type remote_syslog
      host_with_port "#{data[:value]}"
    ]

    host, port = d.instance.send(:split_host_with_port, data[:value])
    assert_equal(data[:host], host)
    assert_equal(data[:port], port)
  end

  data("ipv4", {host_with_port: "127.0.0.1:5567", bind: "127.0.0.1"})
  data("ipv6", {host_with_port: "[::1]:5567", bind: "::1"})
  def test_write_tcp_with_host_with_port(data)
    out_driver = create_driver_out_syslog %[
      @type remote_syslog
      hostname foo.com
      host_with_port "#{data[:host_with_port]}"
      program minitest

      protocol tcp

      <format>
        @type single_value
        message_key message
      </format>
    ]

    in_driver = create_driver_in_syslog %[
      @type syslog
      tag tag
      port 5567
      bind #{data[:bind]}
      protocol_type tcp
    ]

    in_driver.run(expect_records: 1, timeout: 5) do
      out_driver.run do
        out_driver.feed("tag", Fluent::EventTime.now, {"message" => "This is a test message."})
      end
    end

    assert_equal 1, in_driver.events.length
    _, _, msg = in_driver.events[0]
    assert_equal("This is a test message.", msg["message"])
  end

  data("emerg", {in: "emerg", out: "emerg"})
  data("alert", {in: "alert", out: "alert"})
  data("crit", {in: "crit", out: "crit"})
  data("err", {in: "err", out: "err"})
  data("warn", {in: "warn", out: "warn"})
  data("warning", {in: "warning", out: "warn"})
  data("notice", {in: "notice", out: "notice"})
  data("info", {in: "info", out: "info"})
  data("debug", {in: "debug", out: "debug"})
  data("wrong", {in: "wrong", out: "wrong"})
  def test_severity_mapper(data)
    out = Fluent::Plugin::RemoteSyslogOutput::SeverityMapper.map(data[:in])
    assert_equal(data[:out], out)
  end
end
