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

L'interface est servie sur `127.0.0.1:8081` par un service systemd, `argocd-forward` (un `kubectl port-forward --address 127.0.0.1 svc/argocd-server 8081:80`, jamais plus large que `127.0.0.1`, port > 1024). Il démarre avec la machine et redémarre tout seul. Création, une fois, sur la machine qui héberge Minikube :

```bash
sudo tee /etc/systemd/system/argocd-forward.service >/dev/null <<UNIT
[Unit]
Description=Expose the ArgoCD interface on 127.0.0.1:8081 (http)
After=network-online.target docker.service

[Service]
Environment=KUBECONFIG=$HOME/.kube/config
ExecStart=/usr/local/bin/kubectl -n argocd port-forward --address 127.0.0.1 svc/argocd-server 8081:80
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
UNIT
sudo systemctl daemon-reload && sudo systemctl enable --now argocd-forward
```

Si la page ne répond plus : `systemctl status argocd-forward`.

Puis ouvrir http://127.0.0.1:8081 (utilisateur `admin`). Test : `curl http://127.0.0.1:8081`.

Le serveur ArgoCD est en mode `insecure` : il sert du http au lieu de son TLS auto-signé, ce qui évite l'avertissement du navigateur. Ce n'est pas un risque ici, le port n'écoute que sur `127.0.0.1`. Réglage fait une fois, après l'installation :

```bash
kubectl -n argocd patch configmap argocd-cmd-params-cm --type merge -p '{"data":{"server.insecure":"true"}}'
kubectl -n argocd rollout restart deployment argocd-server
```

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

Deux mécanismes déploient le même contenu (`k8s/dev` et `k8s/prod`) : le CD par runner self-hosted (`kubectl apply --server-side --force-conflicts -f k8s/<env>`, US 3) et ArgoCD (GitOps, US 6). Les deux appliquent exactement les mêmes manifests, donc ils ne se contredisent pas : le résultat est identique quel que soit celui qui passe en premier. ArgoCD ajoute la détection de dérive (`selfHeal` en dev) et la visualisation de l'état ; il adopte les ressources déjà présentes sans les recréer.

Pour que les deux cohabitent, les deux appliquent en **server-side** (`ServerSideApply=true` dans les Applications, `--server-side` dans les workflows). Avec un `kubectl apply` classique, le runner effaçait l'annotation de suivi d'ArgoCD (`argocd.argoproj.io/tracking-id`) : la prod, en sync manuel, passait alors entièrement OutOfSync après chaque déploiement par le workflow (dev se répare seul grâce à `selfHeal`). Les deux Applications ignorent aussi `volumeClaimTemplates` du StatefulSet `postgres`, que le cluster complète avec des valeurs par défaut.

ArgoCD ne relit le repo qu'environ toutes les 3 minutes. Juste après un merge, les Applications peuvent donc encore viser l'ancienne révision : `pwytch-prod` apparaît OutOfSync, et le `selfHeal` de dev peut remettre l'ancienne valeur qu'un déploiement du runner vient d'appliquer. Pour forcer la relecture tout de suite : `kubectl -n argocd annotate application pwytch-dev argocd.argoproj.io/refresh=hard --overwrite` (idem pour `pwytch-prod`).
