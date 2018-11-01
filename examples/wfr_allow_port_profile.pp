# @PDQTestWin
windows_firewall_rule { "puppet - open port in specific profiles":
  ensure         => present,
  direction      => "inbound",
  action         => "allow",
  protocol       => "tcp",
  profile        => ["private", "domain"],
  local_port     => "666",
  interface_type => ["wireless", "wired"],

}