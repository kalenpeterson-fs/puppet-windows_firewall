param(
    [String] $Target,
    [String] $Name,
    [String] $DisplayName,
    [String] $Description,
    $Enabled,
    $Action,
    [String] $Protocol,
    $IcmpType,
    $Profile,
    [String] $Program,
    $Direction,
    [String] $LocalIp,
    [String] $RemoteIp,
    [String] $ProtocolType,
    [Int]    $ProtocolCode,
    [String]    $LocalPort,
    [String]    $RemotePort,
    $EdgeTraversalPolicy,
    $InterfaceType
)

Import-Module NetSecurity


# =====

# Lookup select firewall rules using powershell. This is needed to resolve names that are missing
# from netsh output
function Get-PSFirewallRules {
    param($filter)

    $rules = @()
    Show-NetFirewallRule | Where-Object { $_.DisplayName  -in $filter} | ForEach-Object {

        $af = (Get-NetFirewallAddressFilter -AssociatedNetFirewallRule $_)[0]
        $appf = (Get-NetFirewallApplicationFilter -AssociatedNetFirewallRule $_)[0]
        $pf = (Get-NetFirewallPortFilter -AssociatedNetFirewallRule $_)[0]
        $if = (Get-NetFirewallInterfaceTypeFilter -AssociatedNetFirewallRule $_)[0]

        $rules += @{
            Name = $_.Name
            DisplayName = $_.DisplayName
            Description = $_.Description
            Enabled = $_.Enabled.toString()
            Action = $_.Action.toString()
            Direction = $_.Direction.toString()
            EdgeTraversalPolicy = $_.EdgeTraversalPolicy.toString()
            Profile = $_.Profile.toString()
            DisplayGroup = $_.DisplayGroup
            # Address Filter
            LocalAddress = $af.LocalAddress
            RemoteAddress = $af.RemoteAddress
            LocalIp = $af.LocalIp
            RemoteIp = $af.RemoteIp
            # Port Filter
            LocalPort = $pf.LocalPort
            RemotePort = $pf.RemotePort
            Protocol = $pf.Protocol
            IcmpType = $pf.IcmpType
            # Application Filter
            Program = $appf.Program
            # Interface Filter
            InterfaceType = $if.InterfaceType.toString()
        }
    }
    return $rules
}

# resolve references like
# *  @{Microsoft.Todos_1.41.12842.0_x64__8wekyb3d8bbwe?ms-resource://Microsoft.Todos/Resources/app_name_ms_todo}
# to
# * Microsoft To-Do
# by resolving in registry
function Get-ResolveRefs {
    param($refs)
    $resolved = @()
    $searchPath = 'HKCR:\Local Settings\MrtCache'
    # http://powershelleverydayfaq.blogspot.com/2012/06/how-to-query-hkeyclassesroot.html
    New-PSDrive -Name HKCR -PSProvider Registry -Root HKEY_CLASSES_ROOT

    $RegKey = Get-ChildItem $searchPath -rec -ea SilentlyContinue

    foreach ($ref in $refs) {
        $found = $false


        #$RegKey | foreach {
        :inner
        foreach ($r in $RegKey) {
            #$CurrentKey = (Get-ItemProperty -Path $_.PsPath)
            $CurrentKey = (Get-ItemProperty -Path $r.PsPath)
            if ($currentKey.$ref -ne $null) {
                $found = $currentKey.$ref
                break inner
            }
        }
        if (! $found) {
            write-error "could not resolve $($ref) in registry under $($searchPath)"
        } else {
            $resolved += $found
        }
    }
    return $resolved
}


# Convert netsh value to powershell value
function Get-NormalizedValue {
    param(
        $keyName,
        $rawValue
    )

    $normalize = @{
        "Enabled" = { param($x); if ($x -eq "Yes") {"True"} else {"False"}}
        "Direction" = { param($x) ; if ($x -eq "In") {"Inbound"} elseif ($x -eq "Out") {"Outbound"}}
        "EdgeTraversalPolicy" = { param($x);  if ($x -eq "No") { "Block"} elseif ($x -eq "Yes") {"Allow"} elseif ($x -eq "Defer to application") { "DeferToApp" } elseif ($x -eq "Defer to user") { "DeferToUser" }}
        "InterfaceType" = {param($x); $x -replace "RAS", "RemoteAccess" -replace "LAN", "Wired" }
        "Program" = { param($x); $x -replace '\\', '\\' }
    }

    if ($normalize.containsKey($keyName)) {
        $value = $normalize[$keyName].invoke($rawValue)
    } else {
        $value = $rawValue
    }
    return $value

}

# Normalize ICMP type from netsh to match that from powershell
function Get-NormalizedIcmpType {
    param(
        $type,
        $code
    )
    # Output from netsh will match one of:
    # * Any Any
    # * x Any
    # * x x
    # Output from powershell will match one of:
    # * Any
    # * x
    # * x:x

    if ($type -eq "Any") {
        $icmpType = "Any"
    } elseif ($code -eq "Any") {
        $icmpType = $type
    } else {
        $icmpType = "$($type):$($code)"
    }

    return $icmpType
}

