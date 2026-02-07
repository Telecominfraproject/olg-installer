{% if (https_enabled): %}
https {
    {% if (length(https_allow_from) > 0): %}
    allow-client {
        {% for (let a in https_allow_from): %}
        address {{ a }}
        {% endfor %}
    }
    {% endif %}

    {% if (length(https_keys) > 0): %}
    api {
        keys {
            {% for (let k in https_keys): %}
            id {{ k.id }} {
                key {{ k.key }}
            }
            {% endfor %}
        }
        rest {
        }
    }
    {% endif %}

    certificates {
        {% if (https_ca_cert): %}
        ca-certificate {{ https_ca_cert }}
        {% endif %}
        {% if (https_cert): %}
        certificate {{ https_cert }}
        {% endif %}
    }

    port {{ https_port }}
}
{% endif %}
