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
          fprintf(stderr, "Missing API key\n");
          return null;
      }
      if (!host) {
          fprintf(stderr, "Missing host\n");
          return null;
      }
      if (!op) {
          fprintf(stderr, "Missing op\n");
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
              fprintf(stderr, "Unsupported op_arg for op %s\n", op);
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
              fprintf(stderr, "Missing path for show operation\n");
              return null;
          }

      } else if (op == "set" || op == "delete") {
          // NEW: Support for /configure endpoint with set/delete operations
          endpoint = "/configure";

          if (op_arg && op_arg.path) {
              payloadObj.path = op_arg.path;
          } else {
              fprintf(stderr, "Missing path for op %s\n", op);
              return null;
          }

          // For "set", value is required
          if (op == "set") {
              if (op_arg && op_arg.value != null) {
                  payloadObj.value = op_arg.value;
              } else {
                  fprintf(stderr, "Missing value for set operation\n");
                  return null;
              }
          }

      } else {
          fprintf(stderr, "Unsupported op: %s\n", op);
          return null;
      }

      // Convert payload to JSON string
      let payloadStr = sprintf("%J", payloadObj);
      let url        = host + endpoint;

      // Build the curl command - /configure endpoint uses JSON body, not form data
      let cmd;
      if (endpoint == "/configure") {
          cmd = sprintf(
              "curl -skL --connect-timeout 3 -m 5 -X POST %s " +
              "-H 'Content-Type: application/json' -d %s",
              quoteForShell(url),
              quoteForShell(payloadStr)
          );
      } else {
          cmd = sprintf(
              "curl -skL --connect-timeout 3 -m 5 -X POST %s " +
              "--form-string data=%s --form key=%s",
              quoteForShell(url),
              quoteForShell(payloadStr),
              quoteForShell(key)
          );
      }

      // Run curl and capture output
      let proc = fs.popen(cmd, "r");
      if (!proc) {
          fprintf(stderr, "Failed to start curl\n");
          return null;
      }

      let out = proc.read("all");
      proc.close();

      return out;
    }
  };
