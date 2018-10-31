require 'puppet_x'
require 'puppet_x/windows_firewall'

Puppet::Type.type(:windows_firewall_rule).provide(:windows_firewall_rule, :parent => Puppet::Provider) do
  confine :osfamily => :windows
  mk_resource_methods
  desc "Windows Firewall"

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
