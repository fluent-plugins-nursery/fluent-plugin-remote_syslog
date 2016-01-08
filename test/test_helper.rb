$LOAD_PATH.unshift(File.join(File.dirname(__FILE__), "..", "lib"))
$LOAD_PATH.unshift(File.dirname(__FILE__))

require "minitest/autorun"
require "minitest/unit"
require "minitest/pride"
require "fluent/test"
