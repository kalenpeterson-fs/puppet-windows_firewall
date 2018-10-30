require 'puppet_x'
require 'puppet_x/windows_firewall'

Puppet::Type.type(:windows_firewall_rule).provide(:windows_firewall_rule, :parent => Puppet::Provider) do
  confine :osfamily => :windows
  mk_resource_methods
  desc "Windows Firewall"

  # We need to be able to invoke the PS bridge script in both agent and apply
  # mode. In agent mode, the file will be found in LIBDIR, in apply mode it will
  # be found somewhere under CODEDIR. We need to read from the appropriate dir
  # for each mode to avoid unexpected results
  def self.resolve_ps_bridge

    mod_dir = "windows_firewall/lib"
    script_path = "ps/windows_firewall/ps-bridge.ps1"

    # Use storeconfig as a proxy for "agentmode". Storeconfigs is used to
    # indicate to the agent whether there is a puppetdb instance alive
    if Puppet.settings[:storeconfigs]
      Puppet.debug "detected agent mode"
      script = File.join(Puppet.settings[:libdir], script_path)
    else
      Puppet.debug "detected apply mode"

      # 1st priority - environment
      check_for_script = File.join(
          Puppet.settings[:environmentpath],
          Puppet.settings[:envirionment],
          mod_dir,
          script_path
      )

      if File.exists? check_for_script
        script = check_for_script
      else
        # 2nd priority - global
        Puppet.settings[:modulepath].split(":").each do |path_element|
          check_for_script = File.join(path_element, mod_dir, script_path)
          if File.exists? check_for_script
            script = check_for_script
            break;
          end
        end
      end
    end

    cmd = "powershell.exe -File #{script}"

    cmd
  end

  def self.prefetch(resources)
    instances.each do |prov|
      if resource = resources[prov.name]
        resource.provider = prov
      end
    end
  end


  # def initialize(value={})
  #   super(value)
  #   @property_flush = {}
  # end


  def exists?
    @property_hash[:ensure] == :present
  end

  # all work done in `flush()` method
  def create()
  end

  # all work done in `flush()` method
  def destroy()
  end

  def self.instances
    PuppetX::WindowsFirewall.rules(resolve_ps_bridge).collect { |hash| new(hash) }
  end

  def flush
    # @property_hash contains the `IS` values (thanks Gary!)... For new rules there is no `IS`, there is only the
    # `SHOULD`. The setter methods from `mk_resource_methods` (or manually created) won't be called either. You have
    # to inspect @resource instead

    # we are flushing an existing resource to either update it or ensure=>absent it
    # therefore, delete this rule now and create a new one if needed
    if @property_hash[:ensure] == :present
      Puppet.notice("(windows_firewall) deleting rule '#{@resource[:name]}'")
      c = [command(:cmd), "advfirewall", "firewall", "delete", "rule", "name=\"#{@resource[:name]}\""]
      output = execute(c).to_s
    end

    if @resource[:ensure] == :present
      Puppet.notice("(windows_firewall) adding rule '#{@resource[:name]}'")
      args = []
      @resource.properties.reject { |property|
        [:ensure, :protocol_type, :protocol_code].include?(property.name)
      }.each { |property|
        # netsh uses `profiles` when listing but the setter argument for cli is `profile`, all
        # other setter/getter names are symmetrical
        property_name = (property.name == :profiles)? "profile" : property.name.to_s

        # flatten any arrays to comma deliminted lists (usually for `profile`)
        property_value = (property.value.instance_of?(Array)) ? property.value.join(",") : property.value

        # protocol can optionally specify type and code, other properties are set very simply
        args <<
            if property_name == "protocol" && @resource[:protocol_type] && resource[:protocol_code]
              "protocol=\"#{property_value}:#{@resource[:protocol_type]},#{@resource[:protocol_code]}\""
            else
              "#{property_name}=\"#{property_value}\""
            end
      }
      cmd = "#{command(:cmd)} advfirewall firewall add rule name=\"#{@resource[:name]}\" #{args.join(' ')}"
      output = execute(cmd).to_s
      Puppet.debug("...#{output}")
    end
  end

end
