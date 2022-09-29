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
