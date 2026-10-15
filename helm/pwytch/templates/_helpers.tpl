{{/* Nom du chart, sert à app.kubernetes.io/name */}}
{{- define "pwytch.name" -}}
{{- .Chart.Name | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/* Nom et version du chart, pour le label helm.sh/chart */}}
{{- define "pwytch.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/* Namespace de déploiement : values.namespace, sinon celui de la release */}}
{{- define "pwytch.namespace" -}}
{{- default .Release.Namespace .Values.namespace }}
{{- end }}

{{/* Tag des images : values.image.tag, sinon appVersion */}}
{{- define "pwytch.imageTag" -}}
{{- default .Chart.AppVersion .Values.image.tag }}
{{- end }}

{{/*
Labels communs, à mettre sur toutes les ressources.
Usage : {{- include "pwytch.labels" . | nindent 4 }}
*/}}
{{- define "pwytch.labels" -}}
helm.sh/chart: {{ include "pwytch.chart" . }}
app.kubernetes.io/name: {{ include "pwytch.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/version: {{ include "pwytch.imageTag" . | trunc 63 | quote }}
app.kubernetes.io/part-of: pwytch
app.kubernetes.io/managed-by: {{ .Release.Service }}
environment: {{ .Values.environment }}
{{- with .Values.commonLabels }}
{{ toYaml . }}
{{- end }}
{{- end }}

{{/*
Labels de sélection d'un composant (selector des Deployments et Services), stables entre deux versions.
Usage : {{- include "pwytch.selectorLabels" (dict "ctx" . "component" "main") | nindent 6 }}
*/}}
{{- define "pwytch.selectorLabels" -}}
app.kubernetes.io/name: {{ include "pwytch.name" .ctx }}
app.kubernetes.io/instance: {{ .ctx.Release.Name }}
app.kubernetes.io/component: {{ .component }}
{{- end }}
