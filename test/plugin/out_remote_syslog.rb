require "test_helper"
require "fluent/plugin/out_remote_syslog"

class RemoteSyslogOutputTest < Test::Unit::TestCase
  def setup
    super
    Fluent::Test.setup
  end

  CONFIG = %[
    type remote_syslog
    hostname foo.com
    host example.com
    port 5566
    severity debug
    tag testunit
  ]

  def create_driver(conf = CONFIG)
    Fluent::Test::OutputTestDriver.new(Fluent::RemoteSyslogOutput) {}.configure(conf)
  end

  def test_configure
    d = create_driver
    logger = d.instance.instance_variable_get(:@logger)

    assert_not_nil logger
    assert_equal "example.com", logger.instance_variable_get(:@remote_hostname)
    assert_equal 5566, logger.instance_variable_get(:@remote_port)
    p = logger.instance_variable_get(:@packet)
    assert_equal "foo.com", p.hostname
    assert_equal 1, p.facility
    assert_equal "testunit", p.tag
    assert_equal 7, p.severity
  end
end
