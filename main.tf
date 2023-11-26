locals {
  project_name     = coalesce(try(var.context["project"]["name"], null), "default")
  project_id       = coalesce(try(var.context["project"]["id"], null), "default_id")
  environment_name = coalesce(try(var.context["environment"]["name"], null), "test")
  environment_id   = coalesce(try(var.context["environment"]["id"], null), "test_id")
  resource_name    = coalesce(try(var.context["resource"]["name"], null), "example")
  resource_id      = coalesce(try(var.context["resource"]["id"], null), "example_id")

  namespace = coalesce(try(var.infrastructure.namespace, ""), join("-", [
    local.project_name, local.environment_name
  ]))
  gpu_vendor = coalesce(try(var.infrastructure.gpu_vendor, ""), "nvdia.com")

  annotations = {
    "walrus.seal.io/project-id"     = local.project_id
    "walrus.seal.io/environment-id" = local.environment_id
    "walrus.seal.io/resource-id"    = local.resource_id
  }
  labels = {
    "walrus.seal.io/catalog-name"     = "terraform-kubernetes-containertask"
    "walrus.seal.io/project-name"     = local.project_name
    "walrus.seal.io/environment-name" = local.environment_name
    "walrus.seal.io/resource-name"    = local.resource_name
  }

  mode = var.task.periodic != null ? "periodic" : "once"
}

#
# Parse
#

locals {
  wellknown_env_schemas   = ["k8s:secret"]
  wellknown_file_schemas  = ["k8s:secret", "k8s:configmap"]
  wellknown_mount_schemas = ["k8s:secret", "k8s:configmap", "k8s:persistentvolumeclaim"]

  containers = [
    for i, c in var.containers : merge(c, {
      name = format("%s-%d-%s", coalesce(c.profile, "run"), i, basename(split(":", c.image)[0]))
      envs = [
        for xe in [
          for e in(c.envs != null ? c.envs : []) : e
          if e != null && try(!(e.value != null && e.value_refer != null) && !(e.value == null && e.value_refer == null), false)
        ] : xe
        if xe.value_refer == null || (try(contains(local.wellknown_env_schemas, xe.value_refer.schema), false) && try(lookup(xe.value_refer.params, "name", null) != null, false) && try(lookup(xe.value_refer.params, "key", null) != null, false))
      ]
      files = [
        for xf in [
          for f in(c.files != null ? c.files : []) : f
          if f != null && try(!(f.content != null && f.content_refer != null) && !(f.content == null && f.content_refer == null), false)
        ] : xf
        if xf.content_refer == null || (try(contains(local.wellknown_file_schemas, xf.content_refer.schema), false) && try(lookup(xf.content_refer.params, "name", null) != null, false) && try(lookup(xf.content_refer.params, "key", null) != null, false))
      ]
      mounts = [
        for xm in [
          for m in(c.mounts != null ? c.mounts : []) : m
          if m != null && try(!(m.volume != null && m.volume_refer != null), false)
        ] : xm
        if xm.volume_refer == null || (try(contains(local.wellknown_mount_schemas, xm.volume_refer.schema), false) && try(lookup(xm.volume_refer.params, "name", null) != null, false))
      ]
      checks = [
        for ck in(c.checks != null ? c.checks : []) : ck
        if try(lookup(ck, ck.type, null) != null, false)
      ]
    })
    if c != null
  ]
}

locals {
  container_ephemeral_envs_map = {
    for c in local.containers : c.name => [
      for e in c.envs : e
      if try(e.value_refer == null, false)
    ]
    if c != null
  }
  container_refer_envs_map = {
    for c in local.containers : c.name => [
      for e in c.envs : e
      if try(e.value_refer != null, false)
    ]
    if c != null
  }

  container_ephemeral_files_map = {
    for c in local.containers : c.name => [
      for f in c.files : merge(f, {
        name = format("eph-f-%s-%s", c.name, md5(f.path))
      })
      if try(f.content_refer == null, false)
    ]
    if c != null
  }
  container_refer_files_map = {
    for c in local.containers : c.name => [
      for f in c.files : merge(f, {
        name = format("ref-f-%s-%s", c.name, md5(jsonencode(f.content_refer)))
      })
      if try(f.content_refer != null, false)
    ]
    if c != null
  }

  container_ephemeral_mounts_map = {
    for c in local.containers : c.name => [
      for m in c.mounts : merge(m, {
        name = format("eph-m-%s", try(m.volume == null || m.volume == "", true) ? replace(uuid(), "-", "") : md5(m.volume))
      })
      if try(m.volume_refer == null, false)
    ]
    if c != null
  }
  container_refer_mounts_map = {
    for c in local.containers : c.name => [
      for m in c.mounts : merge(m, {
        name = format("ref-m-%s", md5(jsonencode(m.volume_refer)))
      })
      if m.volume_refer != null
    ]
    if c != null
  }

  init_containers = [
    for c in local.containers : c
    if c != null && try(c.profile != "run", false)
  ]
  run_containers = [
    for c in local.containers : c
    if c != null && try(c.profile == "" || c.profile == "run", true)
  ]
}

#
# Deployment
#

## create kubernetes configmap.

locals {
  ephemeral_files = flatten([
    for _, fs in local.container_ephemeral_files_map : fs
  ])
  refer_files = flatten([
    for _, fs in local.container_refer_files_map : fs
  ])

  ephemeral_mounts = [
    for _, v in {
      for m in flatten([
        for _, ms in local.container_ephemeral_mounts_map : ms
      ]) : m.name => m...
    } : v[0]
  ]
  refer_mounts = [
    for _, v in {
      for m in flatten([
        for _, ms in local.container_refer_mounts_map : ms
      ]) : m.name => m...
    } : v[0]
  ]
}

