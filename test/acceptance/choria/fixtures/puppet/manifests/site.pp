node 'choria-proxy' {
  include choria
  include choria::broker
}

node default {
  include choria
}
