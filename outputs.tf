#
# Orchestration
#

output "context" {
  description = "The input context, a map, which is used for orchestration."
  value       = var.context
}

output "refer" {
  description = "The refer, a map, including hosts, ports and account, which is used for dependencies or collaborations."
  sensitive   = true
  value = {
    schema = local.mode == "once" ? "k8s:job" : "k8s:cronjob"
    params = {
      selector  = local.labels
      namespace = local.namespace
      name      = local.mode == "once" ? kubernetes_job_v1.task[0].metadata[0].name : kubernetes_cron_job_v1.task[0].metadata[0].name
    }
  }
}
