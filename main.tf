locals {
  project_name     = coalesce(try(var.context["project"]["name"], null), "default")
  project_id       = coalesce(try(var.context["project"]["id"], null), "default_id")
  environment_name = coalesce(try(var.context["environment"]["name"], null), "test")
  environment_id   = coalesce(try(var.context["environment"]["id"], null), "test_id")
  resource_name    = coalesce(try(var.context["resource"]["name"], null), "example")
  resource_id      = coalesce(try(var.context["resource"]["id"], null), "example_id")

  task_periodic = try(var.deployment.execute_strategy.type == "periodic" && var.deployment.execute_strategy.periodic != null, false)
  namespace     = coalesce(try(var.infrastructure.namespace, ""), join("-", [local.project_name, local.environment_name]))
  gpu_vendor    = coalesce(try(var.infrastructure.gpu_vendor, ""), "nvdia.com")
  annotations = {
    "walrus.seal.io/project-id"     = local.project_id
    "walrus.seal.io/environment-id" = local.environment_id
    "walrus.seal.io/resource-id"    = local.resource_id
  }
  labels = {
    "walrus.seal.io/project-name"     = local.project_name
    "walrus.seal.io/environment-name" = local.environment_name
    "walrus.seal.io/resource-name"    = local.resource_name
  }
}

#
# Credentials
#

locals {
  credentials_map = {
    for c in try(flatten(var.credentials), []) : c.name => c
    if lookup(c, c.type, null) != null
  }
  credentials = values(local.credentials_map)
}

## provide image registry credentials.

locals {
  image_registry_credentials = {
    for v in local.credentials : v.image_registry.server => {
      username = v.image_registry.username
      password = v.image_registry.password
      email    = v.image_registry.email
      auth     = base64encode("${v.image_registry.username}:${v.image_registry.password}")
    }
    if v.type == "image_registry"
  }
}

resource "kubernetes_secret_v1" "image_registry_credentials" {
  count = try(length(local.image_registry_credentials), 0) > 0 ? 1 : 0

  wait_for_service_account_token = false

  metadata {
    namespace   = local.namespace
    name        = join("-", [local.resource_name, "cred-img-regs"])
    annotations = local.annotations
    labels      = local.labels
  }

  type = "kubernetes.io/dockerconfigjson"
  data = {
    ".dockerconfigjson" = jsonencode(local.image_registry_credentials)
  }
}

#
# Configs
#

locals {
  configs_map = {
    for c in try(flatten(var.configs), []) : c.name => c
    if lookup(c, c.type, null) != null
  }
  configs = values(local.configs_map)
}

## provide secret configs.

resource "kubernetes_secret_v1" "configs" {
  for_each = {
    for v in local.configs : v.name => v.secret
    if v.type == "secret"
  }

  wait_for_service_account_token = false

  metadata {
    namespace   = local.namespace
    name        = join("-", [local.resource_name, "cfg", each.key])
    annotations = local.annotations
    labels      = local.labels
  }

  data = each.value
}

## provide data configs.

resource "kubernetes_config_map_v1" "configs" {
  for_each = {
    for v in local.configs : v.name => v.data
    if v.type == "data"
  }

  metadata {
    namespace   = local.namespace
    name        = join("-", [local.resource_name, "cfg", each.key])
    annotations = local.annotations
    labels      = local.labels
  }

  data = each.value
}

#
# Deployment
#

locals {
  downward_annotations = {
    WALRUS_PROJECT_ID     = "walrus.seal.io/project-id"
    WALRUS_ENVIRONMENT_ID = "walrus.seal.io/environment-id"
    WALRUS_RESOURCE_ID    = "walrus.seal.io/resource-id"
  }
  downward_labels = {
    WALRUS_PROJECT_NAME     = "walrus.seal.io/project-name"
    WALRUS_ENVIRONMENT_NAME = "walrus.seal.io/environment-name"
    WALRUS_RESOURCE_NAME    = "walrus.seal.io/resource-name"
    JOB_NAME                = "batch.kubernetes.io/job-name"
  }

  storages_map = {
    for c in try(flatten(var.storages), []) : c.name => c
    if lookup(c, c.type, null) != null
  }
  storages = values(local.storages_map)

  containers_map = {
    for c in try(flatten(var.containers), []) : c.name => c
  }
  containers = values(local.containers_map)

  completions = try(var.deployment.completions > 0, false) ? var.deployment.completions : null
}

