# Démo : runner puis ArgoCD

Le même changement déployé deux fois : d'abord par le runner self-hosted avec ArgoCD éteint (US 3), puis par ArgoCD avec le runner coupé (US 6). Tout passe par `demo/demo.sh`, lancé depuis le Mac dans ce repo ; `kubectl` passe par la VM Lima `gh-runner`.

Avant : `limactl start gh-runner`, puis `limactl shell gh-runner minikube start`. Ouvrir l'onglet Actions du repo et l'UI ArgoCD (http://127.0.0.1:8081 dans la VM).

## Acte 1 : ArgoCD éteint, le runner déploie

```bash
demo/demo.sh runner   # ArgoCD à 0 pod, deploy-dev actif
demo/demo.sh drift    # search passe à 3 replicas à la main : personne ne corrige pendant 60 s
demo/demo.sh bump     # change les replicas de stats dans k8s/dev, commit, push
gh run watch -R Bilnaa/pwytch-cd   # deploy-dev tourne sur le runner : kubectl apply, rollout
```

À montrer : le job dans Actions, puis `stats` à la nouvelle valeur. Le runner réapplique tout `k8s/dev`, donc `search` revient aussi à 1, mais seulement parce qu'on a poussé un commit.

Prod : Actions > deploy-prod > Run workflow (promotion d'un tag).

## Acte 2 : ArgoCD allumé, le runner coupé

```bash
demo/demo.sh argo     # ArgoCD rallumé, deploy-dev désactivé : seul ArgoCD déploie
demo/demo.sh drift    # search à 3 : ArgoCD (selfHeal) le remet à 1 en quelques secondes
demo/demo.sh bump     # push : ArgoCD relit le repo et synchronise pwytch-dev
```

À montrer dans l'UI : `pwytch-dev` qui passe OutOfSync puis Synced tout seul, et `pwytch-prod` qui reste en sync manuel (bouton SYNC).

## Après

```bash
demo/demo.sh normal   # ArgoCD allumé ET deploy-dev actif, l'état habituel
demo/demo.sh status
```

`bump` laisse des commits `demo: stats …` sur `main` : stats alterne entre 1 et 2 replicas, relancer `bump` pour revenir à 1.
