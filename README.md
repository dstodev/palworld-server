# Game server environment

## Requirements

- [Docker](https://docs.docker.com/get-docker/)

## Configure server

## Start server

`./script/start-server.sh --update`

## Stop server

**You may lose data** if you stop the server using this script, as it may not
save first.

`./script/stop-server.sh`

## Other commands

- Fix Docker permissions to access server files (requires root permissions):  
  `./script/fix-permissions.sh`

- Rebuild Docker image (useful for updating server files):  
  `docker compose -f docker/compose.yml build --no-cache palworld-server`

- Browse the Docker container with a bash shell:  
  `docker compose -f docker/compose.yml run --entrypoint /bin/bash palworld-server`

- Attach to the server screen:  
  `screen -r palworld-server`

  Keybinds:
  - `CTRL+A` then `D` to detach

<!-- line break -->

- Attach most-recent log file to the terminal:  
  `./attach-latest-log.sh`

  Keybinds:
  - `SHIFT+F` while attached to await more log text (useful while server is
              still running)
  - `CTRL+C` while awaiting log text to stop awaiting & resume navigation
  - `Q` while navigating to exit logfile

## Permissions

Running `./script/start-server.sh --update` will cause:

- Group `server-group` exists
- User `server-user` (in group `server-group`) exists
- Host user added to group `server-group` *
- Server files owned by `server-group`
- Repo files owned by `server-group` (for permission to e.g. write backups to `./backups`)

> \* Changes to a user's group membership will not take effect until e.g. the
> user logs out and back in again.
