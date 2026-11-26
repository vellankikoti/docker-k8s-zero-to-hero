{{- define "chai.fullname" -}}{{ .Release.Name }}{{- end -}}
{{- define "chai.selectorLabels" -}}
app.kubernetes.io/name: chai-stall
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}
{{- define "chai.labels" -}}
{{ include "chai.selectorLabels" . }}
app.kubernetes.io/version: {{ .Values.image.tag | default .Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
helm.sh/chart: {{ .Chart.Name }}-{{ .Chart.Version }}
{{- if .Values.slot }}
slot: {{ .Values.slot }}
{{- end }}
{{- end -}}
