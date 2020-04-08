#!/usr/bin/env bash
set -e -o pipefail
[ -z "$wire_server_deploy_root" ] && "Please source env.sh in the root of wire-server-deploy" && exit 1

# This script will install all poetry provided binaries into third_party/bin.
# It exists because we want to provide some tools on $PATH to wire_server_deploy users,
# but those tools are installed via Poetry and Poetry doesn't let you execute
# scripts in any other way than `poetry shell` or `poetry run`.

# Thus, we have to roll our own little piece of cursed code that will look at
# installed binaries within the poetry virtualenv and installs them to
# third_party/bin. (caveat: not from third_party/venv, but the venv that poetry
# itself creates and manages - third_party/venv exists to force poetry to run a
# given Python version, and allows us to install poetry without system
# administrator privileges).

# Run everything in a subshell that lives in third_party/ - poetry expects
# to run from the CWD where the project lives.
(
    set -e -o pipefail
    cd "$wire_server_deploy_root/third_party"
    mkdir -p bin

    # Retrieve the poetry venv path. There seems to be no official API for
    # this, so we use an env var from within poetry run.
    venv="$(venv/bin/poetry run sh -c 'echo $VIRTUAL_ENV')"
    echo "Poetry venv at: $venv"

    # Iterate over all bin/ files in poetry's venv.
    for f in $venv/bin/*; do
        base="$(basename "$f")"
        # Skip activate, as we're already doing it's work with env.sh.
        if [ "$base" == activate ]; then
            continue
        fi

        # We cannot just symlink this binary to third_party/bin, as Python
        # launcher scripts determine their location on the filesystem when
        # settings up things like PYTHONHOME, etc. Thus, for every target
        # binary, we must create a script on disk that will exec into the
        # target script.
        target="$wire_server_deploy_root/third_party/bin/$base"

        rm -f $target
        cat >"$target" <<EOF
#!/usr/bin/env bash
# Generated by third_party/poetry-install.sh
exec "$venv/bin/$base" "\$@"
EOF
        chmod +x "$target"
    done
)