#!/usr/bin/env bash
# Démo : le même déploiement fait d'abord par le runner (ArgoCD éteint), puis par ArgoCD (runner coupé).
# Se lance depuis le Mac, dans ce repo. kubectl passe par la VM Lima du cluster (KUBECTL pour changer).
#
#   demo/demo.sh runner   acte 1 : ArgoCD éteint, workflow deploy-dev actif
#   demo/demo.sh argo     acte 2 : ArgoCD allumé, workflow deploy-dev désactivé
#   demo/demo.sh drift    modifie search à la main dans dev, puis montre qui le corrige
#   demo/demo.sh bump     change les replicas de stats dans k8s/dev, commit et push sur main
#   demo/demo.sh status   état d'ArgoCD, du workflow et de dev
#   demo/demo.sh normal   fin de démo : ArgoCD allumé ET workflow actif (état habituel)
set -euo pipefail

REPO=Bilnaa/pwytch-cd
VM=${VM:-gh-runner}
read -r -a KUBECTL <<<"${KUBECTL:-limactl shell $VM kubectl}"
k() { "${KUBECTL[@]}" "$@"; }

argocd_scale() {
  k -n argocd scale deployment --all --replicas="$1" >/dev/null
  k -n argocd scale statefulset --all --replicas="$1" >/dev/null
}

argocd_on() {
  argocd_scale 1
  k -n argocd rollout status statefulset/argocd-application-controller --timeout=180s
  k -n argocd rollout status deployment/argocd-server --timeout=180s
  k -n argocd rollout status deployment/argocd-repo-server --timeout=180s
  # le port-forward de l'UI tombe quand argocd-server s'arrête : systemd le relance, on n'attend pas les 5 s
  limactl shell "$VM" sudo systemctl restart argocd-forward || true
  refresh
}

argocd_off() {
  argocd_scale 0
  k -n argocd wait --for=delete pod --all --timeout=120s >/dev/null 2>&1 || true
}

# Relecture immédiate du repo par ArgoCD, sans attendre son cycle de 3 minutes
refresh() {
  for app in pwytch-dev pwytch-prod; do
    k -n argocd annotate application "$app" argocd.argoproj.io/refresh=hard --overwrite >/dev/null
  done
}

replicas() { k -n dev get deployment "$1" -o jsonpath='{.spec.replicas}'; }

case "${1:-}" in
  runner)
    argocd_off
    gh workflow enable deploy-dev.yml -R "$REPO"
    echo "Acte 1 : ArgoCD éteint, le runner déploie (deploy-dev sur push, deploy-prod à la main)."
    ;;
  argo)
    gh workflow disable deploy-dev.yml -R "$REPO"
    argocd_on
    echo "Acte 2 : ArgoCD allumé (http://127.0.0.1:8081), deploy-dev désactivé : seul ArgoCD déploie."
    ;;
  drift)
    k -n dev scale deployment/search --replicas=3 >/dev/null
    echo "search passé à 3 replicas à la main (Git dit 1). Suivi pendant 60 s :"
    for _ in $(seq 12); do
      sleep 5
      n=$(replicas search)
      echo "  $(date +%T)  search : $n replicas"
      [ "$n" = 1 ] && { echo "Corrigé : ArgoCD (selfHeal) a remis l'état de Git."; exit 0; }
    done
    echo "Personne n'a corrigé : sans ArgoCD, la dérive reste jusqu'au prochain déploiement."
    echo "Remise à 1 : demo/demo.sh bump (le runner réapplique k8s/dev) ou kubectl -n dev scale deployment/search --replicas=1"
    ;;
  bump)
    f=k8s/dev/26-stats.yaml
    git pull -q --rebase
    cur=$(grep -m1 -E '^  replicas: [0-9]+' "$f" | awk '{print $2}')
    new=$((cur == 1 ? 2 : 1))
    perl -0pi -e "s/^  replicas: \d+/  replicas: $new/m" "$f"
    git commit -qm "demo: stats $cur -> $new replicas en dev" "$f"
    git push -q
    echo "Pushé : stats $cur -> $new replicas dans k8s/dev."
    if k -n argocd get statefulset argocd-application-controller -o jsonpath='{.spec.replicas}' | grep -qx 1; then
      refresh
      echo "ArgoCD relit le repo et synchronise (UI : pwytch-dev)."
    else
      echo "Le runner déploie : onglet Actions > deploy-dev (gh run watch -R $REPO)."
    fi
    echo "Suivi : $(printf '%q ' "${KUBECTL[@]}")-n dev get deployment stats -w"
    ;;
  status)
    echo "ArgoCD : $(k -n argocd get pods --no-headers 2>/dev/null | wc -l | tr -d ' ') pods"
    k -n argocd get applications 2>/dev/null || true
    gh workflow list -R "$REPO" --all
    k -n dev get deployments
    ;;
  normal)
    gh workflow enable deploy-dev.yml -R "$REPO"
    argocd_on
    echo "État habituel : ArgoCD allumé et workflow deploy-dev actif."
    ;;
  *)
    sed -n '2,11p' "$0" | sed 's/^# \{0,1\}//'
    exit 1
    ;;
esac
