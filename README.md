# fluent-plugin-remote_syslog

[![Build Status](https://travis-ci.org/dlackty/fluent-plugin-remote_syslog.svg?branch=master)](https://travis-ci.org/dlackty/fluent-plugin-remote_syslog)

[Fluentd](http://fluentd.org) plugin for output to remote syslog serivce (e.g. [Papertrail](http://papertrailapp.com/))

## Installation

```bash
 fluent-gem install fluent-plugin-remote_syslog
```

## Usage

```
<match foo>
  type remote_syslog
  host example.com
  port 514
  severity debug
  tag fluentd
</match>
```

This plugin makes use of [Fluent::Mixin::PlainTextFormatter](https://github.com/tagomoris/fluent-mixin-plaintextformatter) and [Fluent::Mixin::RewriteTagName](https://github.com/y-ken/fluent-mixin-rewrite-tag-name), please check out their documentations for more configuration options.

## License

Copyright (c) 2014-2015 Richard Lee. See LICENSE for details.
