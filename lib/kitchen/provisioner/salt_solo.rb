# -*- encoding: utf-8 -*-
#
# Author:: Simon McCartney <simon.mccartney@hp.com>
#
# Copyright (C) 2013, Chris Lundquist, Simon McCartney
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#    http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

require 'kitchen/provisioner/base'
require 'kitchen-salt/util'
require 'fileutils'
require 'yaml'

module Kitchen
  module Provisioner
    # Basic Salt Masterless Provisioner, based on work by
    #
    # @author Chris Lundquist (<chris.ludnquist@github.com>)

    class SaltSolo < Base
      include Kitchen::Salt::Util

      default_config :salt_version, 'latest'

      # supported install methods: bootstrap|apt
      default_config :salt_install, 'bootstrap'

      default_config :salt_bootstrap_url, 'http://bootstrap.saltstack.org'
      default_config :salt_bootstrap_options, ''

      # alternative method of installing salt
      default_config :salt_apt_repo, 'http://apt.mccartney.ie'
      default_config :salt_apt_repo_key, 'http://apt.mccartney.ie/KEY'
      default_config :salt_ppa, 'ppa:saltstack/salt'

      default_config :chef_bootstrap_url, 'https://www.getchef.com/chef/install.sh'

      default_config :salt_config, '/etc/salt'
      default_config :salt_minion_config, '/etc/salt/minion'
      default_config :salt_env, 'base'
      default_config :salt_file_root, '/srv/salt'
      default_config :salt_pillar_root, '/srv/pillar'
      default_config :salt_state_top, '/srv/salt/top.sls'
      default_config :state_collection, false
      default_config :state_top, {}
      default_config :state_top_from_file, false
      default_config :salt_run_highstate, true
      default_config :salt_copy_filter, []
      default_config :is_file_root, false
      default_config :require_chef, true

      default_config :dependencies, []
      default_config :vendor_path, nil
      default_config :omnibus_cachier, false

      # salt-call version that supports the undocumented --retcode-passthrough command
      RETCODE_VERSION = '0.17.5'.freeze

      def install_command
        debug(diagnose)

        # if salt_verison is set, bootstrap is being used & bootstrap_options is empty,
        # set the bootstrap_options string to git install the requested version
        if (config[:salt_version] != 'latest') && (config[:salt_install] == 'bootstrap') && config[:salt_bootstrap_options].empty?
          debug("Using bootstrap git to install #{config[:salt_version]}")
          config[:salt_bootstrap_options] = "-P git v#{config[:salt_version]}"
        end

        install_template = File.expand_path("./install.erb", File.dirname(__FILE__))

        ERB.new(File.read(install_template)).result(binding)
      end

      def install_chef
        return unless config[:require_chef]
        chef_url = config[:chef_bootstrap_url]
        omnibus_download_dir = config[:omnibus_cachier] ? '/tmp/vagrant-cache/omnibus_chef' : '/tmp'
        <<-INSTALL
          if [ ! -d "/opt/chef" ]
          then
            echo "-----> Installing Chef Omnibus (for busser/serverspec ruby support)"
            mkdir -p #{omnibus_download_dir}
            if [ ! -x #{omnibus_download_dir}/install.sh ]
            then
              do_download #{chef_url} #{omnibus_download_dir}/install.sh
            fi
            #{sudo('sh')} #{omnibus_download_dir}/install.sh -d #{omnibus_download_dir}
          fi
        INSTALL
      end

      def create_sandbox
        super
        prepare_data
        prepare_minion
        prepare_pillars
        prepare_grains

        if config[:state_collection] || config[:is_file_root]
          prepare_state_collection
        else
          prepare_formula config[:kitchen_root], config[:formula]

          unless config[:vendor_path].nil?
            if Pathname.new(config[:vendor_path]).exist?
              Dir[File.join(config[:vendor_path], '*')].each do |d|
                prepare_formula config[:vendor_path], File.basename(d)
              end
            else
              # :vendor_path was set, but not valid
              raise UserError, "kitchen-salt: Invalid vendor_path set: #{config[:vendor_path]}"
            end
          end
        end

        config[:dependencies].each do |formula|
          prepare_formula formula[:path], formula[:name]
        end
        prepare_state_top
      end

      def init_command
        debug("Initialising Driver #{name} by cleaning #{config[:root_path]}")
        "#{sudo('rm')} -rf #{config[:root_path]} ; mkdir -p #{config[:root_path]}"
      end

      def run_command
        debug("running driver #{name}")
        debug(diagnose)
        if config[:salt_run_highstate]
          cmd = sudo("salt-call --config-dir=#{File.join(config[:root_path], config[:salt_config])} --local state.highstate")
        else
          cmd = sudo("salt-call state.highstate")
        end

        cmd << " --log-level=#{config[:log_level]}" if config[:log_level]

        # config[:salt_version] can be 'latest' or 'x.y.z', 'YYYY.M.x' etc
        # error return codes are a mess in salt:
        #  https://github.com/saltstack/salt/pull/11337
        # Unless we know we have a version that supports --retcode-passthrough
        # attempt to scan the output for signs of failure
        if config[:salt_version] > RETCODE_VERSION || config[:salt_version] == 'latest'
          # hope for the best and hope it works eventually
          cmd += ' --retcode-passthrough'
        else
          # scan the output for signs of failure, there is a risk of false negatives
          fail_grep = 'grep -e Result.*False -e Data.failed.to.compile -e No.matching.sls.found.for'
          # capture any non-zero exit codes from the salt-call | tee pipe
          cmd = 'set -o pipefail ; ' << cmd
          # Capture the salt-call output & exit code
          cmd << ' 2>&1 | tee /tmp/salt-call-output ; SC=$? ; echo salt-call exit code: $SC ;'
          # check the salt-call output for fail messages
          cmd << " (sed '/#{fail_grep}/d' /tmp/salt-call-output | #{fail_grep} ; EC=$? ; echo salt-call output grep exit code ${EC} ;"
          # use the non-zer exit code from salt-call, then invert the results of the grep for failures
          cmd << ' [ ${SC} -ne 0 ] && exit ${SC} ; [ ${EC} -eq 0 ] && exit 1 ; [ ${EC} -eq 1 ] && exit 0)'
        end

        cmd
      end

      protected

      def prepare_data
        return unless config[:data_path]

        info('Preparing data')
        debug("Using data from #{config[:data_path]}")

        tmpdata_dir = File.join(sandbox_path, 'data')
        FileUtils.mkdir_p(tmpdata_dir)
        cp_r_with_filter(config[:data_path], tmpdata_dir, config[:salt_copy_filter])
      end

      def prepare_minion
        info('Preparing salt-minion')

        minion_config_content = <<-MINION_CONFIG.gsub(/^ {10}/, '')
          state_top: top.sls

          file_client: local

          file_roots:
           #{config[:salt_env]}:
             - #{File.join(config[:root_path], config[:salt_file_root])}

          pillar_roots:
           #{config[:salt_env]}:
             - #{File.join(config[:root_path], config[:salt_pillar_root])}
        MINION_CONFIG

        # create the temporary path for the salt-minion config file
        debug("sandbox is #{sandbox_path}")
        sandbox_minion_config_path = File.join(sandbox_path, config[:salt_minion_config])

        write_raw_file(sandbox_minion_config_path, minion_config_content)
      end

      def prepare_state_top
        info('Preparing state_top')

        sandbox_state_top_path = File.join(sandbox_path, config[:salt_state_top])

        if config[:state_top_from_file] == false
          # use the top.sls embedded in .kitchen.yml

          # we get a hash with all the keys converted to symbols, salt doesn't like this
          # to convert all the keys back to strings again
          state_top_content = unsymbolize(config[:state_top]).to_yaml
          # .to_yaml will produce ! '*' for a key, Salt doesn't like this either
          state_top_content.gsub!(/(!\s'\*')/, "'*'")
        else
          # load a top.sls from disk
          state_top_content = File.read('top.sls')
        end

        write_raw_file(sandbox_state_top_path, state_top_content)
      end

      def prepare_pillars
        info("Preparing pillars into #{config[:salt_pillar_root]}")
        debug("Pillars Hash: #{config[:pillars]}")

        return if config[:pillars].nil? && config[:'pillars-from-files'].nil?

        # we get a hash with all the keys converted to symbols, salt doesn't like this
        # to convert all the keys back to strings again
        pillars = unsymbolize(config[:pillars])
        debug("unsymbolized pillars hash: #{pillars}")

        # write out each pillar (we get key/contents pairs)
        pillars.each do |key, contents|
          # convert the hash to yaml
          pillar = contents.to_yaml

          # .to_yaml will produce ! '*' for a key, Salt doesn't like this either
          pillar.gsub!(/(!\s'\*')/, "'*'")

          # generate the filename
          sandbox_pillar_path = File.join(sandbox_path, config[:salt_pillar_root], key)

          debug("Rendered pillar yaml for #{key}:\n #{pillar}")
          write_raw_file(sandbox_pillar_path, pillar)
        end

        # copy the pillars from files straight across, as YAML.load/to_yaml and
        # munge multiline strings
        unless config[:'pillars-from-files'].nil?
          external_pillars = unsymbolize(config[:'pillars-from-files'])
          debug("external_pillars (unsymbolize): #{external_pillars}")
          external_pillars.each do |key, srcfile|
            debug("Copying external pillar: #{key}, #{srcfile}")
            # generate the filename
            sandbox_pillar_path = File.join(sandbox_path, config[:salt_pillar_root], key)
            # create the directory where the pillar file will go
            FileUtils.mkdir_p(File.dirname(sandbox_pillar_path))
            # copy the file across
            FileUtils.copy srcfile, sandbox_pillar_path
          end
        end
      end

      def prepare_grains
        debug("Grains Hash: #{config[:grains]}")

        return if config[:grains].nil?

        info("Preparing grains into #{config[:salt_config]}/grains")
        # we get a hash with all the keys converted to symbols, salt doesn't like this
        # to convert all the keys back to strings again we use unsymbolize
        # then we convert the hash to yaml
        grains = unsymbolize(config[:grains]).to_yaml

        # generate the filename
        sandbox_grains_path = File.join(sandbox_path, config[:salt_config], 'grains')
        debug("sandbox_grains_path: #{sandbox_grains_path}")

        write_hash_file(sandbox_grains_path, config[:grains])
      end

      def prepare_formula(path, formula)
        info("Preparing formula: #{formula} from #{path}")
        debug("Using config #{config}")

        formula_dir = File.join(sandbox_path, config[:salt_file_root], formula)
        FileUtils.mkdir_p(formula_dir)
        cp_r_with_filter(File.join(path, formula), formula_dir, config[:salt_copy_filter])

        # copy across the _modules etc directories for python implementation
        %w(_modules _states _grains _renderers _returners).each do |extrapath|
          src = File.join(path, extrapath)

          if File.directory?(src)
            debug("prepare_formula: #{src} exists, copying..")
            extrapath_dir = File.join(sandbox_path, config[:salt_file_root], extrapath)
            FileUtils.mkdir_p(extrapath_dir)
            cp_r_with_filter(src, extrapath_dir, config[:salt_copy_filter])
          else
            debug("prepare_formula: #{src} doesn't exist, skipping.")
          end
        end
      end

      def prepare_state_collection
        info('Preparing state collection')
        debug("Using config #{config}")

        if config[:collection_name].nil? && config[:formula].nil?
          info('neither collection_name or formula have been set, assuming this is a pre-built collection')
          config[:collection_name] = ''
        elsif config[:collection_name].nil?
          debug("collection_name not set, using #{config[:formula]}")
          config[:collection_name] = config[:formula]
        end

        debug("sandbox_path = #{sandbox_path}")
        debug("salt_file_root = #{config[:salt_file_root]}")
        debug("collection_name = #{config[:collection_name]}")
        collection_dir = File.join(sandbox_path, config[:salt_file_root], config[:collection_name])
        FileUtils.mkdir_p(collection_dir)
        cp_r_with_filter(config[:kitchen_root], collection_dir, config[:salt_copy_filter])
      end
    end
  end
end
