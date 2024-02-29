# Game server environment

## Requirements

- [Docker](https://docs.docker.com/get-docker/)

All host scripts are tested on `Ubuntu 22.04.3 LTS`

## Configure server

After starting for the first time, server configuration files are created in:

- `./server-files/` (root)
- `./server-files/Pal/Saved/Config/LinuxServer/` (configs)

Edit these files to configure the server.

## Ports

The server uses the following ports:

- `UDP 8211` (Game)
- `TCP 25575` (RCON)

These ports are configurable in `./docker/.env`.

## Start server

This script will download the server files and start the server. After starting
for the first time, you do not need to use the `--update` flag unless you want
to update the server files.  
`./script/start-server.sh --update`

## Stop server

This script will save the world and gracefully stop the server.  
`./script/stop-server.sh`

This script requires RCON (see below).

To forcefully stop the server, pass the `--force` flag:  
`./script/stop-server.sh --force`

this will stop the server without saving the world or backing up server files.

## Restart server

To restart the server:  
`./script/stop-server.sh --restart`

You may schedule automatic restarts using e.g. a cron job.
See `./script/stop-server.sh` for details.

## RCON

This environment supports RCON for sending commands to the server:  
`./script/send-rcon.sh MyRconCommand`

This script assumes the server is accessible via `localhost`, but the
underlying C++ client `./rcon/main.cxx` supports sending messages to any host.

To use `send-rcon.sh`, you must first set an RCON password.  
**Without an RCON password, you cannot**:

- Gracefully stop the server using `./script/stop-server.sh`,
  because it uses RCON to send the shutdown command.
- Use `./script/backup.sh` without the `--force` flag, because it uses RCON to
  send the save command.

To set an RCON password, edit `./server-files/Pal/Saved/Config/LinuxServer/PalWorldSettings.ini`:

- set `RCONEnabled=True`
- set `RCONPort=25575` (or update `./docker/.env` to match)
- set `AdminPassword="YourRconPassword"`

then make a file `./rcon/secret` containing the same password in plaintext.

## Backups

This script creates a backup of important server files to `./backups/`:  
`./script/backup.sh --force`

Backups are created automatically when the server is stopped via `stop-server.sh`.

You should schedule automatic backups using e.g. a cron job. See `./script/backup.sh`
for details.

### Restore from backup

To restore from backup, unzip the backup file you want:  
`tar -xjf ./backups/backup-timestamp.tar.bz2`

Replace the files in `./server-files/Pal/Saved` with the files from the backup.

## Update server

To update server files, use the `--update` flag like when first
starting the server:  
`./script/start-server.sh --update`

Palworld updates may change certain config files. When
this happens, you may wish to only restore save files:

1. Stop the server:  (`--force` if necessary)  
   `./script/stop-server.sh`
2. Make sure you have a backup of `./server-files/Pal/Saved`
3. Delete `./server-files/`:  
   `rm -rf ./server-files/`
4. Populate the server files:  
   `./script/start-server.sh --update && ./script/stop-server.sh --force`
5. Restore your backup of `./server-files/Pal/Saved/SaveGames`
6. Take note of the server name: `./server-files/Pal/Saved/SaveGames/0/<YOUR_SERVER_NAME>`
7. Update `./server-files/Pal/Saved/Config/LinuxServer/GameUserSettings.ini`:  
   Set `DedicatedServerName=YOUR_SERVER_NAME`
8. Re-set your configurations in `./server-files/Pal/Saved/Config/LinuxServer/`
9. Start the server:
   `./script/start-server.sh`

Try this if an update cuases your world or characters to reset.

## Other commands

- Rebuild Docker image:  
  `docker compose -f docker/compose.yml build --no-cache palworld-server`
- Browse the Docker container with a bash shell:  
  `docker compose -f docker/compose.yml run --entrypoint /bin/bash palworld-server`
- Attach to the server screen:  
  `screen -r palworld`
  Keybinds:
  - `CTRL+A` then `D` to detach
  - `CTRL+C` to stop the server

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
- Server files owned by `server-user:server-group`
- Repo files owned by `server-group` (for permission to e.g. write backups to `./backups`)

> \* Changes to a user's group membership will not take effect until e.g. the
> user logs out and back in again.
