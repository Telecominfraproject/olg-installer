{% if (length(lans) > 0): %}
dhcp-server {
{%  for (let lan in lans): %}
    shared-network-name {{ lan.name }} {
        subnet {{ lan.net_ip_prefix }} {
            lease {{ lan.lease_secs }}
            option {
                default-router {{ lan.lan_ip }}
{%              if (lan.subnet_id == 1): %}
                domain-name vyos.net
{%              endif %}
                name-server {{ lan.lan_ip }}
            }
            range 0 {
                start {{ lan.range_start }}
                stop {{ lan.range_stop }}
            }
            subnet-id {{ lan.subnet_id }}
        }
    }
{%  endfor %}
}
{% endif %}
