{%

let data = (type(rc) == "object" && type(rc.data) == "object") ? rc.data : {};
let ca_map = (type(data.ca) == "object") ? data.ca : {};
let cert_map = (type(data.certificate) == "object") ? data.certificate : {};

let ca_names = keys(ca_map);
let cert_names = keys(cert_map);
%}
pki {
{%
/* ---- CA blocks ---- */
for (let i = 0; i < length(ca_names); i++) {
    let name = ca_names[i];
    let ca = ca_map[name] || {};
%}
    ca {{name}} {
        certificate {{ca.certificate}}
{%
    if (type(ca.private) == "object" && ca.private.key) {
%}
        private {
            key {{ca.private.key}}
        }
{%
    }
%}
    }
{%
}

/* ---- certificate blocks ---- */
for (let i = 0; i < length(cert_names); i++) {
    let name = cert_names[i];
    let cert = cert_map[name] || {};
%}
    certificate {{name}} {
        certificate {{cert.certificate}}
{%
    if (type(cert.private) == "object" && cert.private.key) {
%}
        private {
            key {{cert.private.key}}
        }
{%
    }
%}
    }
{%
}
%}
}


