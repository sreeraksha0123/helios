{{- define "helios-app.labels" -}}
app.kubernetes.io/part-of: helios-app
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end -}}
