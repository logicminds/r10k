module MCollective
  module Agent
    class R10k<RPC::Agent

       def startup_hook
         @config_file = @config.pluginconf.fetch("r10k.config_file",'/etc/puppetlabs/r10k/r10k.yaml')
         @path_setting = @config.pluginconf.fetch("r10k.path_setting", "/opt/puppet/bin:/usr/local/bin")
         ENV['PATH'] += ":#{@path_setting}"
         @r10k_binary = `which r10k 2> /dev/null`.chomp
         @path_setting = @config.pluginconf.fetch("r10k.path_setting", ":/opt/puppet/bin:/usr/local/bin")
         @binary_path = @config.pluginconf.fetch("r10k.r10k_binary_path", @r10k_binary)
         @http_proxy  = @config.pluginconf.fetch("r10k.http_proxy", nil)
         @https_proxy = @config.pluginconf.fetch("r10k.https_proxy", @http_proxy)
         @git_ssl_no_verify = @config.pluginconf.fetch("r10k.git_ssl_no_verify", 0)
       end

       activate_when do
         #This helper only activate this agent for discovery and execution
         #If r10k is found on $PATH.
         # http://docs.puppetlabs.com/mcollective/simplerpc/agents.html#agent-activation
         ENV['PATH'] += ":/opt/puppet/bin:/usr/local/bin"
         output = `which r10k 2> /dev/null`
         unless $?.success?
           Log.warn("The r10k binary cannot be found, please configure r10k.r10k_binary_path or install r10k")
         end
         $?.success?
       end

       def check_config
         unless File.exists?(@config_file)
            Log.warn("The r10k config file is not present or configured in the mcollective r10.config_file setting")
            reply.fail("R10k config file not found on server at #{@config_file}")
         end
       end

       ['push',
        'pull',
        'status'].each do |act|
          action act do
            path = request[:path]
            if File.exists?(path)
              run_cmd act, path
              reply[:path] = path
            else
              reply.fail "Path not found #{path}"
            end
          end
        end
        ['cache',
         'synchronize',
         'deploy',
         'deploy_module',
         'sync'].each do |act|
          action act do
            if act == 'deploy'
              validate :environment, :shellsafe
              environment = request[:environment]
              run_cmd act, environment
              reply[:environment] = environment
            elsif act == 'deploy_module'
              validate :module_name, :shellsafe
              module_name = request[:module_name]
              run_cmd act, module_name
              reply[:module_name] = module_name
            else
              run_cmd act
            end
          end
        end
      private

      def cmd_as_user(cmd, cwd = nil)
        if /^\w+$/.match(request[:user])
          cmd_as_user = ['su', '-', request[:user], '-c', '\''] 
          if cwd
            cmd_as_user += ['cd', cwd, '&&']
          end
          cmd_as_user += cmd + ["'"]
        
          # doesn't seem to execute when passed as an array
          cmd_as_user.join(' ')
        else
          cmd
        end
      end 

      def run_cmd(action,arg=nil)
        output = ''
        git  = ['/usr/bin/env', 'git']
        r10k = ['/usr/bin/env', 'r10k']
        # Given most people using this are using Puppet Enterprise, add the PE Path
        environment = {"LC_ALL" => "C",
                       "PATH" => "#{ENV['PATH']}:#{@path_setting}",
                       "http_proxy" => @http_proxy,
                       "https_proxy" => @https_proxy,
                       "GIT_SSL_NO_VERIFY" => @git_ssl_no_verify
        }
        case action
          when 'push','pull','status'
            cmd = git
            cmd << 'push'   if action == 'push'
            cmd << 'pull'   if action == 'pull'
            cmd << 'status' if action == 'status'
            reply[:status] = run(cmd_as_user(cmd, arg), :stderr => :error, :stdout => :output, :chomp => true, :cwd => arg, :environment => environment )
          when 'cache','synchronize','sync', 'deploy', 'deploy_module'
            cmd = r10k
            cmd << 'cache' if action == 'cache'
            cmd << 'deploy' << 'environment' << '-p' if action == 'synchronize' or action == 'sync'
            if action == 'deploy'
              cmd << 'deploy' << 'environment' << arg << '-p'
            elsif action == 'deploy_module'
              cmd << 'deploy' << 'module' << arg
            end
            reply[:status] = run(cmd_as_user(cmd), :stderr => :error, :stdout => :output, :chomp => true, :environment => environment)
        end
      end
    end
  end
end
