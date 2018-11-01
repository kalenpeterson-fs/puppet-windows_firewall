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
                  Enabled = $_.Enabled.toString()
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