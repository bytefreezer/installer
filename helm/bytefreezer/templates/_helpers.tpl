{{/*
Expand the name of the chart.
*/}}
{{- define "bytefreezer.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
*/}}
{{- define "bytefreezer.fullname" -}}
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
{{- define "bytefreezer.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "bytefreezer.labels" -}}
helm.sh/chart: {{ include "bytefreezer.chart" . }}
{{ include "bytefreezer.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "bytefreezer.selectorLabels" -}}
app.kubernetes.io/name: {{ include "bytefreezer.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Create the name of the service account to use
*/}}
{{- define "bytefreezer.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "bytefreezer.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{/*
Get the S3 secret name
*/}}
{{- define "bytefreezer.s3SecretName" -}}
{{- if .Values.s3.existingSecret }}
{{- .Values.s3.existingSecret }}
{{- else }}
{{- include "bytefreezer.fullname" . }}-s3
{{- end }}
{{- end }}

{{/*
Get the control service secret name
*/}}
{{- define "bytefreezer.controlSecretName" -}}
{{- if .Values.controlService.existingSecret }}
{{- .Values.controlService.existingSecret }}
{{- else }}
{{- include "bytefreezer.fullname" . }}-control
{{- end }}
{{- end }}

{{/*
Get the image registry prefix
*/}}
{{- define "bytefreezer.imageRegistry" -}}
{{- if .Values.global.imageRegistry }}
{{- printf "%s/" .Values.global.imageRegistry }}
{{- else }}
{{- "" }}
{{- end }}
{{- end }}

{{/*
Get the S3 endpoint - use internal MinIO if enabled
*/}}
{{- define "bytefreezer.s3Endpoint" -}}
{{- if .Values.minio.enabled }}
{{- printf "%s-minio:%d" (include "bytefreezer.fullname" .) (.Values.minio.service.port | int) }}
{{- else }}
{{- .Values.s3.endpoint }}
{{- end }}
{{- end }}

{{/*
Get the S3 access key - use MinIO root user if MinIO is enabled and s3.accessKey is empty
*/}}
{{- define "bytefreezer.s3AccessKey" -}}
{{- if and .Values.minio.enabled (not .Values.s3.accessKey) }}
{{- .Values.minio.rootUser }}
{{- else }}
{{- .Values.s3.accessKey }}
{{- end }}
{{- end }}

{{/*
Get the S3 secret key - use MinIO root password if MinIO is enabled and s3.secretKey is empty
*/}}
{{- define "bytefreezer.s3SecretKey" -}}
{{- if and .Values.minio.enabled (not .Values.s3.secretKey) }}
{{- .Values.minio.rootPassword }}
{{- else }}
{{- .Values.s3.secretKey }}
{{- end }}
{{- end }}

{{/*
Get the metrics endpoint based on configuration
*/}}
{{- define "bytefreezer.metricsEndpoint" -}}
{{- if .Values.monitoring.externalEndpoint }}
{{- .Values.monitoring.externalEndpoint }}
{{- else if .Values.monitoring.victoriametrics.enabled }}
{{- printf "%s-victoriametrics:8428" (include "bytefreezer.fullname" .) }}
{{- else }}
{{- "" }}
{{- end }}
{{- end }}

{{/*
Get the metrics mode based on configuration
*/}}
{{- define "bytefreezer.metricsMode" -}}
{{- if or .Values.monitoring.externalEndpoint .Values.monitoring.victoriametrics.enabled }}
{{- "otlp_http" }}
{{- else }}
{{- .Values.monitoring.mode | default "prometheus" }}
{{- end }}
{{- end }}

{{/*
Component-specific fullname helpers
*/}}
{{- define "bytefreezer.receiver.fullname" -}}
{{- printf "%s-receiver" (include "bytefreezer.fullname" .) | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "bytefreezer.packer.fullname" -}}
{{- printf "%s-packer" (include "bytefreezer.fullname" .) | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "bytefreezer.piper.fullname" -}}
{{- printf "%s-piper" (include "bytefreezer.fullname" .) | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Component-specific labels
*/}}
{{- define "bytefreezer.receiver.labels" -}}
{{ include "bytefreezer.labels" . }}
app.kubernetes.io/component: receiver
{{- end }}

{{- define "bytefreezer.receiver.selectorLabels" -}}
{{ include "bytefreezer.selectorLabels" . }}
app.kubernetes.io/component: receiver
{{- end }}

{{- define "bytefreezer.packer.labels" -}}
{{ include "bytefreezer.labels" . }}
app.kubernetes.io/component: packer
{{- end }}

{{- define "bytefreezer.packer.selectorLabels" -}}
{{ include "bytefreezer.selectorLabels" . }}
app.kubernetes.io/component: packer
{{- end }}

{{- define "bytefreezer.piper.labels" -}}
{{ include "bytefreezer.labels" . }}
app.kubernetes.io/component: piper
{{- end }}

{{- define "bytefreezer.piper.selectorLabels" -}}
{{ include "bytefreezer.selectorLabels" . }}
app.kubernetes.io/component: piper
{{- end }}
