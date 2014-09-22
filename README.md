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
  remote_hostname example.com
  port 25
  key_name message
  severity debug
  program fluentd
</match>
```

## License

Copyright (c) 2014 Richard Lee. See LICENSE for details.
