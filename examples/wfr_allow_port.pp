#@PDQTestWin
windows_firewall_rule { "puppet - allow ports 1000-2000":
  ensure    => present,
  direction => "in",
  action    => "allow",
  protocol  => "tcp",
  localport => "1000-2000",
}