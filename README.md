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

## Secrets

Les secrets ne sont dans aucun fichier : on les crée à la main, une fois par namespace, avant de déployer. Les valeurs sont aléatoires. Les noms sont ceux que les manifests référencent (`postgres-credentials`, `database-urls`, `jwt`).

```bash
NS=dev   # puis NS=prod
PW=$(openssl rand -hex 16)
DB="postgres:$PW@postgres:5432"

kubectl -n $NS create secret generic postgres-credentials \
  --from-literal=POSTGRES_USER=postgres \
  --from-literal=POSTGRES_PASSWORD="$PW"

# le driver dépend du service : psycopg, psycopg_async ou asyncpg
kubectl -n $NS create secret generic database-urls \
  --from-literal=main="postgresql+psycopg://$DB/main" \
  --from-literal=live_chat="postgresql+psycopg_async://$DB/live_chat" \
  --from-literal=replay="postgresql+asyncpg://$DB/replay" \
  --from-literal=search="postgresql+asyncpg://$DB/search" \
  --from-literal=bookmarks="postgresql+psycopg://$DB/bookmarks" \
  --from-literal=stats="postgresql+psycopg://$DB/stats"

kubectl -n $NS create secret generic jwt \
  --from-literal=secret="$(openssl rand -hex 32)"
```

Le namespace doit exister (`kubectl apply -f k8s/$NS/00-namespace.yaml`). Pour refaire un secret : `kubectl -n $NS delete secret <nom>`, le recréer, puis `kubectl -n $NS rollout restart deployment`. Le mot de passe postgres n'est lu qu'à la création du volume : si on le change, il faut aussi supprimer le volume (`kubectl -n $NS delete pvc data-postgres-0`).

## Accéder aux applications

Chaque environnement a son Ingress (ingress-nginx, addon `minikube addons enable ingress`) : `http://pwytch.dev:8080` pour dev et `http://pwytch.prd:8080` pour prod. Tout passe par `main`, qui sert le front et `/api`.

Les noms ne sont pas dans un DNS : il faut les déclarer sur la machine qui ouvre le navigateur, dans `/etc/hosts` :

```
127.0.0.1  pwytch.dev pwytch.prd
```

Minikube tourne dans une VM Lima : le contrôleur d'ingress est exposé sur le port 8080 de la VM par un service systemd (`ingress-forward`, un `kubectl port-forward` limité à `127.0.0.1`), que Lima relaie vers `127.0.0.1:8080` de la machine hôte. Le port 80 n'est pas utilisé : macOS ne permet de l'ouvrir que sur toutes les interfaces, donc visible du réseau. Si la page ne répond plus, vérifier ce service dans la VM : `systemctl status ingress-forward`.

Test sans modifier `/etc/hosts` : `curl --resolve pwytch.dev:8080:127.0.0.1 http://pwytch.dev:8080/api/health`.

## Règles

- Les secrets ne sont jamais dans ce repo : ils sont créés à part dans le cluster.
- Les tags d'images sont des sha de commit du repo CI, jamais `latest`.
