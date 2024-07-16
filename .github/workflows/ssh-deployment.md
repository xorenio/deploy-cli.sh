# ssh-deployment

This action will install this repo on to a server via ssh.


## setup

### Server to deploy to

- Ssh key in github deployment key
- apt install git curl  


Please ensure you have set up the following repository secrets:

`Github.com > repo > settings > secrets and variables > actions > Repository secrets`


|     Secret    |   Description   |
|    --------   |    --------     |
| DEPLOYMENT_SSH_HOST | The hostname or IP address of the server for deployment. |
| DEPLOYMENT_SSH_HOST_KNOWN_ENTRY | The known host entry for the SSH host server. |
| DEPLOYMENT_SSH_USERNAME | The SSH username for connecting to the deployment server. |
| DEPLOYMENT_SSH_PRIVATE_KEY | The private SSH key used for connecting to the deployment server. |
| DEPLOYMENT_PATH | The path on the server to the live deployment. |
| DEPLOYMENT_GITHUB_TOKEN | A Github api token with access to this repos for commit logs. |

### Have you setup repo deployment key for remote server cloning?

You need to login to the server to be deployed to and run the following commands 

```bash
$ ssh-keygen -t ed25519 -N "" -C "server@domain.com" -f ~/.ssh/id_ed25519
$ cat ~/.ssh/id_ed25519.pub
```

Take the output from the cat command and put that in as a deployment key.

Then accept the github.com ssh key

```bash
$ ssh git@github.com -T
```
