admins = { }

modules_enabled = {
  "roster";
  "saslauth";
  "tls";
  "disco";
  "carbons";
  "pep";
  "private";
  "vcard4";
  "vcard_legacy";
  "register";
  "admin_adhoc";
  "ping";
  "uptime";
  "version";
  "time";
}

modules_disabled = {
}

allow_registration = true
c2s_require_encryption = false
s2s_require_encryption = false
s2s_secure_auth = false

authentication = "internal_plain"
storage = "internal"

log = {
  info = "/var/log/prosody/prosody.log";
  error = "/var/log/prosody/prosody.err";
}

pidfile = "/var/run/prosody/prosody.pid"

VirtualHost "localhost"
  enabled = true

VirtualHost "saros-xmpp"
  enabled = true
