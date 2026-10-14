# ArgoCD (GitOps, US 6)

Une Application ArgoCD par environnement, qui suit ce repo (branche `main`) :

| Application | Chemin | Namespace | Sync |
|---|---|---|---|
| `pwytch-dev` | `k8s/dev` | `dev` | automatique (`selfHeal`, sans `prune`) |
| `pwytch-prod` | `k8s/prod` | `prod` | manuel |

Les Secrets (`postgres-credentials`, `database-urls`, `jwt`) ne sont pas dans Git : ArgoCD ne les connaît pas et ne les touche pas.

## Installation

Version épinglée : **v3.5.5**, installation standard (tous les composants), dans le namespace `argocd`. `--server-side` est nécessaire car les CRD sont trop grosses pour `kubectl apply` classique.

```bash
kubectl create namespace argocd
kubectl apply -n argocd --server-side --force-conflicts \
  -f https://raw.githubusercontent.com/argoproj/argo-cd/v3.5.5/manifests/install.yaml
kubectl -n argocd wait --for=condition=Ready pod --all --timeout=300s
```

## Accès à l'interface

Le port-forward est lancé à la demande (jamais plus large que `127.0.0.1`, port > 1024). Dans la VM Lima, Lima le relaie vers `127.0.0.1` du Mac :

```bash
kubectl -n argocd port-forward --address 127.0.0.1 svc/argocd-server 8081:443
```

Puis ouvrir https://127.0.0.1:8081 (certificat auto-signé à accepter). Test : `curl -k https://127.0.0.1:8081`.

Compte `admin`, mot de passe initial lu dans le cluster (ne jamais le copier dans Git) :

```bash
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath='{.data.password}' | base64 -d; echo
```

## Appliquer les Applications

ArgoCD lit `main` : les fichiers doivent d'abord être mergés. Ensuite, une seule fois :

```bash
kubectl apply -f argocd/pwytch-dev.yaml -f argocd/pwytch-prod.yaml
kubectl -n argocd get applications
```

Dev se synchronise seul à chaque commit sur `main`. Prod apparaît `OutOfSync` dès qu'un commit change `k8s/prod`, sans rien déployer.

## Synchroniser la prod à la main

Depuis l'UI : application `pwytch-prod`, bouton **SYNC**, puis **SYNCHRONIZE**. En CLI `argocd` : `argocd app sync pwytch-prod`. Sans CLI, on peut déclencher l'opération par kubectl :

```bash
kubectl -n argocd patch application pwytch-prod --type merge \
  -p '{"operation":{"sync":{"revision":"main"}}}'
```

## Coexistence avec les workflows runner

Deux mécanismes déploient le même contenu (`k8s/dev` et `k8s/prod`) : le CD par runner self-hosted (`kubectl apply -f k8s/<env>`, US 3) et ArgoCD (GitOps, US 6). Les deux appliquent exactement les mêmes manifests, donc ils ne se contredisent pas : le résultat est identique quel que soit celui qui passe en premier. ArgoCD ajoute la détection de dérive (`selfHeal` en dev) et la visualisation de l'état ; il adopte les ressources déjà présentes sans les recréer.
