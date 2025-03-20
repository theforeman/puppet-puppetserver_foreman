# Puppet module for managing Foreman integration in Puppetserver

The Foreman integration consists of an ENC and a report processor. This has a
configuration file. All of this can be managed by this module.

Historically this integration was part of [theforeman-foreman
module](https://github.com/theforeman/puppet-foreman).

## Compatibility

* Foreman API v2: 1.3 - 3.x
* Puppetserver: 1.x - 7.x

These scripts have a long history and have basically been unchanged since Puppet 2.6, even before Puppetserver existed.
They have been adopted to leverage some more modern Ruby methods and require at least Ruby 2.7, but can probably still handle old reports.
