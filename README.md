# zprompt
Shell prompt, rethought from scratch to suit 21st century agi researchers.

## Usage

Configure machine metadata: 
```
Z_MACHINE_NAME=hostname
# Supported classes:
#   client   hidden machine marker; intended for local client machines
#   gpu      ◆
#   storage  ▣
#   generic  ◇
Z_MACHINE_CLASS=client
```

for zsh:

# ~/.zshrc
source ~/.config/zprompt/prompt.zsh

for bash:

# ~/.bashrc
source ~/.config/zprompt/prompt.bash

research context is repository-local:

ctx scaling-law    # set
ctx                # print
ctx -              # clear

and is stored in:

.git/z-context
