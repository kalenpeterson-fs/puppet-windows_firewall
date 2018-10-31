require 'puppet/parameter/boolean'

Puppet::Type.newtype(:windows_firewall_rule) do
  @doc = "Manage Windows Firewall with Puppet"

  ensurable do
    desc "How to ensure this firewall rule (`present` or `absent`)"

    defaultvalues

    defaultto(:present)

    # we need the insync? for puppet to make right decision on whether to run the provider or not - if we leave it up
    # to provider.exists? then puppet resource command broken for files that are mismatched, they always show as ensure
    # absent even though puppet is somewhat aware of them
    def insync?(is)
      (is == :present && should == :present) || (is == :absent && should == :absent)
    end
  end

  newproperty(:enabled) do
    desc "Whether the rule is enabled (Yes or No)"
    newvalues(:yes, :no)
  end

  newproperty(:display_name) do
    desc "Displayname for this rule"
  end

  newproperty(:description) do
    desc "Description of this rule"
  end

  newproperty(:direction) do
    desc "Direction the rule applies to (`inbound`/`outbound`)"
    newvalues(:inbound, :outbound)
  end

  newproperty(:profile, :array_matching=>:all) do
    desc "Which profile(s) this rule belongs to, use an array to pass more then one"
    newvalues(:domain, :private, :public, :any)
	
    # Thanks Gary!
    def insync?(is)
      # `is` will be an unsorted array of STRING, `should` will be an unsorted
      # array of SYMBOL. Convert `is` to symbol and sort both for comparison
      # to avoid breaking idempotency
      is.map { |x| x.to_sym }.sort == should.sort
    end
  end

  newproperty(:grouping) do
    desc "group that the rule belongs to (read-only)"
    validate do |value|
      fail("grouping is readonly: https://social.technet.microsoft.com/Forums/office/en-US/669a8eaf-13d1-4010-b2ac-30c800c4b152/2008r2-firewall-add-rules-to-group-create-new-group")
    end
  end

  newproperty(:local_ip) do
    desc "the local IP the rule targets"
  end

  newproperty(:remote_ip) do
    desc "the remote IP the rule targets"
  end

  newproperty(:protocol) do
    desc "the protocol the rule targets"
    munge do |value|
      value.downcase
    end
  end

  newproperty(:icmp_type) do
    desc "protocol type to use (with ICMPv4/ICMPv6)"
    munge do |value|
      value.downcase
    end
  end

  newproperty(:protocol_code) do
    desc "protocol code to use (with ICMPv4/ICMPv6)"
    munge do |value|
      value.downcase
    end
  end

  newproperty(:local_port) do
    desc "the local port the rule targets"
  end

  newproperty(:remote_port) do
    desc "the remote port the rule targets"
  end

  newproperty(:edge_traversal_policy) do
    desc "Apply rule to encapsulated traffic (?) - see: https://serverfault.com/questions/89824/windows-advanced-firewall-what-does-edge-traversal-mean#89846"
    newvalues(:yes, :deferapp, :deferuser, :no)
  end

  newproperty(:action) do
    desc "What to do when this rule matches (Accept/Reject)"
    newvalues(:block, :allow)
  end

  newproperty(:program) do
    desc "Path to program this rule applies to"
  end

  newproperty(:interface_type) do
    desc "Interface types this rule applies to"
    newvalues(:wireless, :lan, :ras, :any)
  end

  
  newparam(:name) do
    desc "Name of this rule"
    isnamevar
    validate do |value|
      fail("it is not allowed to have a rule called 'any'") if value.downcase == "any"
    end
  end

end
