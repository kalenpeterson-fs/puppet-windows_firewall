require 'puppet_x'
require 'pp'
module PuppetX
  module WindowsFirewall

    MOD_DIR = "windows_firewall/lib"
    SCRIPT_FILE = "ps-bridge.ps1"
    SCRIPT_PATH = File.join("ps/windows_firewall", SCRIPT_FILE)


    # We need to be able to invoke the PS bridge script in both agent and apply
    # mode. In agent mode, the file will be found in LIBDIR, in apply mode it will
    # be found somewhere under CODEDIR. We need to read from the appropriate dir
    # for each mode to work in the most puppety way
    def self.resolve_ps_bridge

      case Puppet.run_mode.name
      when :user
        # AKA `puppet resource` - first scan modules then cache
        script = find_ps_bridge_in_modules || find_ps_bridge_in_cache
      when :apply
        # puppet apply demands local module install...
        script = find_ps_bridge_in_modules
      when :agent
        # agent mode would only look in cache
        script = find_ps_bridge_in_cache
      else
        raise("Don't know how to resolve #{SCRIPT_FILE} for windows_firewall in mode #{Puppet.run_mode.name}")
      end

      if ! script
        raise("windows_firewall unable to find #{SCRIPT_FILE} in expected location")
      end

      cmd = ["powershell.exe", "-File", script]
      cmd
    end

    def self.find_ps_bridge_in_modules
      # 1st priority - environment
      check_for_script = File.join(
          Puppet.settings[:environmentpath],
          Puppet.settings[:environment],
          MOD_DIR,
          SCRIPT_PATH,
          )
      Puppet.debug("Checking for #{SCRIPT_FILE} at #{check_for_script}")
      if File.exists? check_for_script
        script = check_for_script
      else
        # 2nd priority - custom module path, then basemodulepath
        full_module_path = "#{Puppet.settings[:modulepath]}#{File::PATH_SEPARATOR}#{Puppet.settings[:basemodulepath]}"
        full_module_path.split(File::PATH_SEPARATOR).reject do |path_element|
          path_element.empty?
        end.each do |path_element|
          check_for_script = File.join(path_element, MOD_DIR, SCRIPT_PATH)
          Puppet.debug("Checking for #{SCRIPT_FILE} at #{check_for_script}")
          if File.exists? check_for_script
            script = check_for_script
            break;
          end
        end
      end

      script
    end

    def self.find_ps_bridge_in_cache
      check_for_script = File.join(Puppet.settings[:libdir], SCRIPT_PATH)

      Puppet.debug("Checking for #{SCRIPT_FILE} at #{check_for_script}")
      script = File.exists? check_for_script ? check_for_script : nil
      script
    end



    # convert a puppet type key name to the argument to use for `netsh` command
    def self.global_argument_lookup(key)
      {
          :keylifetime       => "mainmode mmkeylifetime",
          :secmethods        => "mainmode mmsecmethods",
          :forcedh           => "mainmode mmforcedh",
          :strongcrlcheck    => "ipsec strongcrlcheck",
          :saidletimemin     => "ipsec saidletimemin",
          :defaultexemptions => "ipsec defaultexemptions",
          :ipsecthroughnat   => "ipsec ipsecthroughnat",
          :authzcomputergrp  => "ipsec authzcomputergrp",
          :authzusergrp      => "ipsec authzusergrp",
      }.fetch(key, key.to_s)
    end

    # convert a puppet type key name to the argument to use for `netsh` command
    def self.profile_argument_lookup(key)
      {
        :localfirewallrules         => "settings localfirewallrules",
        :localconsecrules           => "settings localconsecrules",
        :inboundusernotification    => "settings inboundusernotification",
        :remotemanagement           => "settings remotemanagement",
        :unicastresponsetomulticast => "settings unicastresponsetomulticast",
        :logallowedconnections      => "logging allowedconnections",
        :logdroppedconnections      => "logging droppedconnections",
        :filename                   => "logging filename",
        :maxfilesize                => "logging maxfilesize",
     }.fetch(key, key.to_s)
    end

    def self.to_ps(key)
      {
        :enabled               => lambda { |x| camel_case(x)},
        :action                => lambda { |x| camel_case(x)},
        :direction             => lambda { |x| camel_case(x)},
        :interface_type        => lambda { |x| camel_case(x)},
        :profile               => lambda { |x| x.map {|e| camel_case(e)}.join(",")},
        :protocol              => lambda { |x| x.to_s.upcase.sub("V","v")},
        :edge_traversal_policy => lambda { |x| camel_case(x)},
        :local_port            => lambda { |x| "\"#{x}\""},
        :remote_port           => lambda { |x| "\"#{x}\""},
      }.fetch(key, lambda { |x| x })
    end

    def self.to_ruby(key)
      {
        :enabled                => lambda { |x| snake_case_sym(x)},
        :action                 => lambda { |x| snake_case_sym(x)},
        :direction              => lambda { |x| snake_case_sym(x)},
        :interface_type         => lambda { |x| snake_case_sym(x)},
        :profile                => lambda { |x| x.split(",").map{ |e| snake_case_sym(e.strip)}},
        :protocol               => lambda { |x| snake_case_sym(x)},
        :edge_traversal_policy  => lambda { |x| snake_case_sym(x)},
      }.fetch(key, lambda { |x| x })
    end

    # create a normalised key name by:
    # 1. lowercasing input
    # 2. converting spaces to underscores
    # 3. convert to symbol
    def self.key_name(input)
      input.downcase.gsub(/\s/, "_").to_sym
    end

    # Convert input CamelCase to snake_case symbols
    def self.snake_case_sym(input)
      input.gsub(/([a-z])([A-Z])/, '\1_\2').downcase.to_sym
    end

    # Convert snake_case input symbol to CamelCase string
    def self.camel_case(input)
      # https://stackoverflow.com/a/24917606/3441106
      input.to_s.split('_').collect(&:capitalize).join
    end

    def self.delete_rule(name)
      Puppet.notice("(windows_firewall) deleting rule '#{name}'")
      out = Puppet::Util::Execution.execute(resolve_ps_bridge + ["delete"], name).to_s
      Puppet.debug out
    end

    # Create a new firewall rule using powershell
    # @see https://docs.microsoft.com/en-us/powershell/module/netsecurity/new-netfirewallrule?view=win10-ps
    def self.create_rule(resource)
      Puppet.notice("(windows_firewall) adding rule '#{resource[:name]}'")

      # `Name` is mandatory and also a `parameter` not a `property`
      args = [ "-Name", resource[:name] ]
      
      resource.properties.reject { |property|
        [:ensure, :protocol_type, :protocol_code].include?(property.name) ||
            property.value == :none
      }.each { |property|
        # All properties start `-`
        property_name = "-#{camel_case(property.name)}"
        property_value = to_ps(property.name).call(property.value)

        # protocol can optionally specify type and code, other properties are set very simply
        args << property_name
        args << property_value
            # if property_name == "protocol" && @resource[:protocol_type] && resource[:protocol_code]
            #   "protocol=\"#{property_value}:#{@resource[:protocol_type]},#{@resource[:protocol_code]}\""
            # else
            #   "#{property_name}=\"#{property_value}\""
            # end
      }
      # cmd = "#{command(:cmd)} advfirewall firewall add rule name=\"#{@resource[:name]}\" #{args.join(' ')}"
      # output = execute(cmd).to_s
      # Puppet.debug("...#{output}")


      Puppet.debug "Creating firewall rule with args: #{args}"

      out = Puppet::Util::Execution.execute(resolve_ps_bridge + ["create"] + args)
      Puppet.debug out
    end

    def self.rules
      rules = JSON.parse Puppet::Util::Execution.execute(resolve_ps_bridge + ["show"]).to_s
      
      # Rules is an array of hash as-parsed and hash keys need converted to
      # lowercase ruby labels
      puppet_rules = rules.map { |e|
        Hash[e.map { |k,v|
          key = snake_case_sym(k)
          [key, to_ruby(key).call(v)]
        }].merge({ensure: :present})
      }
      Puppet.debug("Parsed rules: #{puppet_rules.pretty_inspect}")

      #
      # begin
      #   Puppet::Util::Execution.execute([cmd, "advfirewall", "firewall", "show", "rule", "all", "verbose"]).to_s.split("\n\n").each do |line|
      #     rules << parse_rule(line)
      #   end
      # rescue Puppet::ExecutionFailure => e
      #   # if there are no rules (maybe someone purged them...) then the command will fail with
      #   # the message below. In this case we can ignore the error and just zero the list of rules
      #   # parsed
      #   if e.message =~ /No rules match the specified criteria/
      #     rules = []
      #   end
      # end
      #
      # rules

      puppet_rules
    end

    def self.groups(cmd)
      # get all individual firewall rules, then create a new hash containing the overall group
      # status for each group of rules
      groups = {}
      rules.select { |e|
        # we are only interested in firewall rules that provide grouping information so bounce
        # anything that doesn't have it from the list
        e.has_key? :grouping
      }.each { |e|
        # extract the group information for each rule, use the value of :enabled to
        # build up an overall status for the whole group
        groups[e[:grouping]] = (groups.fetch(e[:grouping], "yes") && e[:enabled] == "yes") ? "yes" : "no"
      }

      # convert into puppet's preferred hash format which is an array of hashes
      # with each hash representing a distinct resource
      transformed = groups.map { |k,v|
        {:name => k, :enabled => v}
      }

      transformed
    end

    # Each rule is se
    # def self.parse_rule(input)
    #   rule = {}
    #   last_key = nil
    #   input.split("\n").reject { |line|
    #     line =~ /---/
    #   }.each { |line|
    #     # split at most twice - there will be more then one colon if we have path to a program here
    #     # eg:
    #     #   Program: C:\foo.exe
    #     line_split = line.split(":", 2)
    #
    #     if line_split.size == 2
    #       key = key_name(line_split[0].strip)
    #
    #       # downcase all values for comparison purposes
    #       value = line_split[1].strip.downcase
    #
    #       # puppet blows up if the namevar isn't called `name` despite what you choose to expose this
    #       # to the user as in the type definition...
    #       safe_key = (key == :rule_name) ? :name : key
    #
    #       case safe_key
    #       when :profiles
    #         munged_value = value.split(",")
    #       else
    #         munged_value = value
    #       end
    #
    #       rule[safe_key] = munged_value
    #       last_key = safe_key
    #
    #     else
    #       # probably looking at the protocol type/code - we only support ONE of these per rule
    #       # since the CLI only lets us set one (although the GUI has no limit). Because of looping
    #       # this will return the _last_ item in the list
    #       if last_key == :protocol
    #         line_split = line.strip.split(/\s+/, 2)
    #         if line_split.size == 2
    #           rule[:protocol_type] = line_split[0].downcase
    #           rule[:protocol_code] = line_split[1].downcase
    #         end
    #       end
    #     end
    #   }
    #
    #   # if we see the rule then it must exist...
    #   rule[:ensure] = :present
    #
    #   Puppet.debug "Parsed windows firewall rule: #{rule}"
    #   rule
    # end


    # Each rule is se
    def self.parse_profile(input)
      profile = {}
      first_line = true
      profile_name = "__error__"
      input.split("\n").reject { |line|
        line =~ /---/ || line =~ /^\s*$/
      }.each { |line|
        if first_line
          # take the first word in the line - eg "public profile settings" -> "public"
          profile_name = line.split(" ")[0].downcase
          first_line = false
        else
          # nasty hack - "firewall policy" setting contains space and will break our
          # logic below. Also the setter in `netsh` to use is `firewallpolicy`. Just fix it...
          line = line.sub("Firewall Policy", "firewallpolicy")

          # split each line at most twice by first glob of whitespace
          line_split = line.split(/\s+/, 2)

          if line_split.size == 2
            key = key_name(line_split[0].strip)

            # downcase all values for comparison purposes
            value = line_split[1].strip.downcase

            profile[key] = value
          end
        end
      }

      # if we see the rule then it must exist...
      profile[:name] = profile_name

      Puppet.debug "Parsed windows firewall profile: #{profile}"
      profile
    end

    # Each rule is se
    def self.parse_global(input)
      globals = {}
      input.split("\n").reject { |line|
        line =~ /---/ || line =~ /^\s*$/
      }.each { |line|

        # split each line at most twice by first glob of whitespace
        line_split = line.split(/\s+/, 2)

        if line_split.size == 2
          key = key_name(line_split[0].strip)

          # downcase all values for comparison purposes
          value = line_split[1].strip.downcase

          case key
          when :secmethods
            # secmethods are output with a hypen like this:
            #   DHGroup2-AES128-SHA1,DHGroup2-3DES-SHA1
            # but must be input with a colon like this:
            #   DHGroup2:AES128-SHA1,DHGroup2:3DES-SHA1
            safe_value = value.split(",").map { |e|
              e.sub("-", ":")
            }.join(",")
          when :strongcrlcheck
            safe_value = value.split(":")[0]
          when :defaultexemptions
            safe_value = value.split(",").sort
          when :saidletimemin
            safe_value = value.sub("min","")
          when :ipsecthroughnat
            safe_value = value.gsub(" ","")
          else
            safe_value = value
          end

          globals[key] = safe_value
        end
      }

      globals[:name] = "global"

      Puppet.debug "Parsed windows firewall globals: #{globals}"
      globals
    end

    # parse firewall profiles
    def self.profiles(cmd)
      profiles = []
      # the output of `show allprofiles` contains several blank lines that make parsing somewhat
      # harder so just run it for each of the three profiles to make life easy...
      ["publicprofile", "domainprofile", "privateprofile"].each { |profile|
        profiles <<  parse_profile(Puppet::Util::Execution.execute([cmd, "advfirewall", "show", profile]).to_s)
      }
      profiles
    end


    # parse firewall profiles
    def self.globals(cmd)
      profiles = []
      # the output of `show allprofiles` contains several blank lines that make parsing somewhat
      # harder so just run it for each of the three profiles to make life easy...
      ["publicprofile", "domainprofile", "privateprofile"].each { |profile|
        profiles <<  parse_global(Puppet::Util::Execution.execute([cmd, "advfirewall", "show", "global"]).to_s)
      }
      profiles
    end
  end
end


