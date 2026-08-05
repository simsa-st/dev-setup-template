# secrets/

Everything in this directory except this file and `*.example` is gitignored.

`setup/config/shell/bashrc-extra` sources `secrets/env` if it exists, so tokens
land in the environment without ever being committed:

```bash
cp env.example env && chmod 600 env && $EDITOR env
```

## Getting secrets onto a new machine

Pick one and write the choice into the repo README, because it is the step
people forget when setting up their next machine:

| Approach | Good for | Cost |
|---|---|---|
| Password manager (1Password/Bitwarden CLI) | most setups | one login per machine |
| `age`/`sops`-encrypted `env.age` committed here | machines without a password-manager CLI | key distribution is on you |
| Manual `scp` from the laptop | one or two machines | drifts silently |

Do **not** commit plaintext secrets and rely on directory permissions. Git does
not preserve modes, every clone and every backup carries the plaintext, and the
history keeps it after deletion.
