{{/*
Expand the name of the chart.
*/}}
{{- define "vpn-operator.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
*/}}
{{- define "vpn-operator.fullname" -}}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- $name := default .Chart.Name .Values.nameOverride }}
{{- if contains $name .Release.Name }}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}
{{- end }}

{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "vpn-operator.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "vpn-operator.labels" -}}
helm.sh/chart: {{ include "vpn-operator.chart" . }}
{{ include "vpn-operator.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "vpn-operator.selectorLabels" -}}
app.kubernetes.io/name: {{ include "vpn-operator.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Create the name of the service account to use
*/}}
{{- define "vpn-operator.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "vpn-operator.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{/*
Get the namespace to watch
*/}}
{{- define "vpn-operator.watchNamespace" -}}
{{- .Values.operator.watchNamespace | default "" }}
{{- end }}

{{/*
Get webhook certificate secret name
*/}}
{{- define "vpn-operator.webhookCertSecret" -}}
{{- printf "%s-webhook-certs" (include "vpn-operator.fullname" .) }}
{{- end }}