require "test_helper"
require "fluent/plugin/out_remote_syslog"

class RemoteSyslogOutputTest < MiniTest::Unit::TestCase
  def setup
    Fluent::Test.setup
  end

  def create_driver(conf = CONFIG, tag = "test.remote_syslog")
    Fluent::Test::OutputTestDriver.new(Fluent::RemoteSyslogOutput, tag) {}.configure(conf)
  end

  def test_configure
    d = create_driver %[
      type remote_syslog
      hostname foo.com
      host example.com
      port 5566
      severity debug
      tag minitest
    ]

    d.run do
      d.emit(message: "foo")
    end

    loggers = d.instance.instance_variable_get(:@loggers)
    refute_empty loggers

    logger = loggers.values.first

    assert_equal "example.com", logger.instance_variable_get(:@remote_hostname)
    assert_equal 5566, logger.instance_variable_get(:@remote_port)

    p = logger.instance_variable_get(:@packet)
    assert_equal "foo.com", p.hostname
    assert_equal 1, p.facility
    assert_equal "minitest", p.tag
    assert_equal 7, p.severity
  end

  def test_rewrite_tag
    d = create_driver %[
      type remote_syslog
      hostname foo.com
      host example.com
      port 5566
      severity debug
      tag rewrited.${tag_parts[1]}
    ]

    d.run do
      d.emit(message: "foo")
    end

    loggers = d.instance.instance_variable_get(:@loggers)
    logger = loggers.values.first

    p = logger.instance_variable_get(:@packet)
    assert_equal "rewrited.remote_syslog", p.tag
  end

  def test_program_from_record
    d = create_driver %[
      type remote_syslog
      hostname foo.com
      host example.com
      port 5566
      severity debug
      tag orignal
    ]

    d.run do
      d.emit('message' => "foo", 'program' => 'record_based_program')
    end

    loggers = d.instance.instance_variable_get(:@loggers)
    logger = loggers.values.first

    packet = logger.instance_variable_get(:@packet)
    assert_equal "record_based_program", packet.tag
  end

  def test_hostname_from_record
    d = create_driver %[
      type remote_syslog
      hostname foo.com
      host example.com
      port 5566
      severity debug
      tag orignal
    ]

    d.run do
      d.emit('message' => "foo", 'local_hostname' => 'host.name')
    end

    loggers = d.instance.instance_variable_get(:@loggers)
    logger = loggers.values.first

    packet = logger.instance_variable_get(:@packet)
    assert_equal "host.name", packet.hostname
  end
end
