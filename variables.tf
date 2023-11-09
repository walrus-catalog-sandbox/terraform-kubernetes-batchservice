#
# Contextual Fields
#

variable "context" {
  description = <<-EOF
Receive contextual information. When Walrus deploys, Walrus will inject specific contextual information into this field.

Examples:
```
context:
  project:
    name: string
    id: string
  environment:
    name: string
    id: string
  resource:
    name: string
    id: string
```
EOF
  type        = map(any)
  default     = {}
}

#
# Infrastructure Fields
#

variable "infrastructure" {
  description = <<-EOF
Specify the infrastructure information for deploying.

Examples:
```
infrastructure:
  namespace: string, optional
  gpu_vendor: string, optional
```
EOF
  type = object({
    namespace  = optional(string)
    gpu_vendor = optional(string, "nvidia.com")
  })
  default = {}
}

#
# Deployment Fields
#

variable "deployment" {
  description = <<-EOF
Specify the task action, like execution, security and so on.

Examples:
```
deployment:
  timeout: number, optional
  completions: number, optional
  parallelism: number, optional
  retries: number, optional
  cleanup: bool, optional                  # cleanup after 5m
  execute_strategy:
    type: once/periodic
    once: {}
    periodic:
      cron_expression: string
      timezone: string, optional           # https://en.wikipedia.org/wiki/List_of_tz_database_time_zones
      suspend: bool, optional
      keep_not_finished: bool, optional    # forbids concurrent runs if true
  system_controls:
  - name: string
    value: string
```
EOF
  type = object({
    timeout     = optional(number)
    completions = optional(number)
    parallelism = optional(number)
    retries     = optional(number, 6)
    cleanup     = optional(bool, false)
    execute_strategy = optional(object({
      type = optional(string, "once")
      once = optional(object({}), {})
      periodic = optional(object({
        cron_expression   = string
        timezone          = optional(string)
        suspend           = optional(bool, false)
        keep_not_finished = optional(bool, false)
      }))
    }))
    system_controls = optional(list(object({
      name  = string
      value = string
    })))
  })
  default = {
    timeout = 0
    retries = 6
    execute_strategy = {
      cleanup = false
      type    = "once"
      once    = {}
    }
  }
}

#
# Prerequisite Fields
#

variable "credentials" {
  description = <<-EOF
Specify the credential items to fetch private data, like an internal image registry.

Examples:
```
credentials:
- name: string                           # unique
  type: image_registry
  image_registry: 
    server: string
    username: string
    password: string
    email: string, optional
```
EOF
  type = list(object({
    name = string
    type = optional(string, "image_registry")
    image_registry = optional(object({
      server   = string
      username = string
      password = string
      email    = optional(string)
    }))
  }))
  default = []
}

variable "configs" {
  description = <<-EOF
Specify the configuration items to configure containers, either raw or sensitive data.

Examples:
```
configs:
- name: string                           # unique
  type: data                             # convert to config map
  data: 
    (key: string): string
- name: string
  type: secret                           # convert to secret
  secret:
    (key: string): string
```
EOF
  type = list(object({
    name   = string
    type   = optional(string, "data")
    data   = optional(map(string))
    secret = optional(map(string))
  }))
  default = []
}

