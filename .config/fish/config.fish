# Get rid of welcome note
set -U fish_greeting ""

# Environment variables & prompt
set -gx QT_QPA_PLATFORMTHEME qt6ct
starship init fish | source

# Add local bins to PATH
fish_add_path ~/.local/bin ~/bin

fish_add_path /home/saravanan/.spicetify
