  // This provides support to call VyOS Https Server API's as per operation mode

  let fs = require("fs");
  function quoteForShell(s) {
      if (s == null)
          return "''";

      let parts = split(s, "'");
      return "'" + join("'\"'\"'", parts) + "'";
  }

  return{
     vyos_api_call: function(op_arg, op, host, key) {
      // Basic argument validation
      if (!key) {
          printf("ERROR: Missing API key\n");
          return null;
      }
      if (!host) {
          printf("ERROR: Missing host\n");
          return null;
      }
      if (!op) {
          printf("ERROR: Missing op\n");
          return null;
      }

      // Determine endpoint and payload based on op
      let endpoint;
      let payloadObj = { op: op, key: key };

      if (op == "load" || op == "merge") {
          endpoint = "/config-file";

          if (op_arg && op_arg.file) {
              payloadObj.file = op_arg.file;
          } else if (op_arg && op_arg.string) {
              payloadObj.string = op_arg.string;
          } else {
              printf("ERROR: Unsupported op_arg for op %s\n", op);
              return null;
          }

      } else if (op == "showConfig") {
          endpoint = "/retrieve";

          if (op_arg && op_arg.path) {
              payloadObj.path = op_arg.path;
          } else {
              // default: whole config
              payloadObj.path = [];
          }

      } else if (op == "show") {
          // NEW: Support for /show endpoint (operational commands)
          endpoint = "/show";

          if (op_arg && op_arg.path) {
              payloadObj.path = op_arg.path;
          } else {
              printf("ERROR: Missing path for show operation\n");
              return null;
          }

      } else if (op == "set" || op == "delete") {
          // NEW: Support for /configure endpoint with set/delete operations
          endpoint = "/configure";

          if (op_arg && op_arg.path) {
              payloadObj.path = op_arg.path;
          } else {
              printf("ERROR: Missing path for op %s\n", op);
              return null;
          }

          // For "set", value is optional (some commands are flags without values)
          if (op == "set" && op_arg && op_arg.value != null) {
              payloadObj.value = op_arg.value;
          }

      } else {
          printf("ERROR: Unsupported op: %s\n", op);
          return null;
      }

      // Convert payload to JSON string
      let payloadStr = sprintf("%J", payloadObj);
      let url        = host + endpoint;

      // Build the curl command - /configure and /config-file use different timeouts
      let cmd;
      if (endpoint == "/configure") {
          cmd = sprintf(
              "curl -skL --connect-timeout 3 -m 5 -X POST %s " +
              "-H 'Content-Type: application/json' -d %s",
              quoteForShell(url),
              quoteForShell(payloadStr)
          );
      } else if (endpoint == "/config-file") {
          // config-file operations need more time to validate and commit
          cmd = sprintf(
              "curl -skL --connect-timeout 10 -m 30 -X POST %s " +
              "--form-string data=%s --form key=%s",
              quoteForShell(url),
              quoteForShell(payloadStr),
              quoteForShell(key)
          );
      } else {
          cmd = sprintf(
              "curl -skL --connect-timeout 3 -m 5 -X POST %s " +
              "-H 'Content-Type: application/json' -d %s",
              quoteForShell(url),
              quoteForShell(payloadStr)
          );
      }

      // Run curl and capture output
      let proc = fs.popen(cmd, "r");
      if (!proc) {
          printf("ERROR: Failed to start curl\n");
          return null;
      }

      let out = proc.read("all");
      proc.close();

      return out;
    }
  };