resource "kubernetes_job_v1" "once" {
  count = !local.task_periodic ? 1 : 0

  wait_for_completion = false

  metadata {
    namespace     = local.namespace
    generate_name = format("%s-", local.resource_name)
    annotations   = local.annotations
    labels        = local.labels
  }

  spec {
    active_deadline_seconds    = var.deployment.timeout
    completions                = local.completions
    parallelism                = try(var.deployment.parallelism != null && var.deployment.parallelism > 0, false) ? var.deployment.parallelism : null
    backoff_limit              = var.deployment.retries
    ttl_seconds_after_finished = try(var.deployment.cleanup != null && var.deployment.cleanup, false) ? 300 : null
    completion_mode            = local.completions == null ? "NonIndexed" : "Indexed"

    template {
      metadata {
        annotations = local.annotations
        labels      = local.labels
      }

      spec {
        automount_service_account_token = false
        subdomain                       = local.completions != null ? kubernetes_service_v1.tasks[0].metadata[0].name : null
        restart_policy                  = try(var.deployment.retries == 0) ? "Never" : "OnFailure"

        dynamic "security_context" {
          for_each = try(length(var.deployment.system_controls), 0) > 0 ? [{}] : []
          content {
            dynamic "sysctl" {
              for_each = var.deployment.system_controls
              content {
                name  = sysctl.value.name
                value = sysctl.value.value
              }
            }
          }
        }

        ## mount image registry credentials.

        dynamic "image_pull_secrets" {
          for_each = try(length(kubernetes_secret_v1.image_registry_credentials), 0) > 0 ? [{}] : []
          content {
            name = kubernetes_secret_v1.image_registry_credentials[0].metadata[0].name
          }
        }

        ## declare empty stroages.

        dynamic "volume" {
          for_each = {
            for v in local.storages : v.name => v.empty
            if v.type == "empty"
          }
          content {
            name = format("stg-%s", volume.key)
            empty_dir {
              medium     = volume.value.medium
              size_limit = try(format("%dMi", volume.value.size), null)
            }
          }
        }

        ## declare nas stroages.

        dynamic "volume" {
          for_each = {
            for v in local.storages : v.name => v.nas
            if v.type == "nas"
          }
          content {
            name = format("stg-%s", volume.key)
            nfs {
              server = volume.value.server
              path   = volume.value.path
            }
          }
        }

        ## declare san stroages.

        dynamic "volume" {
          for_each = {
            for v in local.storages : v.name => v.san
            if v.type == "san"
          }
          content {
            name = format("stg-%s", volume.key)

            dynamic "fc" {
              for_each = volume.value.type == "fc" ? [volume.value] : []
              content {
                read_only    = fc.value.read_only
                fs_type      = fc.value.fs_type
                lun          = fc.value.fc.lun
                target_ww_ns = compact(fc.value.fc.wwns)
              }
            }

            dynamic "iscsi" {
              for_each = volume.value.type == "iscsi" ? [volume.value] : []
              content {
                read_only     = iscsi.value.read_only
                fs_type       = iscsi.value.fs_type
                lun           = iscsi.value.iscsi.lun
                target_portal = iscsi.value.iscsi.portal
                iqn           = iscsi.value.iscsi.iqn
              }
            }
          }
        }

        ## declare ephemeral storages.

        dynamic "volume" {
          for_each = {
            for v in local.storages : v.name => v.ephemeral
            if v.type == "ephemeral"
          }
          content {
            name = format("stg-%s", volume.key)
            ephemeral {
              volume_claim_template {
                metadata {
                  annotations = local.annotations
                  labels      = local.labels
                }
                spec {
                  access_modes       = [coalesce(volume.value.access_mode, "ReadWriteOnce")]
                  storage_class_name = volume.value.class
                  resources {
                    requests = {
                      "storage" = format("%dMi", volume.value.size)
                    }
                  }
                }
              }
            }
          }
        }

        ## declare persistent storages.

        dynamic "volume" {
          for_each = {
            for v in local.storages : v.name => v.persistent
            if v.type == "persistent"
          }
          content {
            name = format("stg-%s", volume.key)
            persistent_volume_claim {
              read_only  = volume.value.read_only
              claim_name = volume.value.name
            }
          }
        }

        ## declare configs for init profile containers.

        dynamic "volume" {
          for_each = {
            for c in flatten([
              for x in local.containers : tolist(toset([
                for y in try(flatten(x.mounts), []) : y
                if y.type == "config" && y.config != null
              ]))
              if x.profile != "run"
            ]) : md5(jsonencode(c.config)) => c...
          }
          content {
            name = format("cfg-init-%s", volume.key)
            dynamic "config_map" {
              for_each = local.configs_map[volume.value[0].config.name].type == "data" ? [volume.value[0]] : []
              content {
                default_mode = config_map.value.config.mode
                name         = join("-", [local.resource_name, "cfg", config_map.value.config.name])
                dynamic "items" {
                  for_each = config_map.value.config.key != null ? [{}] : []
                  content {
                    key  = config_map.value.config.key
                    path = basename(config_map.value.path)
                  }
                }
              }
            }
            dynamic "secret" {
              for_each = local.configs_map[volume.value[0].config.name].type == "secret" ? [volume.value[0]] : []
              content {
                default_mode = secret.value.config.mode
                secret_name  = join("-", [local.resource_name, "cfg", secret.value.config.name])
                dynamic "items" {
                  for_each = secret.value.config.key != null ? [{}] : []
                  content {
                    key  = secret.value.config.key
                    path = basename(secret.value.path)
                  }
                }
              }
            }
          }
        }

        ## declare configs for run profile containers.

        dynamic "volume" {
          for_each = {
            for c in flatten([
              for x in local.containers : tolist(toset([
                for y in try(flatten(x.mounts), []) : y
                if y.type == "config" && y.config != null
              ]))
              if x.profile == "run"
            ]) : md5(jsonencode(c.config)) => c...
          }
          content {
            name = format("cfg-run-%s", volume.key)
            dynamic "config_map" {
              for_each = local.configs_map[volume.value[0].config.name].type == "data" ? [volume.value[0]] : []
              content {
                default_mode = config_map.value.config.mode
                name         = join("-", [local.resource_name, "cfg", config_map.value.config.name])
                dynamic "items" {
                  for_each = config_map.value.config.key != null ? [{}] : []
                  content {
                    key  = config_map.value.config.key
                    path = basename(config_map.value.path)
                  }
                }
              }
            }
            dynamic "secret" {
              for_each = local.configs_map[volume.value[0].config.name].type == "secret" ? [volume.value[0]] : []
              content {
                default_mode = secret.value.config.mode
                secret_name  = join("-", [local.resource_name, "cfg", secret.value.config.name])
                dynamic "items" {
                  for_each = secret.value.config.key != null ? [{}] : []
                  content {
                    key  = secret.value.config.key
                    path = basename(secret.value.path)
                  }
                }
              }
            }
          }
        }

        ## setup init containers.

        dynamic "init_container" {
          for_each = {
            for c in local.containers : c.name => c
            if c.profile != "run"
          }
          content {
            name = init_container.key

            image             = init_container.value.image.name
            image_pull_policy = try(init_container.value.image.pull_policy, "Always")

            command     = try(init_container.value.execute.command, null)
            args        = try(init_container.value.execute.args, null)
            working_dir = try(init_container.value.execute.working_dir, null)
            dynamic "security_context" {
              for_each = try(init_container.value.execute.as != null, false) ? [{}] : []
              content {
                run_as_non_root = try(init_container.value.execute.as == "non_root", false)
                run_as_user     = try(tonumber(split(":", init_container.value.execute.as)[0]), null)
                run_as_group    = try(tonumber(split(":", init_container.value.execute.as)[1]), null)
              }
            }

            dynamic "resources" {
              for_each = init_container.value.resources != null ? [init_container.value.resources] : []
              content {
                requests = resources.value.requests != null ? {
                  for k, v in resources.value.requests : "%{if k == "gpu"}${local.gpu_vendor}/%{endif}${k}" => "%{if k == "memory"}${v}Mi%{else}${v}%{endif}"
                  if v != null && v > 0
                } : null
                limits = resources.value.limits != null ? {
                  for k, v in resources.value.limits : "%{if k == "gpu"}${local.gpu_vendor}/%{endif}${k}" => "%{if k == "memory"}${v}Mi%{else}${v}%{endif}"
                  if v != null && v > 0
                } : null
              }
            }

            dynamic "env" {
              for_each = {
                for c in try(flatten(init_container.value.envs), []) : try(coalesce(c.name, ""), "") => c
                if lookup(c, c.type, null) != null && try(coalesce(c.name, ""), "") != ""
              }
              content {
                name  = env.key
                value = env.value.type == "text" ? env.value.text.content : null

                dynamic "value_from" {
                  for_each = env.value.type == "config" && try(env.value.config.key != null, false) ? [{}] : []
                  content {
                    dynamic "config_map_key_ref" {
                      for_each = local.configs_map[env.value.config.name].type == "data" ? [{}] : []
                      content {
                        name = join("-", [local.resource_name, "cfg", env.value.config.name])
                        key  = env.value.config.key
                      }
                    }
                    dynamic "secret_key_ref" {
                      for_each = local.configs_map[env.value.config.name].type == "secret" ? [{}] : []
                      content {
                        name = join("-", [local.resource_name, "cfg", env.value.config.name])
                        key  = env.value.config.key
                      }
                    }
                  }
                }
              }
            }

            dynamic "env_from" {
              for_each = [
                for c in try(flatten(init_container.value.envs), []) : c
                if lookup(c, c.type, null) != null && c.type == "config" && try(coalesce(c.name, ""), "") == "" && try(c.config.key == null || c.config.key == "", false)
              ]
              content {
                dynamic "config_map_ref" {
                  for_each = local.configs_map[env_from.value.config.name].type == "data" ? [{}] : []
                  content {
                    name = join("-", [local.resource_name, "cfg", env_from.value.config.name])
                  }
                }
                dynamic "secret_ref" {
                  for_each = local.configs_map[env_from.value.config.name].type == "secret" ? [{}] : []
                  content {
                    name = join("-", [local.resource_name, "cfg", env_from.value.config.name])
                  }
                }
              }
            }

            dynamic "env" {
              for_each = local.downward_annotations
              content {
                name = env.key
                value_from {
                  field_ref {
                    field_path = format("metadata.annotations['%s']", env.value)
                  }
                }
              }
            }

            dynamic "env" {
              for_each = local.downward_labels
              content {
                name = env.key
                value_from {
                  field_ref {
                    field_path = format("metadata.labels['%s']", env.value)
                  }
                }
              }
            }

            dynamic "volume_mount" {
              for_each = {
                for c in try(flatten(init_container.value.mounts), []) : c.path => c
                if lookup(c, c.type, null) != null
              }
              content {
                mount_path = volume_mount.key
                read_only  = volume_mount.value.read_only
                sub_path   = volume_mount.value.type == "storage" ? volume_mount.value.storage.sub_path : (volume_mount.value.config.key != null && volume_mount.value.config.disable_changed ? basename(volume_mount.key) : null)
                name       = volume_mount.value.type == "storage" ? format("stg-%s", volume_mount.value.storage.name) : format("cfg-init-%s", md5(jsonencode(volume_mount.value.config)))
              }
            }
          }
        }

        ## setup containers.

        dynamic "container" {
          for_each = {
            for c in local.containers : c.name => c
            if c.profile == "run"
          }
          content {
            name = container.key

            image             = container.value.image.name
            image_pull_policy = try(container.value.image.pull_policy, "Always")

            command     = try(container.value.execute.command, null)
            args        = try(container.value.execute.args, null)
            working_dir = try(container.value.execute.working_dir, null)
            dynamic "security_context" {
              for_each = try(container.value.execute.as != null, false) ? [{}] : []
              content {
                run_as_non_root = try(container.value.execute.as == "non_root", false)
                run_as_user     = try(tonumber(split(":", container.value.execute.as)[0]), null)
                run_as_group    = try(tonumber(split(":", container.value.execute.as)[1]), null)
              }
            }

            dynamic "resources" {
              for_each = container.value.resources != null ? [container.value.resources] : []
              content {
                requests = resources.value.requests != null ? {
                  for k, v in resources.value.requests : "%{if k == "gpu"}${local.gpu_vendor}/%{endif}${k}" => "%{if k == "memory"}${v}Mi%{else}${v}%{endif}"
                  if v != null && v > 0
                } : null
                limits = resources.value.limits != null ? {
                  for k, v in resources.value.limits : "%{if k == "gpu"}${local.gpu_vendor}/%{endif}${k}" => "%{if k == "memory"}${v}Mi%{else}${v}%{endif}"
                  if v != null && v > 0
                } : null
              }
            }

            dynamic "env" {
              for_each = {
                for c in try(flatten(container.value.envs), []) : try(coalesce(c.name, ""), "") => c
                if lookup(c, c.type, null) != null && try(coalesce(c.name, ""), "") != ""
              }
              content {
                name  = env.key
                value = env.value.type == "text" ? env.value.text.content : null

                dynamic "value_from" {
                  for_each = env.value.type == "config" && try(env.value.config.key != null, false) ? [{}] : []
                  content {
                    dynamic "config_map_key_ref" {
                      for_each = local.configs_map[env.value.config.name].type == "data" ? [{}] : []
                      content {
                        name = join("-", [local.resource_name, "cfg", env.value.config.name])
                        key  = env.value.config.key
                      }
                    }
                    dynamic "secret_key_ref" {
                      for_each = local.configs_map[env.value.config.name].type == "secret" ? [{}] : []
                      content {
                        name = join("-", [local.resource_name, "cfg", env.value.config.name])
                        key  = env.value.config.key
                      }
                    }
                  }
                }
              }
            }

            dynamic "env_from" {
              for_each = [
                for c in try(flatten(container.value.envs), []) : c
                if lookup(c, c.type, null) != null && c.type == "config" && try(coalesce(c.name, ""), "") == "" && try(c.config.key == null || c.config.key == "", false)
              ]
              content {
                dynamic "config_map_ref" {
                  for_each = local.configs_map[env_from.value.config.name].type == "data" ? [{}] : []
                  content {
                    name = join("-", [local.resource_name, "cfg", env_from.value.config.name])
                  }
                }
                dynamic "secret_ref" {
                  for_each = local.configs_map[env_from.value.config.name].type == "secret" ? [{}] : []
                  content {
                    name = join("-", [local.resource_name, "cfg", env_from.value.config.name])
                  }
                }
              }
            }

            dynamic "env" {
              for_each = local.downward_annotations
              content {
                name = env.key
                value_from {
                  field_ref {
                    field_path = format("metadata.annotations['%s']", env.value)
                  }
                }
              }
            }

            dynamic "env" {
              for_each = local.downward_labels
              content {
                name = env.key
                value_from {
                  field_ref {
                    field_path = format("metadata.labels['%s']", env.value)
                  }
                }
              }
            }

            dynamic "volume_mount" {
              for_each = {
                for c in try(flatten(container.value.mounts), []) : c.path => c
                if lookup(c, c.type, null) != null
              }
              content {
                mount_path = volume_mount.key
                read_only  = volume_mount.value.read_only
                sub_path   = volume_mount.value.type == "storage" ? volume_mount.value.storage.sub_path : (volume_mount.value.config.key != null && volume_mount.value.config.disable_changed ? basename(volume_mount.key) : null)
                name       = volume_mount.value.type == "storage" ? format("stg-%s", volume_mount.value.storage.name) : format("cfg-run-%s", md5(jsonencode(volume_mount.value.config)))
              }
            }
          }
        }
      }
    }
  }
}

