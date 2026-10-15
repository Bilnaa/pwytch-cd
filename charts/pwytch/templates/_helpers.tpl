{{/* Nom du chart, sert à app.kubernetes.io/name */}}
{{- define "pwytch.name" -}}
{{- .Chart.Name | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/* Nom et version du chart, pour le label helm.sh/chart */}}
{{- define "pwytch.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Namespace de déploiement : toujours celui de la release (helm install -n <namespace>),
pour que le Secret de la release Helm soit dans le même namespace que les ressources.
*/}}
{{- define "pwytch.namespace" -}}
{{- .Release.Namespace }}
{{- end }}

{{/* Environnement : values.environment, sinon le namespace de la release. Doit valoir dev ou prod. */}}
{{- define "pwytch.environment" -}}
{{- $env := default .Release.Namespace .Values.environment }}
{{- if not (has $env (list "dev" "prod")) }}
{{- fail (printf "environment doit valoir dev ou prod (reçu %q) : utiliser -n dev / -n prod ou --set environment=" $env) }}
{{- end }}
{{- $env }}
{{- end }}

{{/* Tag des images, obligatoire : le sha complet (40 caractères) d'un commit du repo CI */}}
{{- define "pwytch.imageTag" -}}
{{- $tag := required "image.tag est obligatoire (sha d'un commit du repo CI)" .Values.image.tag }}
{{- if not (regexMatch "^[0-9a-f]{40}$" $tag) }}
{{- fail (printf "image.tag doit être un sha complet de 40 caractères (reçu %q)" $tag) }}
{{- end }}
{{- $tag }}
{{- end }}

{{/*
Labels communs, à mettre sur toutes les ressources (metadata et template des pods).
Fixes d'un déploiement à l'autre : pas de version, sinon chaque nouveau sha redémarre aussi postgres, redis et mosquitto.
commonLabels s'ajoute sans pouvoir remplacer un label du chart, ni le label app des selectors.
Usage : {{- include "pwytch.labels" . | nindent 4 }}
*/}}
{{- define "pwytch.labels" -}}
{{- $labels := dict
  "helm.sh/chart" (include "pwytch.chart" .)
  "app.kubernetes.io/name" (include "pwytch.name" .)
  "app.kubernetes.io/instance" .Release.Name
  "app.kubernetes.io/part-of" "pwytch"
  "app.kubernetes.io/managed-by" .Release.Service
  "environment" (include "pwytch.environment" .)
}}
{{- toYaml (merge $labels (omit (.Values.commonLabels | default dict) "app" "app.kubernetes.io/version")) }}
{{- end }}

{{/*
Label de version, seulement sur les 7 services (main, stream, live-chat, replay, search, bookmarks, stats).
Usage : {{- include "pwytch.versionLabel" . | nindent 4 }}
*/}}
{{- define "pwytch.versionLabel" -}}
app.kubernetes.io/version: {{ include "pwytch.imageTag" . | quote }}
{{- end }}

{{/*
Label de sélection d'un composant (selector des Deployments, StatefulSets et Services).
Même label app que les manifests de k8s/ : un selector ne peut pas changer, le chart doit pouvoir reprendre les objets existants.
Sur le template des pods : pwytch.labels + pwytch.selectorLabels (pas de clé en commun).
Usage : {{- include "pwytch.selectorLabels" (dict "component" "main") | nindent 6 }}
*/}}
{{- define "pwytch.selectorLabels" -}}
app: {{ required "selectorLabels : component est obligatoire" .component | quote }}
{{- end }}

{{/*
Image d'un des 7 services : <registry>/<repositoryPrefix><nom>:<tag>.
services.<nom>.image.repository et services.<nom>.image.tag remplacent ceux du chart pour ce service.
Le tag est toujours un sha complet de 40 caractères, jamais latest.
Usage : {{ include "pwytch.serviceImage" (dict "root" $ "name" $name "service" $service) }}
*/}}
{{- define "pwytch.serviceImage" -}}
{{- $image := .service.image | default dict }}
{{- $repository := $image.repository | default (printf "%s/%s%s" .root.Values.image.registry .root.Values.image.repositoryPrefix .name) }}
{{- $tag := $image.tag | default (include "pwytch.imageTag" .root) }}
{{- if not (regexMatch "^[0-9a-f]{40}$" $tag) }}
{{- fail (printf "services.%s.image.tag doit être un sha complet de 40 caractères (reçu %q)" .name $tag) }}
{{- end }}
{{- printf "%s:%s" $repository $tag }}
{{- end }}

{{/*
Tag effectif d'un service, pour son label de version.
Usage : {{ include "pwytch.serviceImageTag" (dict "root" $ "service" $service) }}
*/}}
{{- define "pwytch.serviceImageTag" -}}
{{- ((.service.image | default dict).tag) | default (include "pwytch.imageTag" .root) }}
{{- end }}
