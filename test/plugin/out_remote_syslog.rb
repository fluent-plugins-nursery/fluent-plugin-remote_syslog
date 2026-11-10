require "test_helper"
require "fluent/plugin/out_remote_syslog"
require "fluent/plugin/in_syslog"
require 'fluent/test/driver/input'

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

    now = Time.now.to_i
    times = [now - 600, now - 300]

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
