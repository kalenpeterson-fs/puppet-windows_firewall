require 'puppet/parameter/boolean'

Puppet::Type.newtype(:windows_firewall) do
  @doc = "Manage Windows Firewall with Puppet"

  ensurable do
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

  newproperty(:direction) do
    desc "Direction the rule applies to (In/Out)"
    newvalues(:in, :out)
  end

  newproperty(:profiles) do
    desc "Which profile(s) this rule belongs to (Domain/Private/Public)"
    newvalues(:domain, :private, :public)
  end

  newproperty(:grouping) do
    desc "group that the rule belongs to"
  end

  newproperty(:localip) do
    desc "the local IP the rule targets"
  end

  newproperty(:remoteip) do
    desc "the remote IP the rule targets"
  end

  newproperty(:protocol) do
    desc "the protocol the rule targets"
    munge do |value|
      value.downcase
    end
  end

  newproperty(:localport) do
    desc "the local port the rule targets"
  end

  newproperty(:remoteport) do
    desc "the remote port the rule targets"
  end

  newproperty(:edge_traversal) do
    desc "Apply rule to encapsulated traffic (?) - see: https://serverfault.com/questions/89824/windows-advanced-firewall-what-does-edge-traversal-mean#89846"
  end

  newproperty(:action) do
    desc "What to do when this rule matches (Accept/Reject)"
    newvalues(:block, :allow)
  end

  newproperty(:program) do
    desc "Path to program this rule applies to"
    munge do |value|
      value.downcase
    end
  end

  newproperty(:interfacetypes) do
    desc "Interface types this rule applies to"
  end

  newproperty(:security) do
    desc "Security that applies to this rule"
    munge do |value|
      value.downcase
    end
  end

  newproperty(:rule_source) do
    desc "Where this rule originated"
    munge do |value|
      value.downcase
    end
  end

  newparam(:name) do
    desc "Name of this rule"
    isnamevar
    munge do |value|
      value.downcase
    end
  end

  # # see "title patterns" - https://www.craigdunn.org/2016/07/composite-namevars-in-puppet/
  # def self.title_patterns
  #   [
  #       # just a regular title (no '=') - assign it to the name field
  #       [ /(^([^\=]*)$)/m,
  #         [ [:name] ] ],
  #
  #       # Title is in form key=value - assign LHS of = to name, RHS to value
  #       [ /^([^=]+)=(.*)$/,
  #         [ [:name], [:value] ]
  #       ]
  #   ]
  # end

end