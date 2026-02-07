{% if (length(lans) > 0): %}
dns {
    forwarding {
{%      for (let lan in lans): %}
        allow-from {{ lan.net_ip_prefix }}
{%      endfor %}
        cache-size 0
{%      for (let lan in lans): %}
        listen-address {{ lan.lan_ip }}
{%      endfor %}
    }
}
{% endif %}
