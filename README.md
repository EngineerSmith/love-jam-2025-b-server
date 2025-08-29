# love-jam-2025-b-server
The server that handles the game for https://github.com/EngineerSmith/love-jam-2025-b

# Args
| Arg | default | description |
| --- | --- | --- |
| `--port <port>` | `53135` | Defines the server UDP port for game clients. Must be within the range 1024-65535. |
| `--mmport <portnum>` | `80` | Defines the TCP port for the MintMouse web console. Can be any numeric value. |
| `--mmwhitelist <CIDR>` | `127.0.0.1` and `192.168.0.0/16` | Specifies a CIDR block for the MintMousse web console whitelist. Any added value will replace the default entries. Separate multiple CIDRs with a space. For example, to whitelist the defaults you would use `--mmwhitelist 127.0.0.1 192.168.0.0/16`. |