variable "storages" {
  description = <<-EOF
Specify the storage items to mount containers.

Examples:
```
storages:
- name: string                           # unique
  type: empty                            # convert ot empty_dir volume
  empty:
    medium: string, optional
    size: number, optional               # in megabyte
- name: string
  type: nas                              # convert to in-tree nfs volume
  nas:
    read_only: bool, optional
    server: string
    path: string, optional
    username: string, optional
    password: string, optional
- name: string
  type: san                              # convert to in-tree fc or iscsi volume
  san:
    read_only: bool, optional
    fs_type: string, optional
    type: fc/iscsi
    fc: 
      lun: number
      wwns: list(string)
    iscsi
      lun: number, optional
      portal: string
      iqn: string
- name: string
  type: ephemeral                         # convert to dynamic volume claim template
  ephemeral:
    class: string, optional
    access_mode: string, optional
    size: number, optional                # in megabyte
- name: string
  type: persistent                        # convert to existing volume claim template
  persistent:
    read_only: bool, optional
    name: string                          # the name of persistent volume claim
```
EOF
  type = list(object({
    name = string
    type = optional(string, "empty")
    empty = optional(object({
      medium = optional(string)
      size   = optional(number)
    }))
    nas = optional(object({
      read_only = optional(bool, false)
      server    = string
      path      = optional(string, "/")
      username  = optional(string)
      password  = optional(string)
    }))
    san = optional(object({
      read_only = optional(bool, false)
      fs_type   = optional(string, "ext4")
      type      = string
      fc = optional(object({
        lun  = optional(number, 0)
        wwns = list(string)
      }))
      iscsi = optional(object({
        lun    = optional(number, 0)
        portal = string
        iqn    = string
      }))
    }))
    ephemeral = optional(object({
      class       = optional(string)
      access_mode = optional(string, "ReadWriteOnce")
      size        = number
    }))
    persistent = optional(object({
      read_only = optional(bool, false)
      name      = string
    }))
  }))
  default = []
}

#
# Main Fields
#

variable "containers" {
  description = <<-EOF
Specify the container items to deployment.

Examples:
```
containers:
- name: string                           # unique
  profile: init/run
  image:
    name: string
    pull_policy: string, optional
  execute:
    command: list(string), optional
    args: list(string), optional
    working_dir: string, optional
    as: string, optional                # i.e. non_root, user_id:group:id
  resources:
    requests:
      cpu: number, optional             # in oneCPU, i.e. 0.25, 0.5, 1, 2, 4, 8
      memory: number, optional          # in megabyte
      gpu: number, optional             # i.e. 0.25, 0.5, 1, 2, 4, 8
    limits:
      cpu: number, optioanl             # in oneCPU, i.e. 0.25, 0.5, 1, 2, 4, 8
      memory: number, optional          # in megabyte
      gpu: number, optional             # i.e. 0.25, 0.5, 1, 2, 4, 8
  envs:
  - name: string, optional              # only work if the config.key is null
    type: text/config
    text:
      content: string
    config:
      name: string
      key: string, optional
  mounts:
  - path: string                        # unique
    read_only: bool, optional
    type: config/storage
    config:
      name: string
      key: string, optional
      mode: string, optional
      disable_changed: bool, optional   # only work if config.key is not null
    storage:
      name: string
      sub_path: string, optional
```
EOF
  type = list(object({
    name    = string
    profile = optional(string, "run")
    image = object({
      name        = string
      pull_policy = optional(string, "IfNotPresent")
    })
    execute = optional(object({
      command     = optional(list(string))
      args        = optional(list(string))
      working_dir = optional(string)
      as          = optional(string)
    }))
    resources = optional(object({
      requests = object({
        cpu    = optional(number, 0.1)
        memory = optional(number, 64)
        gpu    = optional(number, 0)
      })
      limits = optional(object({
        cpu    = optional(number, 0)
        memory = optional(number, 0)
        gpu    = optional(number, 0)
      }))
    }))
    envs = optional(list(object({
      name = optional(string)
      type = optional(string, "text")
      text = optional(object({
        content = string
      }))
      config = optional(object({
        name = string
        key  = optional(string)
      }))
    })))
    mounts = optional(list(object({
      path      = string
      read_only = optional(bool, false)
      type      = optional(string, "config")
      config = optional(object({
        name            = string
        key             = optional(string)
        mode            = optional(string, "0644")
        disable_changed = optional(bool, false)
      }))
      storage = optional(object({
        name     = string
        sub_path = optional(string)
      }))
    })))
  }))
}
