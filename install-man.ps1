function Install-ManPages {
    param([string]$RepoPath)
    wsl -- bash -c "
        find /mnt/\$(echo '$RepoPath' | sed 's|C:/|c/|')/man -name '*.[0-9]' | while read f; do
            sec=\${f##*.}
            mkdir -p ~/.local/share/man/man\$sec
            cp \$f ~/.local/share/man/man\$sec/
        done
        mandb -q
    "
}

