{%
let data = (type(systeminfo) == "object" && type(systeminfo.data) == "object")
	? systeminfo.data : {};

let og_map   = (type(data["operator-group"]) == "object") ? data["operator-group"] : {};
let user_map = (type(data.user) == "object") ? data.user : {};

let og_names   = keys(og_map);
let user_names = keys(user_map);
let cdata = (type(consoleinfo) == "object" && type(consoleinfo.data) == "object") ? consoleinfo.data : {};

let cdev_map   = (type(cdata.device) == "object") ? cdata.device : {};
let cdev_names = keys(cdev_map);
%}
system {
     console {
{%
for (let i = 0; i < length(cdev_names); i++) {
    let dev_name = cdev_names[i];
    let dev      = (type(cdev_map[dev_name]) == "object") ? cdev_map[dev_name] : {};
    let speed    = dev.speed || null;
%}
        device {{dev_name}} {
{%
    if (speed != null) {
%}
            speed "{{speed}}"
{%
    }
%}
        }
{%
}
%}
    }
    name-server "8.8.8.8"
    login {
{%
for (let i = 0; i < length(og_names); i++) {
    let og_name = og_names[i];
    let og      = og_map[og_name] || {};
    let cp      = (type(og["command-policy"]) == "object") ? og["command-policy"] : {};
    let cp_allow = cp.allow || null;
%}
        operator-group {{og_name}} {
{%
    if (cp_allow) {
%}
            command-policy {
                allow "{{cp_allow}}"
            }
{%
    }
%}
        }
{%
}

for (let i = 0; i < length(user_names); i++) {
    let user_name = user_names[i];
    let u         = user_map[user_name] || {};
    let auth      = (type(u.authentication) == "object") ? u.authentication : {};

    let enc_pw    = auth["encrypted-password"] || null;
    let plain_pw  = auth["plaintext-password"] ? auth["plaintext-password"] : "";
%}
        user {{user_name}} {
{%
    if (type(auth) == "object") {
%}
            authentication {
{%
        if (enc_pw) {
%}
                encrypted-password "{{enc_pw}}"
{%
        }
        if (plain_pw == '' || plain_pw) {
%}
                plaintext-password "{{plain_pw}}"
{%
        }
%}
            }
{%
    }
%}
        }
{%
}
%}
    }
}

