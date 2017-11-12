<!--
# @markup markdown
# @title Provisioner Options
# @author SaltStack Inc.
-->

# Provisioner Options #

## State Options ##

### dry_run ###

default: `false`

Setting this to True will run the highstate with test=True (good for testing states syntax)

### formula ###

default: `nil`

Name of the formula directory for finding where the state files are located.

### state_collection ###

default: `nil`

Directory containing salt states that is not a formula

### is_file_root ###

default: `false`

Treat the root directory of this project as a complete file root.

Setting the `is_file_root` flag allows you to work with a directory tree that more closely resembles a built file_root on a salt-master, where you have may have multiple directories of states or formula.  The project is recursively copied down to guest instance, excluding any hidden files or directories (i.e. .git is not copied down, this is the standard behaviour of ruby's FileUtil.cp_r method)

Consider a directory that looks like this:

    top.sls
    .kitchen.yml
    apache/init.sls
    mysql/init.sls
    mysql/client.sls
    mysql/server.sls
    php/init.sls
    ...

With a .kitchen.yml like this you can now test the completed collection:

    ---
    driver:
      name: vagrant

    provisioner:
      name: salt_solo
      is_file_root: true
      state_top:
        base:
          '*':
            - apache
            - mysql.client

    platforms:
      - name: ubuntu-12.04

    suites:
      - name: default

In this example, the apache state could use functionality from the php state etc.  You're not just restricted to a single formula.

### local_salt_root ###

default: `nil`

When used with is_file_root, the directory specified here represents the /srv/ directory and everything will be copied there.

    provisioner:
      is_file_root: true
      local_salt_root: setup/

The above will require that a `salt` directory be located at `setup/salt/` with all the state files in it.  To use the root directory, set `local_salt_root: '.'`.

### remote_states ###

default: `nil`

This is used for testing environments.  Specify the salt states elsewhere, and then use them to deploy code from the current environment.

    ---
    provisioner:
      name: salt_solo
      remote_states:
        repo: git
        name: git://github.com/saltstack/salt-jenkins.git
        branch: 2017.7
        testingdir: /testing
      state_top:
        base:
          '*':
            - git.salt

This will clone down the git repo to the sandbox /srv/salt, and then run the git.salt state.

Salt-Jenkins is used to configure the testing environment for saltstack.

The repo from which this is run is copied with the `salt_copy_filter` applied to the `testingdir`

### log_level ###

default: `nil`

The log level with which the salt-call command will be run.

### state_top ###

default: `{}`

Dictionary that will be turned into a top file on the test instance.

    suites:
      - name: client
        provisioner:
          state_top:
            base:
              '*':
                - beaver
                - beaver.ppa

      - name: server
        provisioner:
          state_top:
            base:
              '*':
                - beaver.server
                - beaver.ppa

### salt_env ###

default: `base`

Environment to use in the environment to use in minion config file for the file and pillar roots.

### state_top_from_file ###

default: `nil`

File to use as the `top.sls` in the test instance

### vendor_path ###

default: `nil`

Absolute or relative path to a collection of formulas required for the states that are being tested.

Example

    provisioner:
      vendor_path: ./srv/env/dev/_formulas

### vendor_repo ###

default: `nil`

Setup repositories for installing packaged formula dependencies.

Types:

- **apt**: apt repository
- **ppa**: ppa repository
- **spm**: spm repository

TODO: add yum

Examples

    provisioner:
      vendor_repo:
        - type: apt
          url: http://apt-mk.mirantis.com/trusty
          key_url: http://apt-mk.mirantis.com/public.gpg
          components: salt
          distribution: nightly
        - type: ppa
          name: neovim-ppa/unstable
        - type: spm
          url: https://spm.hubblestack.io/2016.7.1
          name: hubblestack

### dependencies ###

default: `[]`

A list of hashes for installing formula depenencies into the VM.

Types:

- **path**: relative or absolute path to one formula
- **apt**: install formula via apt package
- **yum**: install formula via yum package
- **spm**: install formula via spm package from http, path, or spm repository
- **git**: install formula by cloning git repository

Examples

    provisioner:
      dependencies:
        - name: foo
          path: ./tests/formula-foo
        - name: nginx
          repo: apt
          package: salt-formula-nginx
        - name: linux
          repo: git
          source: https://github.com/salt-formulas/salt-formula-linux.git
        - name: nginx
          repo: yum
          package: salt-formula-nginx
        - name: hubblestack_nova
          repo: spm
          package: https://spm.hubblestack.io/nova/hubblestack_nova-2016.10.1-1.spm

## Grain and Pillar Options ##

### grains ###

default: `nil`

This options allows grains to be set on the guest, written out to ``/etc/salt/grains``

For example, the following suite will define grains on the guest:

      - name: set-grains-test
        provisioner:
          salt_version: 0.16.2
          grains:
            roles:
              - webserver
              - memcache
            deployment: datacenter4
            cabinet: 13
            cab_u: 14-15

### pillars ###

default: `{}`

Dictionary of pillar files to setup on the minion.

    pillars:
      top.sls:
        base:
          '*':
            - testing
      testing.sls:
        python:
          bin: /usr/bin/python3
          version: 3

### pillars-from-files ###

default: `nil`

The pillars-from-files option allows for loading pillar data from another file, instead of being embedded in the .kitchen.yml.  This allows the re-use of the example files or reduce the clutter in .kitchen.yml

Consider the following suite definition:

    - name: tcp-output-external-pillar
      provisioner:
        pillars-from-files:
          beaver.sls: pillar.example
        pillars:
          top.sls:
            base:
              '*':
                - beaver

And the contents of pillar.example is a normal pillar file:

    # defaults are set in map.jinja and can be over-ridden like this
    beaver:
      transport: stdout
      format: json

### pillars_from_directories ###

default: `[]`

A list of directories that will be copied recursively to the pillar root.

## Install Salt ##

### salt_install ###

default: `bootstrap`

Method by which salt will be installed:

- **bootstrap**: install salt with the bootstrap script.
- **yum**: install salt from a yum repository.
- **apt**: install salt from an apt repository.
- **distrib**: install the version of salt that comes with the distribution.
- **ppa**: install salt from a ppa.

Except for `distrib` and `bootstrap`, most of these options will require extra configuration to make sure it fits the tests distribution version.  Unless the newest version is used, then it should just work for yum and apt setups.

### salt_version ###

default: `latest`

The desired version of salt that will be installed.  For some places, this is used to set the repo to enable or what version to pass to bootstrap.

This is also used to verify that the correct version of salt was installed before running the highstate.

### salt_bootstrap_url ###

default: `https://bootstrap.saltstack.com`

Location of the bootstrap script.

For Windows, use the [powershell script](https://github.com/saltstack/salt-bootstrap/blob/develop/bootstrap-salt.ps1)

### salt_bootstrap_options ###

default: `nil`

Optional options passed to the bootstrap script.  By default this gets set to the `salt_version` if nothing is specified here.

For example, this could be used to install salt from the develop branch:

    suites:
      - name: use-development-branch-salt
        provisioner:
          salt_bootstrap_options: -M -N git develop

Details on the various options available at the [salt-bootstrap](https://docs.saltstack.com/en/latest/topics/tutorials/salt_bootstrap.html) documentation.

For the Windows Powershell script:

    platform:
      - name: windows
        salt_bootstrap_script: https://github.com/saltstack/salt-bootstrap/blob/develop/bootstrap-salt.ps1
        salt_bootstrap_options: -version 2017.7.2

### salt_apt_repo ###

default: `https://repo.saltstack.com/apt/ubuntu/16.04/amd64/`
This should be the top level of the apt repository so that the `salt_version` can be appended to the url.

### salt_apt_repo_key ###

default: `https://repo.saltstack.com/apt/ubuntu/16.04/amd64/latest/SALTSTACK-GPG-KEY.pub`

The location of the apt repo key.

### salt_ppa ###

default: `ppa:saltstack/salt`

Specify the ppa to enable for installing.  This is probably not as useful anymore now that salt is managed from the [official repos](https://repo.saltstack.com/#ubuntu)

### salt_yum_rpm_key ###

default: `https://repo.saltstack.com/yum/redhat/7/x86_64/archive/%s/SALTSTACK-GPG-KEY.pub`

The rpm key that should be installed for verifying signatures of the yum repo packages.

### salt_yum_repo ###

default: `https://repo.saltstack.com/yum/redhat/$releasever/$basearch/archive/%s`

The baseurl for the yum repository.  `%s` is replaced with `salt_version`. More information on [SaltStack Package Repo](https://repo.saltstack.com/)

### salt_yum_repo_key ###

default: `https://repo.saltstack.com/yum/redhat/$releasever/$basearch/archive/%s/SALTSTACK-GPG-KEY.pub`

The gpg key url to the key for the yum repository file. `%s` is replaced with `salt_version`. More information on [SaltStack Package Repo](https://repo.saltstack.com/)

### salt_yum_repo_latest ###

default : `https://repo.saltstack.com/yum/redhat/salt-repo-latest-2.el7.noarch.rpm`

The url for the yum repository rpm. Used to install if `salt_version` is `latest`. More information on [SaltStack Package Repo](https://repo.saltstack.com/)

### pip_pkg ###

default: `salt==%s`

Name of the pip package to install for salt.  This can be a file location or a package name from a pypi simple server.

### pip_editable ###

default: `false`

Install using the editable flag for pip

### pip_index_url ###

default: `https://pypi.python.org/simple/`

Path to the pypi simple index to use for installing salt.

### pip_extra_index_url ###

default: `[]`

List of extra index urls to fall back to if dependencies are not found on the main index.

### pip_bin ###

default: `pip`

pip binary in the `$PATH` or path to a pip binary to use for installing salt.

## Extra Config Options ##

### init_environment ###

default: `""`

Commands to run prior to running salt-call

### bootstrap_url ###

default: `https://raw.githubusercontent.com/saltstack/kitchen-salt/master/assets/install.sh`

A bootstrap script used to provide Ruby (`ruby` and `ruby-dev`) required for the serverspec test runner on the guest OS. If this script is unable to setup Ruby, it will fallback to using Chef bootstrap installer (set via `chef_bootstrap_url`)

### chef_bootstrap_url ###

default: `https://www.getchef.com/chef/install.sh`

The chef bootstrap installer, used to provide Ruby for the serverspec test runner on the guest OS.

### require_chef ###

default: `true`

Install chef.  This is required by the busser to run tests, if no verification driver is specified in the `.kitchen.yml`

### salt_config ###

default: `/etc/salt`

Location in the sandbox where the salt configs are placed.

### salt_copy_filter ###

default: `[]`

List of filenames and directories to be excluded when copying to the sandbox.

Example

    provisioner:
      is_file_root: true
      salt_copy_filter:
        - .git
        - .travis.yml

### salt_minion_config ###

default: `/etc/salt/minion`

Location to place the minion config in the sandbox.

### salt_minion_config_template ###

default: `nil`

Local custom minion config template to be used in kitchen-salt.  The default is {file:lib/kitchen/provisioner/minion.erb}

### salt_minion_id ###

default: `nil`

Customize salt minion_id. If none specified, the machine hostname is used.

### salt_file_root ###

default: `/srv/salt`

File root to use in the minion config and sandbox.

### salt_pillar_root ###

default: `/srv/pillar`

Pillar root to use in the minion config and sandbox.

### salt_state_top ###

default: `/srv/salt/top.sls`

Location to place the top file in the sandbox.

### salt_force_color ###

default: `false`

Pass `--force-color` to the salt-call command.
