# fluent-plugin-remote_syslog

[![Build Status](https://travis-ci.org/dlackty/fluent-plugin-remote_syslog.svg?branch=master)](https://travis-ci.org/dlackty/fluent-plugin-remote_syslog)

[Fluentd](http://fluentd.org) plugin for output to remote syslog serivce (e.g. [Papertrail](http://papertrailapp.com/))

## Requirements

| fluent-plugin-remote_syslog | fluentd    | ruby   |
| -------------------         | ---------  | ------ |
| >= 1.0.0                    | >= v0.14.0 | >= 2.1 |
| < 1.0.0                     | >= v0.12.0 | >= 1.9 |

## Installation

```bash
 fluent-gem install fluent-plugin-remote_syslog
```

## Usage

```
<match foo.bar>
  @type remote_syslog
  host example.com
  port 514
  severity debug
  program fluentd
  hostname ${tag[1]}

  <buffer tag>
  </buffer>
</match>
```

## License

Copyright (c) 2014-2017 Richard Lee. See LICENSE for details.
