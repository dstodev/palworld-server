# Game server environment

## Requirements

- [Docker](https://docs.docker.com/get-docker/)

## Configure server

After starting for the first time, server configuration files are created in

- `./server-files/`
- `./server-files/Pal/Saved/Config/LinuxServer/`

Edit these files to configure the server.

## Start server

This script will download the server files and start the server. After starting
for the first time, you do not need to use the `--update` flag unless you want
to update the server files.

`./script/start-server.sh --update`

## Stop server

This script will save the world and gracefully stop the server.

`./script/stop-server.sh`

## Backups

This script creates a backup of important server files in `./backups/`.

`./script/backup.sh --force`

Backups are created automatically when the server is stopped, and can
be further automated by e.g. a cron job. See `./script/backup.sh` for details.

### Restore from backup

To restore from backup, unzip the backup file you want:

`tar -xjf ./backups/backup-timestamp.tar.bz2`

Replace the files in `./server-files/Pal/Saved` with the files from the backup.

## Other commands

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
