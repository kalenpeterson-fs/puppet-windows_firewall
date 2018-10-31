param(
    [String] $Target,
    [String] $Name,
    [String] $DisplayName,
    [String] $Description,
    $Enabled,
    $Action,
    [String] $Protocol,
    [Int]    $IcmpType,
    $Profile,
    [String] $Program,
    $Direction,
    [String] $LocalIp,
    [String] $RemoteIp,
    [String] $ProtocolType,
    [Int]    $ProtocolCode,
    [Int]    $LocalPort,
    [Int]    $RemotePort,
    $EdgeTraversalPolicy,
    $InterfaceType
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
    write-host "Deleting $($Name)..."
    remove-netfirewallrule -name $Name
}


function create {

    $mainParams = @{ 
        Name = $Name;
        Enabled = $Enabled;
        DisplayName = $DisplayName;
        Description = $Description;
        Action = $Action;
        Direction = $Direction;
        EdgeTraversalPolicy = $EdgeTraversalPolicy;
        Profile = $Profile;
    }
    
    $extraParams = @{}
    
    #
    # port filter
    #
    if ($Protocol) {
        $extraParams.Add("Protocol", $Protocol)
    }
    if ($ProtocolType) {
        $extraParams.Add("ProtocolType", $ProtocolType)
    }
    if ($ProtocolCode) {
        $extraParams.Add("ProtocolCode", $ProtocolCode)
    }
    if ($IcmpType) {
        $extraParams.Add("IcmpType", $IcmpType)
    }
    if ($LocalPort) {
        $extraParams.Add("LocalPort", $LocalPort)
    }
    if ($RemotePort) {
        $extraParams.Add("RemotePort", $RemotePort)
    }

    #
    # Program filter
    #
    if ($Program) {
        $extraParam.Add("Program", $Program)
    }
    
    #
    # Interface filter
    #
    if ($InterfaceType) {
        $extraParams.Add("InterfaceTypes", $InterfaceType)
    }

    # Host filter
    if ($LocalIp) {
        $extraParams.Add("LocalIp", $LocalIp)
    }
    if ($RemoteIp) {
        $extraParams.Add("remoteIp", $RemoteIp)
    }
    
    New-NetFirewallRule @mainParams @extraParams
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