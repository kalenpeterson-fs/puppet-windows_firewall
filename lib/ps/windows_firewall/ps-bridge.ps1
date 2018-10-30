param(
    [String] $target,
    [String] $name,
    [String] $displayName,
    [String] $description,
    $enabled,
    $action,
    [String] $protocol,
    [Int]    $icmpType,
    $profile,
    [String] $program,
    $direction,
    [String] $localIp,
    [String] $remoteIp,
    [String] $protocolType,
    [Int]    $protocolCode,
    [Int]    $localPort,
    [Int]    $remotePort,
    $edgeTraversalPolicy,
    $interfaceTypes
)

Import-Module NetSecurity

function show {
    Show-NetFirewallRule | `
        Where-Object { $_.cimclass.toString() -eq "root/standardcimv2:MSFT_NetFirewallRule" } | `
            ForEach-Object { `
                $af = $_ | Get-NetFirewallAddressFilter | Select-Object -First 1; # Assumes only one filter
                $appf = $_ | Get-NetFirewallApplicationFilter | Select-Object -First 1; # Assumes only one filter
                $pf = $_ | Get-NetFirewallPortFilter | Select-Object -First 1; # Assumes only one filter
                $if = $_ | Get-NetFirewallInterfaceTypeFilter | Select-Object -First 1; # Assumes only one filter

                New-Object -Type PSCustomObject -Property @{
                  Name = $_.Name
                  DisplayName = $_.DisplayName
                  Description = $_.Description
                  Enabled = $_.Enabled
                  Action = $_.Action.toString()
                  Direction = $_.Direction.toString()
                  EdgeTraversalPolicy = $_.EdgeTraversalPolicy.toString()
                  Profile = $_.Profile.toString()
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
            } | Convertto-json

}

function delete{
    write-host "Deleting $($name)..."
    remove-netfirewallrule -name $name
}


function create {

    $mainParams = @{ 
        Name = $name;
        Enabled = $enabled;
        DisplayName = $displayName;
        Description = $description;
        Action = $action;
        Direction = $direction;
        EdgeTraversalPolicy = $edgeTraversalPolicy;
        Profile = $profile;
    }
    
    $extraParams = @{}
    
    #
    # port filter
    #
    if ($protocol) {
        $extraParams.Add("Protocol", $protocol)
    }
    if ($protocolType) {
        $extraParams.Add("ProtocolType", $protocolType)
    }
    if ($protocolCode) {
        $extraParams.Add("ProtocolCode", $protocolCode)
    }
    if ($icmpType) {
        $extraParams.Add("IcmpType", $IcmpType)
    }
    if ($localPort) {
        $extraParams.Add("LocalPort", $LocalPort)
    }
    if ($remotePort) {
        $extraParams.Add("RemotePort", $RemotePort)
    }

    #
    # Program filter
    #
    if ($program) {
        $extraParam.Add("Program", $program)
    }
    
    #
    # Interface filter
    #
    if ($interfaceTypes) {
        $extraParams.Add("InterfaceTypes", $interfaceTypes)
    }

    # Host filter
    if ($localIp) {
        $extraParams.Add("LocalIp", $localIp)
    }
    if ($remoteIp) {
        $extraParams.Add("remoteIp", $remoteIp)
    }
    
    New-NetFirewallRule @mainParams @extraParams
}

switch ($target) {
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
        write-error "invalid target: $($target)"
    }
}