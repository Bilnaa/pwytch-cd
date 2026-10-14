# pwytch-cd

Repo de **déploiement** (CD) de Pwytch : uniquement les fichiers Kubernetes. Un runner GitHub installé sur la machine de dev les applique sur Minikube.

Le code des services et la CI (tests, build et publication des images) sont dans le repo [Bilnaa/pwytch](https://github.com/Bilnaa/pwytch).

## Séparation CI / CD

| | Repo CI : `pwytch` | Repo CD : `pwytch-cd` |
|---|---|---|
| Contenu | code des 7 services, Dockerfiles, workflows de build | manifests Kubernetes, workflows de déploiement |
| Rôle | construire et publier les images sur ghcr.io, taguées avec le sha du commit | décrire ce qui tourne sur le cluster et le déployer |
| Tourne sur | runners GitHub | runner self-hosted (VM, à côté de Minikube) |

Le lien entre les deux : la CI publie des images taguées par sha, le tag est ensuite écrit dans les manifests de ce repo. Le changement de tag déclenche le déploiement.

## Organisation du repo

```
k8s/dev/     manifests du namespace dev
k8s/prod/    manifests du namespace prod
.github/workflows/deploy-dev.yml    push sur main -> kubectl apply -f k8s/dev (automatique)
.github/workflows/deploy-prod.yml   lancement manuel -> kubectl apply -f k8s/prod
```

Dev et prod sont déployés indépendamment, chacun dans son namespace. Les fichiers sont volontairement simples (pas de Helm) : le chart Helm et ArgoCD viennent après, en bonus.

## Règles

- Les secrets ne sont jamais dans ce repo : ils sont créés à part dans le cluster.
- Les tags d'images sont des sha de commit du repo CI, jamais `latest`.
