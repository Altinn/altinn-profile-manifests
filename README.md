# altinn-profile-manifests
Gitops manifests for everything that is Profile

## Layout

- `manifests/pre-deploy/<env>`: identity, vault, external secrets, config and the database migration job. Flux applies it first.
- `manifests/deploy/<env>`: the app. Flux applies it after pre-deploy is healthy.
- `manifests/image/<env>`: the app image tag the environment runs, used by both stages.
- `flux/syncroot/<env>`: the Flux resources the platform applies, one overlay per environment.

Environments: `at22`, `at23`, `yt01`, `tt02`, `prod`.

## How a change reaches an environment

**Publish** pushes `profile/manifests` and `profile/syncroot` to `altinncr.azurecr.io` for commits on `main`, tagged with the short sha. Each environment's Flux follows the artifact tag with its own name (`at23`, `tt02`, ...). Deploying means moving that tag.

| Environment | How it changes |
|---|---|
| AT22, AT23 | Automatically: **Publish** runs after every merge to `main` that changes config, and the app repo bumps the image tag after each build |
| YT01 | Run **Deploy**. It is ad hoc for now: nothing moves it automatically |
| TT02, PROD | Run **Deploy**. It waits for the approval gate before anything is committed |

## Deploy

Run **Deploy** from `main`, with the environment and one of:

| Input | Effect |
|---|---|
| `image_tag` | A new app version. It is pinned for the environment with a commit on `main`, published and deployed in one run |
| `commit` | An earlier commit on `main`, as it is (a rollback). Nothing is committed |
| neither | The tip of `main`, for config changes that need no new app version |

TT02 and PROD only take releases (`X.Y.Z`) and hotfix builds (`hotfix-...`). A release only goes to PROD if TT02 is pinned to it. A hotfix build, and a rollback with `commit`, are exempt.

The app version is data in `manifests/image/<env>/kustomization.yaml`, so what an environment runs is always the commit it follows, and the git history shows who moved it and when.

## From the app repo

After building an image for AT22 or AT23, the app repo dispatches `update_image_tag` with a comma separated list of environments and the image tag. **Bump image tag** commits it for all of them in one commit to `main` and starts **Publish**. YT01, TT02 and PROD are never bumped this way, because Publish only moves the AT22 and AT23 tags. They change with **Deploy**.

## Checks

`scripts/validate.sh` builds every overlay, checks that each syncroot overlay points at its own environment, and that the pinned image exists. It runs on pull requests and before every publish, and can be run locally.

## Workflows

The file name starts with how the workflow is started:

- `ci-cd-*.yml`: started by an event.
- `dispatch-*.yml`: started by hand.
- `workflow-*.yml`: reusable, called by other workflows and not started directly.

| File | Name in the Actions tab | Started by |
|---|---|---|
| `ci-cd-publish.yml` | Publish | A push to `main` that changes config or the publish workflows |
| `ci-cd-bump-image-tag.yml` | Bump image tag | The app repo, with the `update_image_tag` event |
| `dispatch-deploy.yml` | Deploy | Someone, from `main` |
| `workflow-publish-artifacts.yml` | Publish artifacts (reusable) | Publish and Deploy |
| `workflow-promote.yml` | Promote (reusable) | Publish and Deploy |
| `workflow-validate.yml` | Validate | Pull requests, and before every publish |

## Needed in the repository settings

- The `DIS_SYNCROOT_AZURE_*` secrets, created by the platform team.
- GitHub environments `TT02` and `PROD`, with required reviewers if the gates should wait for someone.
- A token in the app repo that may dispatch events to this repo.
- `main` must not require pull requests for now. **Deploy** and **Bump image tag** push their pin commits straight to `main` with the workflow's own token, which can't be added to a ruleset bypass list. Requiring pull requests needs a GitHub App that can bypass the ruleset (requested in Altinn/altinn-platform#4493).