resource "kubernetes_config_map_v1" "ephemeral_files" {
  for_each = {
    for f in try(nonsensitive(local.ephemeral_files), local.ephemeral_files) : f.name => f
  }

  metadata {
    namespace   = local.namespace
    name        = each.key
    annotations = local.annotations
    labels      = local.labels
  }

  data = {
    content = each.value.content
  }
}

## create kuberentes job / cronjob.

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

  completions = try(var.task.completions > 0, false) ? var.task.completions : null
}

resource "terraform_data" "replacement" {
  count = local.mode == "once" ? 1 : 0

  input = sha256(jsonencode({
    task       = var.task
    containers = var.containers
  }))
}

resource "kubernetes_job_v1" "task" {
  count = local.mode == "once" ? 1 : 0

  wait_for_completion = false

  metadata {
    namespace     = local.namespace
    generate_name = format("%s-", local.resource_name)
    annotations   = local.annotations
    labels        = local.labels
  }

  spec {
    ### scaling.
    active_deadline_seconds    = try(var.task.timeout != null && var.task.timeout > 0, false) ? var.task.timeout : null
    completions                = local.completions
    parallelism                = try(var.task.parallelism != null && var.task.parallelism > 0, false) ? var.task.parallelism : null
    backoff_limit              = var.task.retries
    ttl_seconds_after_finished = try(var.task.cleanup_finished != null && var.task.cleanup_finished, false) ? 300 : null
    completion_mode            = local.completions == null ? "NonIndexed" : "Indexed"

    template {
      metadata {
        annotations = local.annotations
        labels      = local.labels
      }

      spec {
        ### configure basic.
        automount_service_account_token = false
        restart_policy                  = try(var.task.keep_failed_process != null && var.task.keep_failed_process, true) ? "Never" : "OnFailure"
        subdomain                       = local.completions != null ? kubernetes_service_v1.tasks[0].metadata[0].name : null
        dynamic "security_context" {
          for_each = try(length(var.task.sysctls), 0) > 0 || try(var.task.fs_group != null, false) ? [{}] : []
          content {
            dynamic "sysctl" {
              for_each = try(var.task.sysctls != null, false) ? try(
                nonsensitive(var.task.sysctls),
                var.task.sysctls
              ) : []
              content {
                name  = sysctl.value.name
                value = sysctl.value.value
              }
            }
            fs_group = try(var.task.fs_group, null)
          }
        }

        ### declare ephemeral files.
        dynamic "volume" {
          for_each = try(nonsensitive(local.ephemeral_files), local.ephemeral_files)
          content {
            name = volume.value.name
            config_map {
              default_mode = volume.value.mode
              name         = volume.value.name
              items {
                key  = "content"
                path = basename(volume.value.path)
              }
            }
          }
        }

        ### declare refer files.
        dynamic "volume" {
          for_each = try(nonsensitive(local.refer_files), local.refer_files)
          content {
            name = volume.value.name
            dynamic "config_map" {
              for_each = volume.value.content_refer.schema == "k8s:configmap" ? [volume.value] : []
              content {
                default_mode = config_map.value.mode
                name         = config_map.value.content_refer.params.name
                items {
                  key  = config_map.value.content_refer.params.key
                  path = basename(config_map.value.path)
                }
              }
            }
            dynamic "secret" {
              for_each = volume.value.content_refer.schema == "k8s:secret" ? [volume.value] : []
              content {
                default_mode = secret.value.mode
                secret_name  = secret.value.content_refer.params.name
                items {
                  key  = secret.value.content_refer.params.key
                  path = basename(secret.value.path)
                }
              }
            }
          }
        }

        ### declare ephemeral mounts.
        dynamic "volume" {
          for_each = try(nonsensitive(local.ephemeral_mounts), local.ephemeral_mounts)
          content {
            name = volume.value.name
            empty_dir {}
          }
        }

        ### declare refer mounts.
        dynamic "volume" {
          for_each = try(nonsensitive(local.refer_mounts), local.refer_mounts)
          content {
            name = volume.value.name
            dynamic "config_map" {
              for_each = volume.value.volume_refer.schema == "k8s:configmap" ? [volume.value] : []
              content {
                default_mode = try(lookup(config_map.value.volume_refer.params, "mode", null), null)
                name         = config_map.value.volume_refer.params.name
              }
            }
            dynamic "secret" {
              for_each = volume.value.volume_refer.schema == "k8s:secret" ? [volume.value] : []
              content {
                default_mode = try(lookup(secret.value.volume_refer.params, "mode", null), null)
                secret_name  = secret.value.volume_refer.params.name
              }
            }
            dynamic "persistent_volume_claim" {
              for_each = volume.value.volume_refer.schema == "k8s:persistentvolumeclaim" ? [volume.value] : []
              content {
                read_only  = try(lookup(persistent_volume_claim.value.volume_refer.params, "readonly", null), false)
                claim_name = persistent_volume_claim.value.volume_refer.params.name
              }
            }
          }
        }

        ### configure init containers.
        dynamic "init_container" {
          for_each = try(nonsensitive(local.init_containers), local.init_containers)
          content {
            #### configure basic.
            name              = init_container.value.name
            image             = init_container.value.image
            image_pull_policy = "IfNotPresent"
            working_dir       = try(init_container.value.execute.working_dir, null)
            command           = try(init_container.value.execute.command, null)
            args              = try(init_container.value.execute.args, null)
            security_context {
              read_only_root_filesystem = try(init_container.value.execute.readonly_rootfs, false)
              run_as_user               = try(init_container.value.execute.as_user, null)
              run_as_group              = try(init_container.value.execute.as_group, null)
            }

            #### configure resources.
            dynamic "resources" {
              for_each = init_container.value.resources != null ? try(
                [nonsensitive(init_container.value.resources)],
                [init_container.value.resources]
              ) : []
              content {
                requests = {
                  for k, v in resources.value : "%{if k == "gpu"}${local.gpu_vendor}/%{endif}${k}" => "%{if k == "memory"}${v}Mi%{else}${v}%{endif}"
                  if try(v != null && v > 0, false)
                }
                limits = {
                  for k, v in resources.value : "%{if k == "gpu"}${local.gpu_vendor}/%{endif}${k}" => "%{if k == "memory"}${v}Mi%{else}${v}%{endif}"
                  if try(v != null && v > 0, false) && k != "cpu"
                }
              }
            }

            #### configure downward-api envs.
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

            #### configure ephemeral envs.
            dynamic "env" {
              for_each = local.container_ephemeral_envs_map[init_container.value.name] != null ? try(
                nonsensitive(local.container_ephemeral_envs_map[init_container.value.name]),
                local.container_ephemeral_envs_map[init_container.value.name]
              ) : []
              content {
                name  = env.value.name
                value = env.value.value
              }
            }

            #### configure refer envs.
            dynamic "env" {
              for_each = local.container_refer_envs_map[init_container.value.name] != null ? try(
                nonsensitive(local.container_refer_envs_map[init_container.value.name]),
                local.container_refer_envs_map[init_container.value.name]
              ) : []
              content {
                name = env.value.name
                value_from {
                  secret_key_ref {
                    name = env.value.value_refer.params.name
                    key  = env.value.value_refer.params.key
                  }
                }
              }
            }

            #### configure ephemeral files.
            dynamic "volume_mount" {
              for_each = local.container_ephemeral_files_map[init_container.value.name] != null ? try(
                nonsensitive(local.container_ephemeral_files_map[init_container.value.name]),
                local.container_ephemeral_files_map[init_container.value.name]
              ) : []
              content {
                name       = volume_mount.value.name
                mount_path = dirname(volume_mount.value.path)
              }
            }

            #### configure refer files.
            dynamic "volume_mount" {
              for_each = local.container_refer_files_map[init_container.value.name] != null ? try(
                nonsensitive(local.container_refer_files_map[init_container.value.name]),
                local.container_refer_files_map[init_container.value.name]
              ) : []
              content {
                name       = volume_mount.value.name
                mount_path = volume_mount.value.path
                sub_path   = basename(volume_mount.value.path)
              }
            }

            #### configure ephemeral mounts.
            dynamic "volume_mount" {
              for_each = local.container_ephemeral_mounts_map[init_container.value.name] != null ? try(
                nonsensitive(local.container_ephemeral_mounts_map[init_container.value.name]),
                local.container_ephemeral_mounts_map[init_container.value.name]
              ) : []
              content {
                name       = volume_mount.value.name
                mount_path = volume_mount.value.path
                read_only  = try(volume_mount.value.readonly, null)
                sub_path   = try(volume_mount.value.subpath, null)
              }
            }

            #### configure refer mounts.
            dynamic "volume_mount" {
              for_each = local.container_refer_mounts_map[init_container.value.name] != null ? try(
                nonsensitive(local.container_refer_mounts_map[init_container.value.name]),
                local.container_refer_mounts_map[init_container.value.name]
              ) : []
              content {
                name       = volume_mount.value.name
                mount_path = volume_mount.value.path
                read_only  = try(volume_mount.value.readonly, null)
                sub_path   = try(volume_mount.value.subpath, null)
              }
            }
          }
        }

        ### configure run containers.
        dynamic "container" {
          for_each = try(nonsensitive(local.run_containers), local.run_containers)
          content {
            #### configure basic.
            name              = container.value.name
            image             = container.value.image
            image_pull_policy = "IfNotPresent"
            working_dir       = try(container.value.execute.working_dir, null)
            command           = try(container.value.execute.command, null)
            args              = try(container.value.execute.args, null)
            security_context {
              read_only_root_filesystem = try(container.value.execute.readonly_rootfs, false)
              run_as_user               = try(container.value.execute.as_user, null)
              run_as_group              = try(container.value.execute.as_group, null)
            }

            #### configure resources.
            dynamic "resources" {
              for_each = container.value.resources != null ? try(
                [nonsensitive(container.value.resources)],
                [container.value.resources]
              ) : []
              content {
                requests = {
                  for k, v in resources.value : "%{if k == "gpu"}${local.gpu_vendor}/%{endif}${k}" => "%{if k == "memory"}${v}Mi%{else}${v}%{endif}"
                  if try(v != null && v > 0, false)
                }
                limits = {
                  for k, v in resources.value : "%{if k == "gpu"}${local.gpu_vendor}/%{endif}${k}" => "%{if k == "memory"}${v}Mi%{else}${v}%{endif}"
                  if try(v != null && v > 0, false) && k != "cpu"
                }
              }
            }

            #### configure downward-api envs.
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

            #### configure ephemeral envs.
            dynamic "env" {
              for_each = local.container_ephemeral_envs_map[container.value.name] != null ? try(
                nonsensitive(local.container_ephemeral_envs_map[container.value.name]),
                local.container_ephemeral_envs_map[container.value.name]
              ) : []
              content {
                name  = env.value.name
                value = env.value.value
              }
            }

            #### configure refer envs.
            dynamic "env" {
              for_each = local.container_refer_envs_map[container.value.name] != null ? try(
                nonsensitive(local.container_refer_envs_map[container.value.name]),
                local.container_refer_envs_map[container.value.name]
              ) : []
              content {
                name = env.value.name
                value_from {
                  secret_key_ref {
                    name = env.value.value_refer.params.name
                    key  = env.value.value_refer.params.key
                  }
                }
              }
            }

            #### configure ephemeral files.
            dynamic "volume_mount" {
              for_each = local.container_ephemeral_files_map[container.value.name] != null ? try(
                nonsensitive(local.container_ephemeral_files_map[container.value.name]),
                local.container_ephemeral_files_map[container.value.name]
              ) : []
              content {
                name       = volume_mount.value.name
                mount_path = dirname(volume_mount.value.path)
              }
            }

            #### configure refer files.
            dynamic "volume_mount" {
              for_each = local.container_refer_files_map[container.value.name] != null ? try(
                nonsensitive(local.container_refer_files_map[container.value.name]),
                local.container_refer_files_map[container.value.name]
              ) : []
              content {
                name       = volume_mount.value.name
                mount_path = volume_mount.value.path
                sub_path   = basename(volume_mount.value.path)
              }
            }

            #### configure ephemeral mounts.
            dynamic "volume_mount" {
              for_each = local.container_ephemeral_mounts_map[container.value.name] != null ? try(
                nonsensitive(local.container_ephemeral_mounts_map[container.value.name]),
                local.container_ephemeral_mounts_map[container.value.name]
              ) : []
              content {
                name       = volume_mount.value.name
                mount_path = volume_mount.value.path
                read_only  = try(volume_mount.value.readonly, null)
                sub_path   = try(volume_mount.value.subpath, null)
              }
            }

            #### configure refer mounts.
            dynamic "volume_mount" {
              for_each = local.container_refer_mounts_map[container.value.name] != null ? try(
                nonsensitive(local.container_refer_mounts_map[container.value.name]),
                local.container_refer_mounts_map[container.value.name]
              ) : []
              content {
                name       = volume_mount.value.name
                mount_path = volume_mount.value.path
                read_only  = try(volume_mount.value.readonly, null)
                sub_path   = try(volume_mount.value.subpath, null)
              }
            }

            #### configure checks.
            dynamic "startup_probe" {
              for_each = [
                for ck in container.value.checks : ck
                if try(ck.delay > 0 && !ck.teardown, false)
              ]
              content {
                initial_delay_seconds = startup_probe.value.delay
                period_seconds        = startup_probe.value.interval
                timeout_seconds       = startup_probe.value.timeout
                failure_threshold     = startup_probe.value.retries
                dynamic "exec" {
                  for_each = startup_probe.value.type == "execute" ? [startup_probe.value.execute] : []
                  content {
                    command = exec.value.command
                  }
                }
                dynamic "tcp_socket" {
                  for_each = startup_probe.value.type == "tcp" ? [startup_probe.value.tcp] : []
                  content {
                    port = tcp_socket.value.port
                  }
                }
                dynamic "grpc" {
                  for_each = startup_probe.value.type == "grpc" ? [startup_probe.value.grpc] : []
                  content {
                    port    = grpc.value.port
                    service = grpc.value.service
                  }
                }
                dynamic "http_get" {
                  for_each = startup_probe.value.type == "http" ? [startup_probe.value.http] : []
                  content {
                    port   = http_get.value.port
                    path   = http_get.value.path
                    scheme = "HTTP"
                    dynamic "http_header" {
                      for_each = try(http_get.value.headers != null, false) ? http_get.value.headers : {}
                      content {
                        name  = http_header.value.name
                        value = http_header.value.value
                      }
                    }
                  }
                }
                dynamic "http_get" {
                  for_each = startup_probe.value.type == "https" ? [startup_probe.value.https] : []
                  content {
                    port   = http_get.value.port
                    path   = http_get.value.path
                    scheme = "HTTPS"
                    dynamic "http_header" {
                      for_each = try(http_get.value.headers != null, false) ? http_get.value.headers : {}
                      content {
                        name  = http_header.value.name
                        value = http_header.value.value
                      }
                    }
                  }
                }
              }
            }

            dynamic "readiness_probe" {
              for_each = [
                for ck in container.value.checks : ck
                if try(ck.delay == 0 && !ck.teardown, false)
              ]
              content {
                initial_delay_seconds = readiness_probe.value.delay
                period_seconds        = readiness_probe.value.interval
                timeout_seconds       = readiness_probe.value.timeout
                failure_threshold     = readiness_probe.value.retries
                dynamic "exec" {
                  for_each = readiness_probe.value.type == "execute" ? [readiness_probe.value.execute] : []
                  content {
                    command = exec.value.command
                  }
                }
                dynamic "tcp_socket" {
                  for_each = readiness_probe.value.type == "tcp" ? [readiness_probe.value.tcp] : []
                  content {
                    port = tcp_socket.value.port
                  }
                }
                dynamic "grpc" {
                  for_each = readiness_probe.value.type == "grpc" ? [readiness_probe.value.grpc] : []
                  content {
                    port    = grpc.value.port
                    service = grpc.value.service
                  }
                }
                dynamic "http_get" {
                  for_each = readiness_probe.value.type == "http" ? [readiness_probe.value.http] : []
                  content {
                    port   = http_get.value.port
                    path   = http_get.value.path
                    scheme = "HTTP"
                    dynamic "http_header" {
                      for_each = try(http_get.value.headers != null, false) ? http_get.value.headers : {}
                      content {
                        name  = http_header.value.name
                        value = http_header.value.value
                      }
                    }
                  }
                }
                dynamic "http_get" {
                  for_each = readiness_probe.value.type == "https" ? [readiness_probe.value.https] : []
                  content {
                    port   = http_get.value.port
                    path   = http_get.value.path
                    scheme = "HTTPS"
                    dynamic "http_header" {
                      for_each = try(http_get.value.headers != null, false) ? http_get.value.headers : {}
                      content {
                        name  = http_header.value.name
                        value = http_header.value.value
                      }
                    }
                  }
                }
              }
            }

            dynamic "liveness_probe" {
              for_each = [
                for ck in container.value.checks : ck
                if try(ck.teardown, false)
              ]
              content {
                initial_delay_seconds = liveness_probe.value.delay
                period_seconds        = liveness_probe.value.interval
                timeout_seconds       = liveness_probe.value.timeout
                failure_threshold     = liveness_probe.value.retries
                dynamic "exec" {
                  for_each = liveness_probe.value.type == "execute" ? [liveness_probe.value.execute] : []
                  content {
                    command = exec.value.command
                  }
                }
                dynamic "tcp_socket" {
                  for_each = liveness_probe.value.type == "tcp" ? [liveness_probe.value.tcp] : []
                  content {
                    port = tcp_socket.value.port
                  }
                }
                dynamic "grpc" {
                  for_each = liveness_probe.value.type == "grpc" ? [liveness_probe.value.grpc] : []
                  content {
                    port    = grpc.value.port
                    service = grpc.value.service
                  }
                }
                dynamic "http_get" {
                  for_each = liveness_probe.value.type == "http" ? [liveness_probe.value.http] : []
                  content {
                    port   = http_get.value.port
                    path   = http_get.value.path
                    scheme = "HTTP"
                    dynamic "http_header" {
                      for_each = try(http_get.value.headers != null, false) ? http_get.value.headers : {}
                      content {
                        name  = http_header.value.name
                        value = http_header.value.value
                      }
                    }
                  }
                }
                dynamic "http_get" {
                  for_each = liveness_probe.value.type == "https" ? [liveness_probe.value.https] : []
                  content {
                    port   = http_get.value.port
                    path   = http_get.value.path
                    scheme = "HTTPS"
                    dynamic "http_header" {
                      for_each = try(http_get.value.headers != null, false) ? http_get.value.headers : {}
                      content {
                        name  = http_header.value.name
                        value = http_header.value.value
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
  }

  lifecycle {
    replace_triggered_by = [terraform_data.replacement[0]]
  }
}

resource "kubernetes_cron_job_v1" "task" {
  count = local.mode == "periodic" ? 1 : 0

  metadata {
    namespace     = local.namespace
    generate_name = format("%s-", local.resource_name)
    annotations   = local.annotations
    labels        = local.labels
  }

  spec {
    ### scaling.
    starting_deadline_seconds     = 10
    successful_jobs_history_limit = 5
    failed_jobs_history_limit     = 3
    schedule                      = var.task.periodic.cron_expression
    timezone                      = coalesce(var.task.periodic.timezone, "Etc/UTC")
    suspend                       = try(var.task.periodic.suspend == true, false)
    concurrency_policy            = try(var.task.periodic.keep_unfinished == true, false) ? "Forbid" : "Replace"

    job_template {
      metadata {
        annotations = local.annotations
        labels      = local.labels
      }

      spec {
        ### scaling.
        active_deadline_seconds    = try(var.task.timeout != null && var.task.timeout > 0, false) ? var.task.timeout : null
        completions                = local.completions
        parallelism                = try(var.task.parallelism != null && var.task.parallelism > 0, false) ? var.task.parallelism : null
        backoff_limit              = var.task.retries
        ttl_seconds_after_finished = try(var.task.cleanup_finished != null && var.task.cleanup_finished, false) ? 300 : null
        completion_mode            = local.completions == null ? "NonIndexed" : "Indexed"

        template {
          metadata {
            annotations = local.annotations
            labels      = local.labels
          }

          spec {
            ### configure basic.
            automount_service_account_token = false
            restart_policy                  = try(var.task.keep_failed_process != null && var.task.keep_failed_process, true) ? "Never" : "OnFailure"
            subdomain                       = local.completions != null ? kubernetes_service_v1.tasks[0].metadata[0].name : null
            dynamic "security_context" {
              for_each = try(length(var.task.sysctls), 0) > 0 || try(var.task.fs_group != null, false) ? [{}] : []
              content {
                dynamic "sysctl" {
                  for_each = try(var.task.sysctls != null, false) ? try(
                    nonsensitive(var.task.sysctls),
                    var.task.sysctls
                  ) : []
                  content {
                    name  = sysctl.value.name
                    value = sysctl.value.value
                  }
                }
                fs_group = try(var.task.fs_group, null)
              }
            }

            ### declare ephemeral files.
            dynamic "volume" {
              for_each = try(nonsensitive(local.ephemeral_files), local.ephemeral_files)
              content {
                name = volume.value.name
                config_map {
                  default_mode = volume.value.mode
                  name         = volume.value.name
                  items {
                    key  = "content"
                    path = basename(volume.value.path)
                  }
                }
              }
            }

            ### declare refer files.
            dynamic "volume" {
              for_each = try(nonsensitive(local.refer_files), local.refer_files)
              content {
                name = volume.value.name
                dynamic "config_map" {
                  for_each = volume.value.content_refer.schema == "k8s:configmap" ? [volume.value] : []
                  content {
                    default_mode = config_map.value.mode
                    name         = config_map.value.content_refer.params.name
                    items {
                      key  = config_map.value.content_refer.params.key
                      path = basename(config_map.value.path)
                    }
                  }
                }
                dynamic "secret" {
                  for_each = volume.value.content_refer.schema == "k8s:secret" ? [volume.value] : []
                  content {
                    default_mode = secret.value.mode
                    secret_name  = secret.value.content_refer.params.name
                    items {
                      key  = secret.value.content_refer.params.key
                      path = basename(secret.value.path)
                    }
                  }
                }
              }
            }

            ### declare ephemeral mounts.
            dynamic "volume" {
              for_each = try(nonsensitive(local.ephemeral_mounts), local.ephemeral_mounts)
              content {
                name = volume.value.name
                empty_dir {}
              }
            }

            ### declare refer mounts.
            dynamic "volume" {
              for_each = try(nonsensitive(local.refer_mounts), local.refer_mounts)
              content {
                name = volume.value.name
                dynamic "config_map" {
                  for_each = volume.value.volume_refer.schema == "k8s:configmap" ? [volume.value] : []
                  content {
                    default_mode = try(lookup(config_map.value.volume_refer.params, "mode", null), null)
                    name         = config_map.value.volume_refer.params.name
                  }
                }
                dynamic "secret" {
                  for_each = volume.value.volume_refer.schema == "k8s:secret" ? [volume.value] : []
                  content {
                    default_mode = try(lookup(secret.value.volume_refer.params, "mode", null), null)
                    secret_name  = secret.value.volume_refer.params.name
                  }
                }
                dynamic "persistent_volume_claim" {
                  for_each = volume.value.volume_refer.schema == "k8s:persistentvolumeclaim" ? [volume.value] : []
                  content {
                    read_only  = try(lookup(persistent_volume_claim.value.volume_refer.params, "readonly", null), false)
                    claim_name = persistent_volume_claim.value.volume_refer.params.name
                  }
                }
              }
            }

            ### configure init containers.
            dynamic "init_container" {
              for_each = try(nonsensitive(local.init_containers), local.init_containers)
              content {
                #### configure basic.
                name              = init_container.value.name
                image             = init_container.value.image
                image_pull_policy = "IfNotPresent"
                working_dir       = try(init_container.value.execute.working_dir, null)
                command           = try(init_container.value.execute.command, null)
                args              = try(init_container.value.execute.args, null)
                security_context {
                  read_only_root_filesystem = try(init_container.value.execute.readonly_rootfs, false)
                  run_as_user               = try(init_container.value.execute.as_user, null)
                  run_as_group              = try(init_container.value.execute.as_group, null)
                }

                #### configure resources.
                dynamic "resources" {
                  for_each = init_container.value.resources != null ? try(
                    [nonsensitive(init_container.value.resources)],
                    [init_container.value.resources]
                  ) : []
                  content {
                    requests = {
                      for k, v in resources.value : "%{if k == "gpu"}${local.gpu_vendor}/%{endif}${k}" => "%{if k == "memory"}${v}Mi%{else}${v}%{endif}"
                      if try(v != null && v > 0, false)
                    }
                    limits = {
                      for k, v in resources.value : "%{if k == "gpu"}${local.gpu_vendor}/%{endif}${k}" => "%{if k == "memory"}${v}Mi%{else}${v}%{endif}"
                      if try(v != null && v > 0, false) && k != "cpu"
                    }
                  }
                }

                #### configure downward-api envs.
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

                #### configure ephemeral envs.
                dynamic "env" {
                  for_each = local.container_ephemeral_envs_map[init_container.value.name] != null ? try(
                    nonsensitive(local.container_ephemeral_envs_map[init_container.value.name]),
                    local.container_ephemeral_envs_map[init_container.value.name]
                  ) : []
                  content {
                    name  = env.value.name
                    value = env.value.value
                  }
                }

                #### configure refer envs.
                dynamic "env" {
                  for_each = local.container_refer_envs_map[init_container.value.name] != null ? try(
                    nonsensitive(local.container_refer_envs_map[init_container.value.name]),
                    local.container_refer_envs_map[init_container.value.name]
                  ) : []
                  content {
                    name = env.value.name
                    value_from {
                      secret_key_ref {
                        name = env.value.value_refer.params.name
                        key  = env.value.value_refer.params.key
                      }
                    }
                  }
                }

                #### configure ephemeral files.
                dynamic "volume_mount" {
                  for_each = local.container_ephemeral_files_map[init_container.value.name] != null ? try(
                    nonsensitive(local.container_ephemeral_files_map[init_container.value.name]),
                    local.container_ephemeral_files_map[init_container.value.name]
                  ) : []
                  content {
                    name       = volume_mount.value.name
                    mount_path = dirname(volume_mount.value.path)
                  }
                }

                #### configure refer files.
                dynamic "volume_mount" {
                  for_each = local.container_refer_files_map[init_container.value.name] != null ? try(
                    nonsensitive(local.container_refer_files_map[init_container.value.name]),
                    local.container_refer_files_map[init_container.value.name]
                  ) : []
                  content {
                    name       = volume_mount.value.name
                    mount_path = volume_mount.value.path
                    sub_path   = basename(volume_mount.value.path)
                  }
                }

                #### configure ephemeral mounts.
                dynamic "volume_mount" {
                  for_each = local.container_ephemeral_mounts_map[init_container.value.name] != null ? try(
                    nonsensitive(local.container_ephemeral_mounts_map[init_container.value.name]),
                    local.container_ephemeral_mounts_map[init_container.value.name]
                  ) : []
                  content {
                    name       = volume_mount.value.name
                    mount_path = volume_mount.value.path
                    read_only  = try(volume_mount.value.readonly, null)
                    sub_path   = try(volume_mount.value.subpath, null)
                  }
                }

                #### configure refer mounts.
                dynamic "volume_mount" {
                  for_each = local.container_refer_mounts_map[init_container.value.name] != null ? try(
                    nonsensitive(local.container_refer_mounts_map[init_container.value.name]),
                    local.container_refer_mounts_map[init_container.value.name]
                  ) : []
                  content {
                    name       = volume_mount.value.name
                    mount_path = volume_mount.value.path
                    read_only  = try(volume_mount.value.readonly, null)
                    sub_path   = try(volume_mount.value.subpath, null)
                  }
                }
              }
            }

            ### configure run containers.
            dynamic "container" {
              for_each = try(nonsensitive(local.run_containers), local.run_containers)
              content {
                #### configure basic.
                name              = container.value.name
                image             = container.value.image
                image_pull_policy = "IfNotPresent"
                working_dir       = try(container.value.execute.working_dir, null)
                command           = try(container.value.execute.command, null)
                args              = try(container.value.execute.args, null)
                security_context {
                  read_only_root_filesystem = try(container.value.execute.readonly_rootfs, false)
                  run_as_user               = try(container.value.execute.as_user, null)
                  run_as_group              = try(container.value.execute.as_group, null)
                }

                #### configure resources.
                dynamic "resources" {
                  for_each = container.value.resources != null ? try(
                    [nonsensitive(container.value.resources)],
                    [container.value.resources]
                  ) : []
                  content {
                    requests = {
                      for k, v in resources.value : "%{if k == "gpu"}${local.gpu_vendor}/%{endif}${k}" => "%{if k == "memory"}${v}Mi%{else}${v}%{endif}"
                      if try(v != null && v > 0, false)
                    }
                    limits = {
                      for k, v in resources.value : "%{if k == "gpu"}${local.gpu_vendor}/%{endif}${k}" => "%{if k == "memory"}${v}Mi%{else}${v}%{endif}"
                      if try(v != null && v > 0, false) && k != "cpu"
                    }
                  }
                }

                #### configure downward-api envs.
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

                #### configure ephemeral envs.
                dynamic "env" {
                  for_each = local.container_ephemeral_envs_map[container.value.name] != null ? try(
                    nonsensitive(local.container_ephemeral_envs_map[container.value.name]),
                    local.container_ephemeral_envs_map[container.value.name]
                  ) : []
                  content {
                    name  = env.value.name
                    value = env.value.value
                  }
                }

                #### configure refer envs.
                dynamic "env" {
                  for_each = local.container_refer_envs_map[container.value.name] != null ? try(
                    nonsensitive(local.container_refer_envs_map[container.value.name]),
                    local.container_refer_envs_map[container.value.name]
                  ) : []
                  content {
                    name = env.value.name
                    value_from {
                      secret_key_ref {
                        name = env.value.value_refer.params.name
                        key  = env.value.value_refer.params.key
                      }
                    }
                  }
                }

                #### configure ephemeral files.
                dynamic "volume_mount" {
                  for_each = local.container_ephemeral_files_map[container.value.name] != null ? try(
                    nonsensitive(local.container_ephemeral_files_map[container.value.name]),
                    local.container_ephemeral_files_map[container.value.name]
                  ) : []
                  content {
                    name       = volume_mount.value.name
                    mount_path = dirname(volume_mount.value.path)
                  }
                }

                #### configure refer files.
                dynamic "volume_mount" {
                  for_each = local.container_refer_files_map[container.value.name] != null ? try(
                    nonsensitive(local.container_refer_files_map[container.value.name]),
                    local.container_refer_files_map[container.value.name]
                  ) : []
                  content {
                    name       = volume_mount.value.name
                    mount_path = volume_mount.value.path
                    sub_path   = basename(volume_mount.value.path)
                  }
                }

                #### configure ephemeral mounts.
                dynamic "volume_mount" {
                  for_each = local.container_ephemeral_mounts_map[container.value.name] != null ? try(
                    nonsensitive(local.container_ephemeral_mounts_map[container.value.name]),
                    local.container_ephemeral_mounts_map[container.value.name]
                  ) : []
                  content {
                    name       = volume_mount.value.name
                    mount_path = volume_mount.value.path
                    read_only  = try(volume_mount.value.readonly, null)
                    sub_path   = try(volume_mount.value.subpath, null)
                  }
                }

                #### configure refer mounts.
                dynamic "volume_mount" {
                  for_each = local.container_refer_mounts_map[container.value.name] != null ? try(
                    nonsensitive(local.container_refer_mounts_map[container.value.name]),
                    local.container_refer_mounts_map[container.value.name]
                  ) : []
                  content {
                    name       = volume_mount.value.name
                    mount_path = volume_mount.value.path
                    read_only  = try(volume_mount.value.readonly, null)
                    sub_path   = try(volume_mount.value.subpath, null)
                  }
                }

                #### configure checks.
                dynamic "startup_probe" {
                  for_each = [
                    for ck in container.value.checks : ck
                    if try(ck.delay > 0 && !ck.teardown, false)
                  ]
                  content {
                    initial_delay_seconds = startup_probe.value.delay
                    period_seconds        = startup_probe.value.interval
                    timeout_seconds       = startup_probe.value.timeout
                    failure_threshold     = startup_probe.value.retries
                    dynamic "exec" {
                      for_each = startup_probe.value.type == "execute" ? [startup_probe.value.execute] : []
                      content {
                        command = exec.value.command
                      }
                    }
                    dynamic "tcp_socket" {
                      for_each = startup_probe.value.type == "tcp" ? [startup_probe.value.tcp] : []
                      content {
                        port = tcp_socket.value.port
                      }
                    }
                    dynamic "grpc" {
                      for_each = startup_probe.value.type == "grpc" ? [startup_probe.value.grpc] : []
                      content {
                        port    = grpc.value.port
                        service = grpc.value.service
                      }
                    }
                    dynamic "http_get" {
                      for_each = startup_probe.value.type == "http" ? [startup_probe.value.http] : []
                      content {
                        port   = http_get.value.port
                        path   = http_get.value.path
                        scheme = "HTTP"
                        dynamic "http_header" {
                          for_each = try(http_get.value.headers != null, false) ? http_get.value.headers : {}
                          content {
                            name  = http_header.value.name
                            value = http_header.value.value
                          }
                        }
                      }
                    }
                    dynamic "http_get" {
                      for_each = startup_probe.value.type == "https" ? [startup_probe.value.https] : []
                      content {
                        port   = http_get.value.port
                        path   = http_get.value.path
                        scheme = "HTTPS"
                        dynamic "http_header" {
                          for_each = try(http_get.value.headers != null, false) ? http_get.value.headers : {}
                          content {
                            name  = http_header.value.name
                            value = http_header.value.value
                          }
                        }
                      }
                    }
                  }
                }

                dynamic "readiness_probe" {
                  for_each = [
                    for ck in container.value.checks : ck
                    if try(ck.delay == 0 && !ck.teardown, false)
                  ]
                  content {
                    initial_delay_seconds = readiness_probe.value.delay
                    period_seconds        = readiness_probe.value.interval
                    timeout_seconds       = readiness_probe.value.timeout
                    failure_threshold     = readiness_probe.value.retries
                    dynamic "exec" {
                      for_each = readiness_probe.value.type == "execute" ? [readiness_probe.value.execute] : []
                      content {
                        command = exec.value.command
                      }
                    }
                    dynamic "tcp_socket" {
                      for_each = readiness_probe.value.type == "tcp" ? [readiness_probe.value.tcp] : []
                      content {
                        port = tcp_socket.value.port
                      }
                    }
                    dynamic "grpc" {
                      for_each = readiness_probe.value.type == "grpc" ? [readiness_probe.value.grpc] : []
                      content {
                        port    = grpc.value.port
                        service = grpc.value.service
                      }
                    }
                    dynamic "http_get" {
                      for_each = readiness_probe.value.type == "http" ? [readiness_probe.value.http] : []
                      content {
                        port   = http_get.value.port
                        path   = http_get.value.path
                        scheme = "HTTP"
                        dynamic "http_header" {
                          for_each = try(http_get.value.headers != null, false) ? http_get.value.headers : {}
                          content {
                            name  = http_header.value.name
                            value = http_header.value.value
                          }
                        }
                      }
                    }
                    dynamic "http_get" {
                      for_each = readiness_probe.value.type == "https" ? [readiness_probe.value.https] : []
                      content {
                        port   = http_get.value.port
                        path   = http_get.value.path
                        scheme = "HTTPS"
                        dynamic "http_header" {
                          for_each = try(http_get.value.headers != null, false) ? http_get.value.headers : {}
                          content {
                            name  = http_header.value.name
                            value = http_header.value.value
                          }
                        }
                      }
                    }
                  }
                }

                dynamic "liveness_probe" {
                  for_each = [
                    for ck in container.value.checks : ck
                    if try(ck.teardown, false)
                  ]
                  content {
                    initial_delay_seconds = liveness_probe.value.delay
                    period_seconds        = liveness_probe.value.interval
                    timeout_seconds       = liveness_probe.value.timeout
                    failure_threshold     = liveness_probe.value.retries
                    dynamic "exec" {
                      for_each = liveness_probe.value.type == "execute" ? [liveness_probe.value.execute] : []
                      content {
                        command = exec.value.command
                      }
                    }
                    dynamic "tcp_socket" {
                      for_each = liveness_probe.value.type == "tcp" ? [liveness_probe.value.tcp] : []
                      content {
                        port = tcp_socket.value.port
                      }
                    }
                    dynamic "grpc" {
                      for_each = liveness_probe.value.type == "grpc" ? [liveness_probe.value.grpc] : []
                      content {
                        port    = grpc.value.port
                        service = grpc.value.service
                      }
                    }
                    dynamic "http_get" {
                      for_each = liveness_probe.value.type == "http" ? [liveness_probe.value.http] : []
                      content {
                        port   = http_get.value.port
                        path   = http_get.value.path
                        scheme = "HTTP"
                        dynamic "http_header" {
                          for_each = try(http_get.value.headers != null, false) ? http_get.value.headers : {}
                          content {
                            name  = http_header.value.name
                            value = http_header.value.value
                          }
                        }
                      }
                    }
                    dynamic "http_get" {
                      for_each = liveness_probe.value.type == "https" ? [liveness_probe.value.https] : []
                      content {
                        port   = http_get.value.port
                        path   = http_get.value.path
                        scheme = "HTTPS"
                        dynamic "http_header" {
                          for_each = try(http_get.value.headers != null, false) ? http_get.value.headers : {}
                          content {
                            name  = http_header.value.name
                            value = http_header.value.value
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
