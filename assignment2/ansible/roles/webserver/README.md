# webserver

Installs Apache httpd on Amazon Linux 2023, applies two settings from a template
(`ServerTokens`, `ServerSignature`), renders the home page from a template, and
starts and enables the service. Every task is idempotent: a second run reports `changed=0`.

| Variable (defaults/main.yml) | Default |
|---|---|
| `webserver_package`, `webserver_service` | `httpd` |
| `webserver_docroot` | `/var/www/html` |
| `webserver_conf_dir` | `/etc/httpd/conf.d` |
| `webserver_title`, `webserver_message` | Page heading and text |
| `webserver_server_tokens`, `webserver_server_signature` | `Prod`, `"Off"` |

Used by `../../site.yml` (hosts `role_web`, over SSM) and, in Session 2, by the Packer build.
