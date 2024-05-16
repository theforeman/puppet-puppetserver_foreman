# Changelog

## [4.0.0](https://github.com/theforeman/puppet-puppetserver_foreman/tree/4.0.0) (2024-05-16)

[Full Changelog](https://github.com/theforeman/puppet-puppetserver_foreman/compare/3.1.0...4.0.0)

**Breaking changes:**

- Use namespaced ensure\_packages, require puppetlabs/stdlib 9.x [\#44](https://github.com/theforeman/puppet-puppetserver_foreman/pull/44) ([gcoxmoz](https://github.com/gcoxmoz))

**Fixed bugs:**

- Fix Deprecation-Warning [\#46](https://github.com/theforeman/puppet-puppetserver_foreman/pull/46) ([cocker-cc](https://github.com/cocker-cc))

## [3.1.0](https://github.com/theforeman/puppet-puppetserver_foreman/tree/3.1.0) (2024-03-26)

[Full Changelog](https://github.com/theforeman/puppet-puppetserver_foreman/compare/3.0.0...3.1.0)

**Implemented enhancements:**

- Add support for Debian 11 and 12 [\#42](https://github.com/theforeman/puppet-puppetserver_foreman/pull/42) ([evgeni](https://github.com/evgeni))
- Add Ubuntu 20.04 and 22.04 support [\#41](https://github.com/theforeman/puppet-puppetserver_foreman/pull/41) ([evgeni](https://github.com/evgeni))
- Prepare for Ruby 3. Replace File.exists? with File.exist? [\#40](https://github.com/theforeman/puppet-puppetserver_foreman/pull/40) ([tuxmea](https://github.com/tuxmea))
- Make TLS authentication to foreman optional [\#39](https://github.com/theforeman/puppet-puppetserver_foreman/pull/39) ([bastelfreak](https://github.com/bastelfreak))

## [3.0.0](https://github.com/theforeman/puppet-puppetserver_foreman/tree/3.0.0) (2023-11-14)

[Full Changelog](https://github.com/theforeman/puppet-puppetserver_foreman/compare/2.4.0...3.0.0)

**Breaking changes:**

- Drop Puppet 6 support [\#37](https://github.com/theforeman/puppet-puppetserver_foreman/pull/37) ([ekohl](https://github.com/ekohl))

**Implemented enhancements:**

- Add Puppet 8 support [\#34](https://github.com/theforeman/puppet-puppetserver_foreman/pull/34) ([bastelfreak](https://github.com/bastelfreak))
- Use YAML.safe\_load [\#27](https://github.com/theforeman/puppet-puppetserver_foreman/pull/27) ([ekohl](https://github.com/ekohl))

## [2.4.0](https://github.com/theforeman/puppet-puppetserver_foreman/tree/2.4.0) (2023-08-16)

[Full Changelog](https://github.com/theforeman/puppet-puppetserver_foreman/compare/2.3.0...2.4.0)

**Implemented enhancements:**

- puppetlabs/stdlib: Allow 9.x [\#33](https://github.com/theforeman/puppet-puppetserver_foreman/pull/33) ([bastelfreak](https://github.com/bastelfreak))
- Fixes [\#36573](https://projects.theforeman.org/issues/36573) - Reuse foreman\_url answer from foreman\_proxy module [\#31](https://github.com/theforeman/puppet-puppetserver_foreman/pull/31) ([ekohl](https://github.com/ekohl))

## [2.3.0](https://github.com/theforeman/puppet-puppetserver_foreman/tree/2.3.0) (2023-06-20)

[Full Changelog](https://github.com/theforeman/puppet-puppetserver_foreman/compare/2.2.0...2.3.0)

**Implemented enhancements:**

- Refs [\#35833](https://projects.theforeman.org/issues/35833) - Revert "Fixes [\#35684](https://projects.theforeman.org/issues/35684) - Drop Applied catalog lines" [\#29](https://github.com/theforeman/puppet-puppetserver_foreman/pull/29) ([ekohl](https://github.com/ekohl))

## [2.2.0](https://github.com/theforeman/puppet-puppetserver_foreman/tree/2.2.0) (2022-10-28)

[Full Changelog](https://github.com/theforeman/puppet-puppetserver_foreman/compare/2.1.0...2.2.0)

**Implemented enhancements:**

- Fixes [\#35684](https://projects.theforeman.org/issues/35684) - Drop Applied catalog lines [\#25](https://github.com/theforeman/puppet-puppetserver_foreman/pull/25) ([ekohl](https://github.com/ekohl))
- Update to voxpupuli-test 5 [\#22](https://github.com/theforeman/puppet-puppetserver_foreman/pull/22) ([ekohl](https://github.com/ekohl))
- Serve from cache when response.code != 200 [\#21](https://github.com/theforeman/puppet-puppetserver_foreman/pull/21) ([idl0r](https://github.com/idl0r))

## [2.1.0](https://github.com/theforeman/puppet-puppetserver_foreman/tree/2.1.0) (2022-02-03)

[Full Changelog](https://github.com/theforeman/puppet-puppetserver_foreman/compare/2.0.0...2.1.0)

**Implemented enhancements:**

- Add report\_retry\_limit setting [\#18](https://github.com/theforeman/puppet-puppetserver_foreman/pull/18) ([jplindquist](https://github.com/jplindquist))
- puppetlabs/stdlib: Allow 8.x [\#16](https://github.com/theforeman/puppet-puppetserver_foreman/pull/16) ([bastelfreak](https://github.com/bastelfreak))

**Merged pull requests:**

- Correct assertion to reflect ensure\_packages new default [\#15](https://github.com/theforeman/puppet-puppetserver_foreman/pull/15) ([ekohl](https://github.com/ekohl))
- Fix project URLs used by puppet forge [\#14](https://github.com/theforeman/puppet-puppetserver_foreman/pull/14) ([neomilium](https://github.com/neomilium))

## [2.0.0](https://github.com/theforeman/puppet-puppetserver_foreman/tree/2.0.0) (2021-07-23)

[Full Changelog](https://github.com/theforeman/puppet-puppetserver_foreman/compare/1.0.0...2.0.0)

**Breaking changes:**

- Drop Puppet 5 support [\#10](https://github.com/theforeman/puppet-puppetserver_foreman/pull/10) ([ehelms](https://github.com/ehelms))

**Implemented enhancements:**

- Allow Puppet 7 compatible versions of mods [\#8](https://github.com/theforeman/puppet-puppetserver_foreman/pull/8) ([ekohl](https://github.com/ekohl))

## [1.0.0](https://github.com/theforeman/puppet-puppetserver_foreman/tree/1.0.0) (2021-04-26)

[Full Changelog](https://github.com/theforeman/puppet-puppetserver_foreman/compare/dc6257d5bbbab33172bf60c6823b913400aa6334...1.0.0)

**Merged pull requests:**

- Support Puppetserver 7 [\#6](https://github.com/theforeman/puppet-puppetserver_foreman/pull/6) ([ekohl](https://github.com/ekohl))
- Switch from Travis CI to Github Actions [\#3](https://github.com/theforeman/puppet-puppetserver_foreman/pull/3) ([ekohl](https://github.com/ekohl))
- Port over code from puppet-foreman [\#1](https://github.com/theforeman/puppet-puppetserver_foreman/pull/1) ([ekohl](https://github.com/ekohl))



\* *This Changelog was automatically generated by [github_changelog_generator](https://github.com/github-changelog-generator/github-changelog-generator)*