# convert netsh keyname to powershell keyname
function Get-NormalizedKey {
    param($keyName)
    $keyNames = @{
        "InterfaceTypes" = "InterfaceType"
        "Description"= "Description"
        "Direction" = "Direction"
        "Edge traversal" = "EdgeTraversalPolicy"
        "Profiles" =  "Profile"
        "RemotePort" = "RemotePort"
        "Grouping" = "DisplayGroup"
        "Action" = "Action"
        "LocalIP" = "LocalIp"
        "Rule Name" = "Name"
        "Protocol" = "Protocol"
        "LocalPort" = "LocalPort"
        "Service" = "Unused_Service"
        "Security" = "UnusedSecurity"
        "RemoteIP" = "RemoteIp"
        "Program" =  "Program"
        "Enabled" = "Enabled"
        "Rule Source" = "Unused_RuleSource"
    }
    $resolved = $keyNames[$keyName]
    if (! $resolved) {
        write-error "Unable to resolve `netsh` key '$($keyName)' to a valid key"
    }
    return $resolved
}

# Parse a chunk of netsh output. Netsh uses a double blank line between output to new record
function Get-ParseChunk {
    param([String] $chunk)
    $rule = @{}
    $lastKey = $null

    ForEach ($line in $($chunk -split "`r`n")) {
        if ($line -notmatch "---" -and -not [string]::IsNullOrEmpty($line)) {
            # split at most twice - there will be more then one colon if we have path to a program here
            # eg:
            #   Program: C:\foo.exe
            $lineSplit = $line -split(":",2)



            if ($lineSplit.length -eq 2) {
                $key = Get-NormalizedKey $lineSplit[0].Trim()
                $value = Get-NormalizedValue $key $lineSplit[1].Trim()

                $rule[$key] = $value
            } else {
                # probably looking at the protocol type/code - we only support ONE of these per rule
                # since the CLI only lets us set one (although the GUI has no limit). Because of looping
                # this will return the _last_ item in the list. This lets us gracefully skip over the
                # header row "Type Code"
                $lineSplit = $line -split("\s+")
                if ($lineSplit.length -eq 2) {
                    $rule["IcmpType"] = Get-NormalizedIcmpType $lineSplit[0] $lineSplit[1]
                }
            }
        }
    }

    return $rule
}


# =====

function show {
    # step 1 - list all rules using `netsh` - the easiest and fastest way to resolve
    # 99% of values
    $netshOutput = netsh advfirewall firewall show rule all verbose | out-string
    $missingNames = @()
    $rules = @()
    $s0 = $(get-date)

    ForEach ($chunk in $($netshOutput -split "`r`n`r`n"))
    {
        $rule = Get-ParseChunk $chunk
        if ($rule.get_count() -gt 0) {

            if ($rule["Name"].contains("@")) {
                # additional lookup using powershell required to fully resolve one
                # or more rules
                $missingNames += $rule["Name"]
            } else {
                $rules += $rule
            }
        }
    }
    $s1 = $(get-date)

    if ($missingNames.length) {
        # we have unresolved names that require a secondary powershell lookup to resolve

        # First translate the resource-reef names to their real names
        $resolved = Get-ResolveRefs $missingNames

        $s2 = $(get-date)

        # then use the powershell API on a very limited subset to find them
        $rules += Get-PSFirewallRules $resolved
        $s3 = $(get-date)
    }

    $rules | convertto-json

}

function delete{
    write-host "Deleting $($Name)..."
    remove-netfirewallrule -name $Name
}


function create {

    $params = @{
        Name = $Name;
        Enabled = $Enabled;
        DisplayName = $DisplayName;
        Description = $Description;
        Action = $Action;
    }

    #
    # general optional params
    #
    if ($Direction) {
        $params.Add("Direction", $Direction)
    }
    if ($EdgeTraversalPolicy) {
        $params.Add("EdgeTraversalPolicy", $EdgeTraversalPolicy)
    }
    if ($Profile) {
        $params.Add("Profile", $Profile)
    }

    #
    # port filter
    #
    if ($Protocol) {
        $params.Add("Protocol", $Protocol)
    }
    if ($ProtocolType) {
        $params.Add("ProtocolType", $ProtocolType)
    }
    if ($ProtocolCode) {
        $params.Add("ProtocolCode", $ProtocolCode)
    }
    if ($IcmpType) {
        $params.Add("IcmpType", $IcmpType)
    }
    if ($LocalPort) {
        $params.Add("LocalPort", $LocalPort)
    }
    if ($RemotePort) {
        $params.Add("RemotePort", $RemotePort)
    }

    #
    # Program filter
    #
    if ($Program) {
        $param.Add("Program", $Program)
    }
    
    #
    # Interface filter
    #
    if ($InterfaceType) {
        $params.Add("InterfaceType", $InterfaceType)
    }

    # Host filter
    if ($LocalIp) {
        $params.Add("LocalIp", $LocalIp)
    }
    if ($RemoteIp) {
        $params.Add("remoteIp", $RemoteIp)
    }
    
    New-NetFirewallRule @params
}

switch ($Target) {
    "show" {
        show
    }
    "delete" {
        delete
    }
    "create" {
        create
    }
    default {
        write-error "invalid target: $($Target)"
    }
}