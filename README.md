# pwytch-cd

Repo de **déploiement** (CD) de Pwytch. ArgoCD suit ce repo et applique son contenu sur le cluster Kubernetes.

Le code des services et la CI (tests, build et publication des images) sont dans le repo [Bilnaa/pwytch](https://github.com/Bilnaa/pwytch).

## Séparation CI / CD

| | Repo CI : `pwytch` | Repo CD : `pwytch-cd` |
|---|---|---|
| Contenu | code des 7 services, Dockerfiles, workflows | chart Helm, values par environnement, applications ArgoCD |
| Rôle | construire et publier les images sur ghcr.io, taguées avec le sha du commit | décrire ce qui tourne sur le cluster |
| Qui le lit | les développeurs, GitHub Actions | ArgoCD (repo public, sans identifiants) |

Le lien entre les deux : quand la CI publie des images, elle commit le nouveau tag dans les values de dev de ce repo. ArgoCD voit le commit et déploie. Pour la prod, la promotion d'un tag est manuelle, depuis ce repo.

## Organisation du repo

```
charts/pwytch/        chart Helm (templates des 7 services, postgres, redis, mosquitto)
envs/dev/values.yaml  values de l'environnement de dev (tags mis à jour par la CI)
envs/prod/values.yaml values de la prod (tags promus à la main)
argocd/dev.yaml       Application ArgoCD de dev (sync automatique)
argocd/prod.yaml      Application ArgoCD de prod (sync manuel)
```

Un seul chart, deux fichiers de values : dev et prod ne diffèrent que par leurs values, jamais par leurs templates.

## Règles

- Les secrets ne sont jamais dans ce repo : ils sont créés à part dans le cluster.
- Les tags d'images sont des sha de commit du repo CI, jamais `latest`.