resource "kubernetes_cron_job_v1" "periodic" {
  count = local.task_periodic ? 1 : 0

  metadata {
    namespace     = local.namespace
    generate_name = format("%s-", local.resource_name)
    annotations   = local.annotations
    labels        = local.labels
  }

  spec {
    starting_deadline_seconds     = 10
    successful_jobs_history_limit = 5
    failed_jobs_history_limit     = 3
    schedule                      = var.deployment.execute_strategy.periodic.cron_expression
    timezone                      = coalesce(var.deployment.execute_strategy.periodic.timezone, "Etc/UTC")
    suspend                       = try(var.deployment.execute_strategy.periodic.suspend == true, false)
    concurrency_policy            = try(var.deployment.execute_strategy.periodic.keep_not_finished == true, false) ? "Forbid" : "Replace"


    job_template {
      metadata {
        annotations = local.annotations
        labels      = local.labels
      }

      spec {
        active_deadline_seconds    = var.deployment.timeout
        completions                = local.completions
        parallelism                = try(var.deployment.parallelism != null && var.deployment.parallelism > 0, false) ? var.deployment.parallelism : null
        backoff_limit              = var.deployment.retries
        ttl_seconds_after_finished = try(var.deployment.cleanup != null && var.deployment.cleanup, false) ? 300 : null
        completion_mode            = local.completions == null ? "NonIndexed" : "Indexed"

        template {
          metadata {
            annotations = local.annotations
            labels      = local.labels
          }

          spec {
            automount_service_account_token = false
            subdomain                       = local.completions != null ? kubernetes_service_v1.tasks[0].metadata[0].name : null
            restart_policy                  = try(var.deployment.retries == 0) ? "Never" : "OnFailure"

            dynamic "security_context" {
              for_each = try(length(var.deployment.system_controls), 0) > 0 ? [{}] : []
              content {
                dynamic "sysctl" {
                  for_each = var.deployment.system_controls
                  content {
                    name  = sysctl.value.name
                    value = sysctl.value.value
                  }
                }
              }
            }

            ## mount image registry credentials.

            dynamic "image_pull_secrets" {
              for_each = try(length(kubernetes_secret_v1.image_registry_credentials), 0) > 0 ? [{}] : []
              content {
                name = kubernetes_secret_v1.image_registry_credentials[0].metadata[0].name
              }
            }

            ## declare empty stroages.

            dynamic "volume" {
              for_each = {
                for v in local.storages : v.name => v.empty
                if v.type == "empty"
              }
              content {
                name = format("stg-%s", volume.key)
                empty_dir {
                  medium     = volume.value.medium
                  size_limit = try(format("%dMi", volume.value.size), null)
                }
              }
            }

            ## declare nas stroages.

            dynamic "volume" {
              for_each = {
                for v in local.storages : v.name => v.nas
                if v.type == "nas"
              }
              content {
                name = format("stg-%s", volume.key)
                nfs {
                  server = volume.value.server
                  path   = volume.value.path
                }
              }
            }

            ## declare san stroages.

            dynamic "volume" {
              for_each = {
                for v in local.storages : v.name => v.san
                if v.type == "san"
              }
              content {
                name = format("stg-%s", volume.key)

                dynamic "fc" {
                  for_each = volume.value.type == "fc" ? [volume.value] : []
                  content {
                    read_only    = fc.value.read_only
                    fs_type      = fc.value.fs_type
                    lun          = fc.value.fc.lun
                    target_ww_ns = compact(fc.value.fc.wwns)
                  }
                }

                dynamic "iscsi" {
                  for_each = volume.value.type == "iscsi" ? [volume.value] : []
                  content {
                    read_only     = iscsi.value.read_only
                    fs_type       = iscsi.value.fs_type
                    lun           = iscsi.value.iscsi.lun
                    target_portal = iscsi.value.iscsi.portal
                    iqn           = iscsi.value.iscsi.iqn
                  }
                }
              }
            }

            ## declare ephemeral storages.

            dynamic "volume" {
              for_each = {
                for v in local.storages : v.name => v.ephemeral
                if v.type == "ephemeral"
              }
              content {
                name = format("stg-%s", volume.key)
                ephemeral {
                  volume_claim_template {
                    metadata {
                      annotations = local.annotations
                      labels      = local.labels
                    }
                    spec {
                      access_modes       = [coalesce(volume.value.access_mode, "ReadWriteOnce")]
                      storage_class_name = volume.value.class
                      resources {
                        requests = {
                          "storage" = format("%dMi", volume.value.size)
                        }
                      }
                    }
                  }
                }
              }
            }

            ## declare persistent storages.

            dynamic "volume" {
              for_each = {
                for v in local.storages : v.name => v.persistent
                if v.type == "persistent"
              }
              content {
                name = format("stg-%s", volume.key)
                persistent_volume_claim {
                  read_only  = volume.value.read_only
                  claim_name = volume.value.name
                }
              }
            }

            ## declare configs for init profile containers.

            dynamic "volume" {
              for_each = {
                for c in flatten([
                  for x in local.containers : tolist(toset([
                    for y in try(flatten(x.mounts), []) : y
                    if y.type == "config" && y.config != null
                  ]))
                  if x.profile != "run"
                ]) : md5(jsonencode(c.config)) => c...
              }
              content {
                name = format("cfg-init-%s", volume.key)
                dynamic "config_map" {
                  for_each = local.configs_map[volume.value[0].config.name].type == "data" ? [volume.value[0]] : []
                  content {
                    default_mode = config_map.value.config.mode
                    name         = join("-", [local.resource_name, "cfg", config_map.value.config.name])
                    dynamic "items" {
                      for_each = config_map.value.config.key != null ? [{}] : []
                      content {
                        key  = config_map.value.config.key
                        path = basename(config_map.value.path)
                      }
                    }
                  }
                }
                dynamic "secret" {
                  for_each = local.configs_map[volume.value[0].config.name].type == "secret" ? [volume.value[0]] : []
                  content {
                    default_mode = secret.value.config.mode
                    secret_name  = join("-", [local.resource_name, "cfg", secret.value.config.name])
                    dynamic "items" {
                      for_each = secret.value.config.key != null ? [{}] : []
                      content {
                        key  = secret.value.config.key
                        path = basename(secret.value.path)
                      }
                    }
                  }
                }
              }
            }

            ## declare configs for run profile containers.

            dynamic "volume" {
              for_each = {
                for c in flatten([
                  for x in local.containers : tolist(toset([
                    for y in try(flatten(x.mounts), []) : y
                    if y.type == "config" && y.config != null
                  ]))
                  if x.profile == "run"
                ]) : md5(jsonencode(c.config)) => c...
              }
              content {
                name = format("cfg-run-%s", volume.key)
                dynamic "config_map" {
                  for_each = local.configs_map[volume.value[0].config.name].type == "data" ? [volume.value[0]] : []
                  content {
                    default_mode = config_map.value.config.mode
                    name         = join("-", [local.resource_name, "cfg", config_map.value.config.name])
                    dynamic "items" {
                      for_each = config_map.value.config.key != null ? [{}] : []
                      content {
                        key  = config_map.value.config.key
                        path = basename(config_map.value.path)
                      }
                    }
                  }
                }
                dynamic "secret" {
                  for_each = local.configs_map[volume.value[0].config.name].type == "secret" ? [volume.value[0]] : []
                  content {
                    default_mode = secret.value.config.mode
                    secret_name  = join("-", [local.resource_name, "cfg", secret.value.config.name])
                    dynamic "items" {
                      for_each = secret.value.config.key != null ? [{}] : []
                      content {
                        key  = secret.value.config.key
                        path = basename(secret.value.path)
                      }
                    }
                  }
                }
              }
            }

            ## setup init containers.

            dynamic "init_container" {
              for_each = {
                for c in local.containers : c.name => c
                if c.profile != "run"
              }
              content {
                name = init_container.key

                image             = init_container.value.image.name
                image_pull_policy = try(init_container.value.image.pull_policy, "Always")

                command     = try(init_container.value.execute.command, null)
                args        = try(init_container.value.execute.args, null)
                working_dir = try(init_container.value.execute.working_dir, null)
                dynamic "security_context" {
                  for_each = try(init_container.value.execute.as != null, false) ? [{}] : []
                  content {
                    run_as_non_root = try(init_container.value.execute.as == "non_root", false)
                    run_as_user     = try(tonumber(split(":", init_container.value.execute.as)[0]), null)
                    run_as_group    = try(tonumber(split(":", init_container.value.execute.as)[1]), null)
                  }
                }

                dynamic "resources" {
                  for_each = init_container.value.resources != null ? [init_container.value.resources] : []
                  content {
                    requests = resources.value.requests != null ? {
                      for k, v in resources.value.requests : "%{if k == "gpu"}${local.gpu_vendor}/%{endif}${k}" => "%{if k == "memory"}${v}Mi%{else}${v}%{endif}"
                      if v != null && v > 0
                    } : null
                    limits = resources.value.limits != null ? {
                      for k, v in resources.value.limits : "%{if k == "gpu"}${local.gpu_vendor}/%{endif}${k}" => "%{if k == "memory"}${v}Mi%{else}${v}%{endif}"
                      if v != null && v > 0
                    } : null
                  }
                }

                dynamic "env" {
                  for_each = {
                    for c in try(flatten(init_container.value.envs), []) : try(coalesce(c.name, ""), "") => c
                    if lookup(c, c.type, null) != null && try(coalesce(c.name, ""), "") != ""
                  }
                  content {
                    name  = env.key
                    value = env.value.type == "text" ? env.value.text.content : null

                    dynamic "value_from" {
                      for_each = env.value.type == "config" && try(env.value.config.key != null, false) ? [{}] : []
                      content {
                        dynamic "config_map_key_ref" {
                          for_each = local.configs_map[env.value.config.name].type == "data" ? [{}] : []
                          content {
                            name = join("-", [local.resource_name, "cfg", env.value.config.name])
                            key  = env.value.config.key
                          }
                        }
                        dynamic "secret_key_ref" {
                          for_each = local.configs_map[env.value.config.name].type == "secret" ? [{}] : []
                          content {
                            name = join("-", [local.resource_name, "cfg", env.value.config.name])
                            key  = env.value.config.key
                          }
                        }
                      }
                    }
                  }
                }

                dynamic "env_from" {
                  for_each = [
                    for c in try(flatten(init_container.value.envs), []) : c
                    if lookup(c, c.type, null) != null && c.type == "config" && try(coalesce(c.name, ""), "") == "" && try(c.config.key == null || c.config.key == "", false)
                  ]
                  content {
                    dynamic "config_map_ref" {
                      for_each = local.configs_map[env_from.value.config.name].type == "data" ? [{}] : []
                      content {
                        name = join("-", [local.resource_name, "cfg", env_from.value.config.name])
                      }
                    }
                    dynamic "secret_ref" {
                      for_each = local.configs_map[env_from.value.config.name].type == "secret" ? [{}] : []
                      content {
                        name = join("-", [local.resource_name, "cfg", env_from.value.config.name])
                      }
                    }
                  }
                }

                dynamic "env" {
                  for_each = local.downward_annotations
                  content {
                    name = env.key
                    value_from {
                      field_ref {
                        field_path = format("metadata.annotations['%s']", env.value)
                      }
                    }
                  }
                }

                dynamic "env" {
                  for_each = local.downward_labels
                  content {
                    name = env.key
                    value_from {
                      field_ref {
                        field_path = format("metadata.labels['%s']", env.value)
                      }
                    }
                  }
                }

                dynamic "volume_mount" {
                  for_each = {
                    for c in try(flatten(init_container.value.mounts), []) : c.path => c
                    if lookup(c, c.type, null) != null
                  }
                  content {
                    mount_path = volume_mount.key
                    read_only  = volume_mount.value.read_only
                    sub_path   = volume_mount.value.type == "storage" ? volume_mount.value.storage.sub_path : (volume_mount.value.config.key != null && volume_mount.value.config.disable_changed ? basename(volume_mount.key) : null)
                    name       = volume_mount.value.type == "storage" ? format("stg-%s", volume_mount.value.storage.name) : format("cfg-init-%s", md5(jsonencode(volume_mount.value.config)))
                  }
                }
              }
            }

            ## setup containers.

            dynamic "container" {
              for_each = {
                for c in local.containers : c.name => c
                if c.profile == "run"
              }
              content {
                name = container.key

                image             = container.value.image.name
                image_pull_policy = try(container.value.image.pull_policy, "Always")

                command     = try(container.value.execute.command, null)
                args        = try(container.value.execute.args, null)
                working_dir = try(container.value.execute.working_dir, null)
                dynamic "security_context" {
                  for_each = try(container.value.execute.as != null, false) ? [{}] : []
                  content {
                    run_as_non_root = try(container.value.execute.as == "non_root", false)
                    run_as_user     = try(tonumber(split(":", container.value.execute.as)[0]), null)
                    run_as_group    = try(tonumber(split(":", container.value.execute.as)[1]), null)
                  }
                }

                dynamic "resources" {
                  for_each = container.value.resources != null ? [container.value.resources] : []
                  content {
                    requests = resources.value.requests != null ? {
                      for k, v in resources.value.requests : "%{if k == "gpu"}${local.gpu_vendor}/%{endif}${k}" => "%{if k == "memory"}${v}Mi%{else}${v}%{endif}"
                      if v != null && v > 0
                    } : null
                    limits = resources.value.limits != null ? {
                      for k, v in resources.value.limits : "%{if k == "gpu"}${local.gpu_vendor}/%{endif}${k}" => "%{if k == "memory"}${v}Mi%{else}${v}%{endif}"
                      if v != null && v > 0
                    } : null
                  }
                }

                dynamic "env" {
                  for_each = {
                    for c in try(flatten(container.value.envs), []) : try(coalesce(c.name, ""), "") => c
                    if lookup(c, c.type, null) != null && try(coalesce(c.name, ""), "") != ""
                  }
                  content {
                    name  = env.key
                    value = env.value.type == "text" ? env.value.text.content : null

                    dynamic "value_from" {
                      for_each = env.value.type == "config" && try(env.value.config.key != null, false) ? [{}] : []
                      content {
                        dynamic "config_map_key_ref" {
                          for_each = local.configs_map[env.value.config.name].type == "data" ? [{}] : []
                          content {
                            name = join("-", [local.resource_name, "cfg", env.value.config.name])
                            key  = env.value.config.key
                          }
                        }
                        dynamic "secret_key_ref" {
                          for_each = local.configs_map[env.value.config.name].type == "secret" ? [{}] : []
                          content {
                            name = join("-", [local.resource_name, "cfg", env.value.config.name])
                            key  = env.value.config.key
                          }
                        }
                      }
                    }
                  }
                }

                dynamic "env_from" {
                  for_each = [
                    for c in try(flatten(container.value.envs), []) : c
                    if lookup(c, c.type, null) != null && c.type == "config" && try(coalesce(c.name, ""), "") == "" && try(c.config.key == null || c.config.key == "", false)
                  ]
                  content {
                    dynamic "config_map_ref" {
                      for_each = local.configs_map[env_from.value.config.name].type == "data" ? [{}] : []
                      content {
                        name = join("-", [local.resource_name, "cfg", env_from.value.config.name])
                      }
                    }
                    dynamic "secret_ref" {
                      for_each = local.configs_map[env_from.value.config.name].type == "secret" ? [{}] : []
                      content {
                        name = join("-", [local.resource_name, "cfg", env_from.value.config.name])
                      }
                    }
                  }
                }

                dynamic "env" {
                  for_each = local.downward_annotations
                  content {
                    name = env.key
                    value_from {
                      field_ref {
                        field_path = format("metadata.annotations['%s']", env.value)
                      }
                    }
                  }
                }

                dynamic "env" {
                  for_each = local.downward_labels
                  content {
                    name = env.key
                    value_from {
                      field_ref {
                        field_path = format("metadata.labels['%s']", env.value)
                      }
                    }
                  }
                }

                dynamic "volume_mount" {
                  for_each = {
                    for c in try(flatten(container.value.mounts), []) : c.path => c
                    if lookup(c, c.type, null) != null
                  }
                  content {
                    mount_path = volume_mount.key
                    read_only  = volume_mount.value.read_only
                    sub_path   = volume_mount.value.type == "storage" ? volume_mount.value.storage.sub_path : (volume_mount.value.config.key != null && volume_mount.value.config.disable_changed ? basename(volume_mount.key) : null)
                    name       = volume_mount.value.type == "storage" ? format("stg-%s", volume_mount.value.storage.name) : format("cfg-run-%s", md5(jsonencode(volume_mount.value.config)))
                  }
                }
              }
            }
          }
        }
      }
    }
  }
}

#
# Exposing
#

resource "kubernetes_service_v1" "tasks" {
  count = local.completions != null ? 1 : 0

  wait_for_load_balancer = false

  metadata {
    namespace   = local.namespace
    name        = join("-", [local.resource_name, "tasks"])
    annotations = local.annotations
    labels      = local.labels
  }

  spec {
    selector   = local.labels
    cluster_ip = "None"
  }
}
